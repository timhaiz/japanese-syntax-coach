import type { Question } from '@/lib/question-bank'
import { normalizeAnswer, isAnswerAccepted } from '@/lib/question-bank'
import { errorTagsForAnswer, knowledgeTagsForQuestion, explainAnswerDifference } from './answer-utils'

export type LocalVerdict = 'correct' | 'needs_fix' | 'incorrect'
export type AiVerdict = 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect' | null

/**
 * 计算本地判分结果
 */
export function calculateLocalVerdict(
  question: Question,
  userAnswer: string,
): { verdict: LocalVerdict; matches: boolean } {
  const matches = question.options
    ? isAnswerAccepted(question, userAnswer)
    : isAnswerAccepted(question, userAnswer)

  if (matches) {
    return { verdict: 'correct', matches: true }
  }

  const expected = normalizeAnswer(question.answer)
  const actual = normalizeAnswer(userAnswer)
  const shared =
    expected.length && actual.length
      ? [...expected].filter((char, index) => char === actual[index]).length /
        Math.max(expected.length, actual.length)
      : 0

  return {
    verdict: shared >= 0.55 ? 'needs_fix' : 'incorrect',
    matches: false,
  }
}

/**
 * 生成判分反馈文本
 */
export function generateFeedback(
  question: Question,
  userAnswer: string,
  matches: boolean,
): string {
  if (matches) {
    return '句型结构正确，继续保持主动输出。'
  }

  // 选择题显示选择的选项和正确答案
  if (question.options) {
    const expectedAnswer =
      question.options
        .find((option) => option.startsWith(`${question.answer}：`))
        ?.slice(2)
        .trim() || question.answer
    return `你选择了「${userAnswer}」，正确选项是「${expectedAnswer}」。`
  }

  // 其他题型分析答案差异
  const expectedAnswer =
    question.options
      ?.find((option) => option.startsWith(`${question.answer}：`))
      ?.slice(2)
      .trim() || question.answer

  return explainAnswerDifference(expectedAnswer, userAnswer)
}

/**
 * 答题记录参数
 */
export type AnswerRecordParams = {
  questionId: string
  lessonId: number
  answer: string
  correct: boolean
  verdict: LocalVerdict | AiVerdict
  errorTags: string[]
  knowledgeTags: string[]
  mode: 'lesson' | 'lesson_replay' | 'review'
}

/**
 * 提交答题记录到服务端
 */
export async function recordAnswer(params: AnswerRecordParams): Promise<void> {
  try {
    const response = await fetch('/api/record-answer', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    })
    if (!response.ok) return
    await response.json()
  } catch {
    console.warn('Unable to persist answer; using local fallback')
  }
}

/**
 * 构建答题记录参数
 */
export function buildAnswerRecordParams(
  question: Question,
  userAnswer: string,
  isCorrect: boolean,
  verdict: LocalVerdict | AiVerdict,
  practiceMode: 'lesson' | 'mistakes' | 'mixed',
  replayMode: boolean,
): AnswerRecordParams {
  return {
    questionId: question.id,
    lessonId: question.lessonId,
    answer: userAnswer,
    correct: isCorrect,
    verdict: verdict || 'incorrect',
    errorTags: isCorrect ? [] : errorTagsForAnswer(question, userAnswer),
    knowledgeTags: knowledgeTagsForQuestion(question),
    mode:
      practiceMode === 'lesson'
        ? replayMode
          ? 'lesson_replay'
          : 'lesson'
        : 'review',
  }
}

/**
 * 判断答案是否正确（综合 AI 和本地判分）
 */
export function isAnswerCorrect(
  aiVerdict: AiVerdict,
  localMatches: boolean,
): boolean {
  if (aiVerdict) {
    return aiVerdict === 'correct' || aiVerdict === 'mostly_correct'
  }
  return localMatches
}

/**
 * 获取用户提交的答案文本
 */
export function getSubmittedAnswer(
  question: Question,
  selectedChoice: string,
  tokenAnswer: string,
): string {
  if (question.type === '翻译' || question.type === '问答') {
    return tokenAnswer
  }
  return selectedChoice
}

/**
 * 获取期望答案文本（用于显示）
 */
export function getExpectedAnswer(question: Question): string {
  if (question.options) {
    const option = question.options.find((opt) => opt.startsWith(`${question.answer}：`))
    return option?.slice(2).trim() || question.answer
  }
  return question.answer
}
