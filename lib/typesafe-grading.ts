/**
 * TypeSafe Jev 判分集成
 *
 * 使用 TypeSafe 的 Jev 模型进行快速、结构化的答案评估
 * 相比 OpenAI：速度提升 3-5x，成本降低 80%+
 */

export type JevGradeResult = {
  verdict: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect'
  correctedAnswer: string
  errorTags: string[]
  explanation: string
  confidence?: number
  qualityScore?: number
}

/**
 * 使用 TypeSafe Jev 进行答案判分
 */
export async function gradeWithJev(input: {
  answer: string
  standardAnswer: string
  context?: string
  userAgent?: string
}): Promise<JevGradeResult | null> {
  const apiKey = process.env.TYPESAFE_API_KEY

  if (!apiKey) {
    console.warn('TYPESAFE_API_KEY not configured, skipping Jev grading')
    return null
  }

  try {
    const state = {
      question_context: input.context || '',
      standard_answer: input.standardAnswer,
      user_answer: input.answer,
    }

    const response = await fetch('https://api.typesafe.ai/v1/systemone', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        ...(input.userAgent ? { 'User-Agent': input.userAgent } : {}),
      },
      body: JSON.stringify({
        model: 'jev-latest',
        state,
        questions: {
          // 评估答案质量（0-100 分数）
          quality: {
            type: 'score',
            instructions: '评估用户答案与标准答案的语义正确性和质量',
            criteria: [
              '完全错误或无关：语义完全不符，或答非所问',
              '部分正确但有重要错误：理解方向对但有关键语法或词汇错误',
              '大部分正确但有小瑕疵：主要内容正确，仅有助词、标点等小问题',
              '完全正确或等价表达：语义完全一致，表达方式可能略有不同',
            ],
          },

          // 判定最终结果
          verdict: {
            type: 'choice',
            instructions: '根据语义正确性给出判定结果',
            criteria: {
              correct: '完全正确或完全等价的表达方式（允许标点差异）',
              mostly_correct: '主要内容正确，但有助词、活用等小错误，不影响理解',
              needs_fix: '有明显语法错误或词汇错误，需要修正',
              incorrect: '语义完全错误或答非所问',
            },
          },

          // 错误类型分类
          error_type: {
            type: 'choice',
            instructions: '如果答案有错误，识别主要错误类型',
            criteria: {
              none: '无错误',
              particle: '助词使用错误（は、が、を、に、で、と等）',
              conjugation: '动词或形容词活用错误（ます形、て形、た形等）',
              word_order: '句型结构或语序错误',
              vocabulary: '词汇选择错误或使用不当',
              kana: '假名拼写错误（ひらがな或カタカナ）',
              semantic: '语义理解错误，答非所问',
              naturalness: '表达不自然但语法基本正确',
            },
          },

          // 是否需要人工复审
          needs_review: {
            type: 'noul',
            instructions: '这个答案是否需要人工复审？',
            criteria: {
              true: '答案模糊、边界情况、或判定不确定',
              false: '明确正确或明确错误，判定有把握',
            },
          },
        },
      }),
    })

    if (!response.ok) {
      const status = response.status
      if (status === 429 || status === 529) {
        console.warn('TypeSafe rate limit or overload, will retry')
      }
      throw new Error(`TypeSafe API error: ${status}`)
    }

    const data = await response.json()
    const answers = data.answers

    // 提取结果
    const verdict = answers.verdict.choice as JevGradeResult['verdict']
    const errorType = answers.error_type.choice
    const qualityScore = calculateQualityScore(answers.quality)
    const confidence = answers.verdict.confidence

    // 生成解释文本
    const explanation = generateExplanation(verdict, errorType, qualityScore, input)

    return {
      verdict,
      correctedAnswer: input.standardAnswer,
      errorTags: errorType !== 'none' ? [mapErrorTypeToTag(errorType)] : [],
      explanation,
      confidence,
      qualityScore,
    }
  } catch (error) {
    console.warn('Jev grading failed:', error)
    return null
  }
}

/**
 * 计算质量分数（从 Score 原语的结果）
 */
function calculateQualityScore(scoreResult: any): number {
  // TypeSafe Score 返回概率分布
  // 我们计算加权平均分数
  if (!scoreResult || !scoreResult.score) {
    return 0
  }

  // score.levels 包含每个级别的概率
  // 级别 0 = 完全错误，级别 3 = 完全正确
  const levels = scoreResult.score.levels || []
  let weightedSum = 0
  let totalProb = 0

  levels.forEach((prob: number, index: number) => {
    weightedSum += prob * index
    totalProb += prob
  })

  // 归一化到 0-100
  if (totalProb > 0) {
    const normalizedScore = (weightedSum / totalProb) / (levels.length - 1)
    return Math.round(normalizedScore * 100)
  }

  return 0
}

/**
 * 生成用户友好的解释文本
 */
function generateExplanation(
  verdict: string,
  errorType: string,
  qualityScore: number,
  input: { answer: string; standardAnswer: string; context?: string }
): string {
  if (verdict === 'correct') {
    return '句型结构正确，继续保持主动输出。'
  }

  if (verdict === 'mostly_correct') {
    return `主要内容正确（质量：${qualityScore}%），但有小瑕疵。参考标准答案：${input.standardAnswer}`
  }

  // 根据错误类型提供针对性建议
  const errorMessages: Record<string, string> = {
    particle: '助词使用有误。请注意「は」「が」「を」「に」等助词的正确用法。',
    conjugation: '动词或形容词活用有误。请检查时态和活用形式。',
    word_order: '句型结构或语序有误。请对照标准句型练习。',
    vocabulary: '词汇选择不当。请确认词汇含义和使用场景。',
    kana: '假名拼写有误。请仔细检查平假名和片假名。',
    semantic: '语义理解有误。请重新理解题目要求。',
    naturalness: '表达不够自然。建议参考标准答案的表达方式。',
  }

  const errorMsg = errorMessages[errorType] || '请对照标准答案检查。'

  if (verdict === 'needs_fix') {
    return `${errorMsg} 标准答案：${input.standardAnswer}`
  }

  // incorrect
  return `答案不正确。${errorMsg} 标准答案：${input.standardAnswer}`
}

/**
 * 映射错误类型到现有的错误标签
 */
function mapErrorTypeToTag(errorType: string): string {
  const mapping: Record<string, string> = {
    particle: '助词',
    conjugation: '活用',
    word_order: '句型顺序',
    vocabulary: '词汇',
    kana: '假名',
    semantic: '语义',
    naturalness: '自然度',
  }

  return mapping[errorType] || '其他'
}

/**
 * 批量判分（用于未来优化）
 */
export async function batchGradeWithJev(
  inputs: Array<{
    answer: string
    standardAnswer: string
    context?: string
  }>
): Promise<Array<JevGradeResult | null>> {
  // TypeSafe 支持单次请求多个问题
  // 这里可以优化为批量请求，减少网络往返
  return Promise.all(inputs.map(input => gradeWithJev(input)))
}
