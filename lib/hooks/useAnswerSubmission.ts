/**
 * 答题提交 Hook
 *
 * 封装复杂的答题提交逻辑，包括：
 * - 答案验证和判分
 * - 错题管理
 * - 进度更新
 * - 云端记录同步
 */

import { useRef, useCallback, useState } from 'react'
import type { Question } from '@/lib/question-bank'
import { isAnswerAccepted, normalizeAnswer } from '@/lib/question-bank'
import { errorTagsForAnswer, knowledgeTagsForQuestion, explainAnswerDifference } from '@/lib/utils/answer-utils'
import { LESSON_QUESTION_LIMIT } from '@/lib/utils/lesson-utils'
import { createMistakeQueue, matchesMistakeScope } from '@/lib/learning/mistake-queue.mjs'

const mistakeQueue = typeof window === 'undefined' ? null : createMistakeQueue()

export type GradeResult = {
  correct: boolean
  verdict: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect'
  explanation: string
  source: 'ai' | 'rule'
  aiVerdict?: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect' | null
  memberRequired?: boolean
}

export type SubmissionContext = {
  question: Question
  answer: string
  practiceMode: 'lesson' | 'mistakes' | 'mixed'
  replayMode: boolean
  currentLesson: number
  userId?: string
  authGeneration?: number
  membershipStatus?: 'anonymous' | 'loading' | 'free' | 'member'
  textbookId?: string
  questionLimit?: number
  atomicMistakeStateAvailable?: boolean
  expectedMistakeVersion?: number
  currentMistake?: boolean
  onMistakeQueueChange?: (notice: string) => void
  onMistakeStateUpdate?: (state: {questionId: string; isMistake: boolean; version: number}) => void
}

export type SubmissionPersistence = 'saved' | 'queued' | 'failed' | 'local'

export type ProgressUpdate = {
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
  dueQuestionIds?: string[]
}

type MemberGrade = {
  verdict: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect'
  explanation: string
}

async function requestMemberGrade(question: Question, answer: string): Promise<{
  grade: MemberGrade | null
  memberRequired: boolean
}> {
  try {
    const response = await fetch('/api/grade-answer', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        answer,
        standardAnswer: question.answer,
        acceptedAnswers: question.acceptedAnswers ?? [],
        hint: question.hint,
      }),
    })
    const payload = await response.json().catch(() => null) as Partial<MemberGrade> & { memberRequired?: boolean } | null
    if (!response.ok) {
      return { grade: null, memberRequired: Boolean(payload?.memberRequired) }
    }
    if (
      payload?.verdict !== 'correct' &&
      payload?.verdict !== 'mostly_correct' &&
      payload?.verdict !== 'needs_fix' &&
      payload?.verdict !== 'incorrect'
    ) {
      return { grade: null, memberRequired: false }
    }
    return {
      grade: {
        verdict: payload.verdict,
        explanation: typeof payload.explanation === 'string' ? payload.explanation : '',
      },
      memberRequired: false,
    }
  } catch {
    return { grade: null, memberRequired: false }
  }
}

export function answerRecordMode(practiceMode: SubmissionContext['practiceMode'], replayMode: boolean) {
  if (practiceMode === 'mistakes') return 'mistakes'
  if (practiceMode === 'lesson') return replayMode ? 'lesson_replay' : 'lesson'
  return 'review'
}

export function useAnswerSubmission(activeUserId = '', activeTextbookId = '', activeAuthGeneration = 0) {
  const activeScopeRef = useRef({userId: activeUserId, textbookId: activeTextbookId, generation: activeAuthGeneration})
  activeScopeRef.current = {userId: activeUserId, textbookId: activeTextbookId, generation: activeAuthGeneration}
  const submittedQuestionRef = useRef<Question | null>(null)
  const replayMistakesRef = useRef<Question[]>([])
  const replayCorrectRef = useRef(0)
  const [mistakeQueueRevision, setMistakeQueueRevision] = useState(0)

  const sendQueuedMistake = useCallback(async (item: Record<string, unknown>, generation: number) => {
    const scope = activeScopeRef.current
    if (!matchesMistakeScope(scope, String(item.userId), String(item.textbookId), generation)) return {status: 503, body: null}
    const response = await fetch('/api/record-answer', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(item),
    })
    const body = await response.json().catch(() => null)
    if (!matchesMistakeScope(activeScopeRef.current, String(item.userId), String(item.textbookId), generation)) return {status: 503, body: null}
    return {status: response.status, body}
  }, [])

  const retryMistakeQueue = useCallback(async (userId: string, textbookId: string, generation = activeScopeRef.current.generation, onStateUpdate?: SubmissionContext['onMistakeStateUpdate']) => {
    if (!mistakeQueue) return {notice: '设备队列不可用', results: [], count: 0, blocked: 0}
    if (!matchesMistakeScope(activeScopeRef.current, userId, textbookId, generation)) {
      return {notice: '账号状态已变化，未发送待同步记录', results: [], count: 0, blocked: 0}
    }
    const candidateStates = new Map<string, {questionId: string; isMistake: boolean; version: number}>()
    const results = await mistakeQueue.flush(async (item) => {
      const response = await sendQueuedMistake(item, generation)
      const state = response.body?.mistakeState
      if (response.status === 200 && response.body?.mistakeStateAvailable === true &&
        state && state.questionId === item.questionId && typeof state.isMistake === 'boolean' && Number.isSafeInteger(state.version)) {
        candidateStates.set(String(item.clientRequestId), state)
      }
      return response
    }, userId, textbookId)
    if (matchesMistakeScope(activeScopeRef.current, userId, textbookId, generation)) {
      for (const result of results) {
        const state = result.persisted ? candidateStates.get(result.clientRequestId) : undefined
        if (state) onStateUpdate?.(state)
      }
    }
    const items = mistakeQueue.list(userId, textbookId)
    setMistakeQueueRevision((revision) => revision + 1)
    const failed = items.filter((item: {status?: string}) => item.status === 'conflict' || item.status === 'failed').length
    const blocked = items.filter((item: {status?: string}) => item.status === 'blocked').length
    if (items.length) {
      const hasConflict = items.some((item: {status?: string}) => item.status === 'conflict')
      const missingVersion = items.some((item: {expectedMistakeVersion?: number | null}) => !Number.isSafeInteger(item.expectedMistakeVersion))
      const notice = hasConflict
        ? '部分答题与云端错题版本冲突，记录仍保留在本设备；不会自动改写版本。'
        : missingVersion
          ? '部分答题已暂存但缺少协议版本，保持阻塞且不会自动发送。'
          : failed
            ? '部分答题暂未同步，记录已保留在本设备。'
            : '同题后续答题等待前一条确认，记录已保留在本设备。'
      return {notice, results, count: items.length, blocked}
    }
    return {notice: '', results, count: 0, blocked: 0}
  }, [sendQueuedMistake])

  /**
   * 本地判分（规则检查）
   */
  const gradeLocally = useCallback((question: Question, answer: string): boolean => {
    return question.options
      ? isAnswerAccepted(question, answer)
      : isAnswerAccepted(question, answer)
  }, [])

  /**
   * 生成反馈文本
   */
  const generateFeedback = useCallback((
    question: Question,
    answer: string,
    matches: boolean
  ): string => {
    if (matches) {
      return '句型结构正确，继续保持主动输出。'
    }

    const expectedAnswer =
      question.options
        ?.find((option) => option.startsWith(`${question.answer}：`))
        ?.slice(2)
        .trim() || question.answer

    if (question.options && !matches) {
      return `你选择了「${answer}」，正确选项是「${expectedAnswer}」。`
    }

    return explainAnswerDifference(expectedAnswer, answer)
  }, [])

  /**
   * 更新错题集合
   */
  const updateMistakes = useCallback((
    currentMistakes: Question[],
    question: Question,
    isCorrect: boolean,
    practiceMode: 'lesson' | 'mistakes' | 'mixed',
    replayMode: boolean,
    questionLimit = LESSON_QUESTION_LIMIT,
  ): Question[] => {
    if (!isCorrect) {
      // 添加到错题集
      const alreadyExists = currentMistakes.some((item) => item.id === question.id)
      if (alreadyExists) {
        return currentMistakes
      }

      // 更新 replay 引用
      if (replayMode && !replayMistakesRef.current.some((item) => item.id === question.id)) {
        replayMistakesRef.current = [...replayMistakesRef.current, question]
      }

      return [...currentMistakes, question]
    } else if (practiceMode === 'mistakes' || replayMode) {
      // 从错题集移除
      if (replayMode) {
        replayMistakesRef.current = replayMistakesRef.current.filter(
          (item) => item.id !== question.id
        )
        replayCorrectRef.current = Math.min(questionLimit, replayCorrectRef.current + 1)
      }

      return currentMistakes.filter((item) => item.id !== question.id)
    }

    return currentMistakes
  }, [])

  /**
   * 更新课程进度
   */
  const updateProgress = useCallback((
    currentProgress: ProgressUpdate,
    question: Question,
    isCorrect: boolean,
    replayMode: boolean,
    questionLimit = LESSON_QUESTION_LIMIT,
  ): Partial<ProgressUpdate> => {
    const lessonIndex = question.lessonId - 1
    const updates: Partial<ProgressUpdate> = {}

    if (replayMode) {
      // Replay 模式：更新正确数
      if (isCorrect) {
        updates.lessonCorrect = {
          ...currentProgress.lessonCorrect,
          [lessonIndex]: Math.min(
            questionLimit,
            (currentProgress.lessonCorrect[lessonIndex] ?? 0) + 1
          ),
        }
      }
    }

    return updates
  }, [])

  /**
   * 记录答题到服务端
   */
  const recordAnswer = useCallback(async (
    context: SubmissionContext,
    gradeResult: GradeResult
  ): Promise<SubmissionPersistence> => {
    // 自定义教材不写入教材范围 RPC。这样即使部署环境还没有最新
    // textbook_id 迁移，导入教材也只使用当前用户自己的本地进度。
    if (!context.userId || context.textbookId !== 'builtin-japanese-syntax') return 'local'

    if (context.atomicMistakeStateAvailable) {
      if (!mistakeQueue) {
        context.onMistakeQueueChange?.('设备队列不可写，答案未提交；当前输入仍保留，请重试。')
        return 'failed'
      }
      let queued = false
      try {
        const clientRequestId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
        await mistakeQueue.enqueue({
          clientRequestId, userId: context.userId, textbookId: context.textbookId,
          questionId: context.question.id, expectedMistakeVersion: context.expectedMistakeVersion,
          requireVersioned: true,
          expectedIsMistake: !gradeResult.correct ? true : ['mistakes', 'lesson_replay'].includes(answerRecordMode(context.practiceMode, context.replayMode)) ? false : Boolean(context.currentMistake),
          lessonId: context.question.lessonId, questionLimit: context.questionLimit ?? LESSON_QUESTION_LIMIT,
          answer: context.answer, correct: gradeResult.correct,
          verdict: gradeResult.aiVerdict ?? gradeResult.verdict,
          errorTags: gradeResult.correct ? [] : errorTagsForAnswer(context.question, context.answer),
          knowledgeTags: knowledgeTagsForQuestion(context.question),
          mode: answerRecordMode(context.practiceMode, context.replayMode),
        })
        queued = true
        const result = await retryMistakeQueue(context.userId, context.textbookId, context.authGeneration ?? activeScopeRef.current.generation, context.onMistakeStateUpdate)
        context.onMistakeQueueChange?.(result.notice)
        return result.count > 0 ? 'queued' : 'saved'
      } catch {
        context.onMistakeQueueChange?.(queued
          ? '答案已暂存到设备队列，但同步检查失败；可稍后重试。'
          : '设备队列不可写，答案未提交；当前输入仍保留，请重试。')
        return queued ? 'queued' : 'failed'
      }
    }

    try {
      const response = await fetch('/api/record-answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          questionId: context.question.id,
          textbookId: context.textbookId ?? 'builtin-japanese-syntax',
          lessonId: context.question.lessonId,
          questionLimit: context.questionLimit ?? LESSON_QUESTION_LIMIT,
          answer: context.answer,
          correct: gradeResult.correct,
          verdict: gradeResult.aiVerdict ?? gradeResult.verdict,
          errorTags: gradeResult.correct ? [] : errorTagsForAnswer(context.question, context.answer),
          knowledgeTags: knowledgeTagsForQuestion(context.question),
          mode: answerRecordMode(context.practiceMode, context.replayMode),
        }),
      })

      if (!response.ok) return 'local'
      await response.json()
      return 'saved'
    } catch {
      console.warn('Unable to persist answer; using local fallback')
      return 'local'
    }
  }, [retryMistakeQueue])

  /**
   * 提交答案（主函数）
   */
  const submitAnswer = useCallback(async (
    context: SubmissionContext,
    currentProgress: ProgressUpdate
  ): Promise<{
    gradeResult: GradeResult
    progressUpdates: Partial<ProgressUpdate>
    persistence: SubmissionPersistence
  }> => {
    const { question, answer } = context

    // 本地判分
    const localMatches = gradeLocally(question, answer)
    const localExplanation = generateFeedback(question, answer, localMatches)

    let aiGrade: MemberGrade | null = null
    let memberRequired = context.membershipStatus === 'free' && !localMatches
    if (context.membershipStatus === 'member' && !localMatches) {
      const result = await requestMemberGrade(question, answer)
      aiGrade = result.grade
      memberRequired = result.memberRequired || memberRequired
    }

    const aiCorrect = aiGrade
      ? aiGrade.verdict === 'correct' || aiGrade.verdict === 'mostly_correct'
      : null
    const finalCorrect = aiCorrect ?? localMatches

    // 构建判分结果。会员的非精确答案会交给服务端 AI；免费用户继续使用规则判分。
    const gradeResult: GradeResult = {
      correct: finalCorrect,
      verdict: aiGrade?.verdict ?? (localMatches ? 'correct' : 'needs_fix'),
      explanation: aiGrade?.explanation || localExplanation,
      source: aiGrade ? 'ai' : 'rule',
      aiVerdict: aiGrade?.verdict ?? null,
      memberRequired,
    }

    // 保存提交的问题引用
    submittedQuestionRef.current = question

    // 更新错题集合
    const updatedMistakes = updateMistakes(
      currentProgress.mistakes,
      question,
      finalCorrect,
      context.practiceMode,
      context.replayMode,
      context.questionLimit,
    )

    // 更新进度
    const progressUpdates = updateProgress(
      currentProgress,
      question,
      finalCorrect,
      context.replayMode,
      context.questionLimit,
    )

    // 更新复习队列（混合模式）。本轮已经作答的题目不应在用户
    // 返回首页后立刻再次出现；服务端仍会根据答题结果保存下一次复习时间。
    if (context.practiceMode === 'mixed' && currentProgress.dueQuestionIds) {
      progressUpdates.dueQuestionIds = currentProgress.dueQuestionIds.filter(
        (id) => id !== question.id
      )
    }

    // 添加错题更新
    progressUpdates.mistakes = updatedMistakes

    const persistence = await recordAnswer(context, gradeResult)

    return {
      gradeResult,
      progressUpdates,
      persistence,
    }
  }, [gradeLocally, generateFeedback, updateMistakes, updateProgress, recordAnswer])

  /**
   * 重置 replay 状态
   */
  const resetReplayState = useCallback(() => {
    replayMistakesRef.current = []
    replayCorrectRef.current = 0
  }, [])

  /**
   * 获取 replay 状态
   */
  const getReplayState = useCallback(() => {
    return {
      mistakes: replayMistakesRef.current,
      correct: replayCorrectRef.current,
    }
  }, [])

  return {
    submitAnswer,
    retryMistakeQueue,
    resetReplayState,
    getReplayState,
    submittedQuestion: submittedQuestionRef.current,
  }
}
