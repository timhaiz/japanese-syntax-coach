/**
 * 答题提交 Hook
 *
 * 封装复杂的答题提交逻辑，包括：
 * - 答案验证和判分
 * - 错题管理
 * - 进度更新
 * - 云端记录同步
 */

import { useRef, useCallback } from 'react'
import type { Question } from '@/lib/question-bank'
import { isAnswerAccepted, normalizeAnswer } from '@/lib/question-bank'
import { errorTagsForAnswer, knowledgeTagsForQuestion, explainAnswerDifference } from '@/lib/utils/answer-utils'
import { LESSON_QUESTION_LIMIT } from '@/lib/utils/lesson-utils'

export type GradeResult = {
  correct: boolean
  verdict: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect'
  explanation: string
  source: 'ai' | 'rule' | 'typesafe'
  aiVerdict?: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect' | null
}

export type SubmissionContext = {
  question: Question
  answer: string
  practiceMode: 'lesson' | 'mistakes' | 'mixed'
  replayMode: boolean
  currentLesson: number
  userId?: string
}

export type ProgressUpdate = {
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
  dueQuestionIds?: string[]
}

export function useAnswerSubmission() {
  const submittedQuestionRef = useRef<Question | null>(null)
  const replayMistakesRef = useRef<Question[]>([])
  const replayCorrectRef = useRef(0)

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
    replayMode: boolean
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
        replayCorrectRef.current = Math.min(LESSON_QUESTION_LIMIT, replayCorrectRef.current + 1)
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
    replayMode: boolean
  ): Partial<ProgressUpdate> => {
    const lessonIndex = question.lessonId - 1
    const updates: Partial<ProgressUpdate> = {}

    if (replayMode) {
      // Replay 模式：更新正确数
      if (isCorrect) {
        updates.lessonCorrect = {
          ...currentProgress.lessonCorrect,
          [lessonIndex]: Math.min(
            LESSON_QUESTION_LIMIT,
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
  ): Promise<void> => {
    if (!context.userId) return

    try {
      const response = await fetch('/api/record-answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          questionId: context.question.id,
          lessonId: context.question.lessonId,
          answer: context.answer,
          correct: gradeResult.correct,
          verdict: gradeResult.aiVerdict ?? gradeResult.verdict,
          errorTags: gradeResult.correct ? [] : errorTagsForAnswer(context.question, context.answer),
          knowledgeTags: knowledgeTagsForQuestion(context.question),
          mode:
            context.practiceMode === 'lesson'
              ? context.replayMode
                ? 'lesson_replay'
                : 'lesson'
              : 'review',
        }),
      })

      if (!response.ok) return
      await response.json()
    } catch {
      console.warn('Unable to persist answer; using local fallback')
    }
  }, [])

  /**
   * 提交答案（主函数）
   */
  const submitAnswer = useCallback(async (
    context: SubmissionContext,
    currentProgress: ProgressUpdate
  ): Promise<{
    gradeResult: GradeResult
    progressUpdates: Partial<ProgressUpdate>
  }> => {
    const { question, answer } = context

    // 本地判分
    const localMatches = gradeLocally(question, answer)
    const localExplanation = generateFeedback(question, answer, localMatches)

    // 构建判分结果
    const gradeResult: GradeResult = {
      correct: localMatches,
      verdict: localMatches ? 'correct' : 'needs_fix',
      explanation: localExplanation,
      source: 'rule',
      aiVerdict: null,
    }

    // 保存提交的问题引用
    submittedQuestionRef.current = question

    // 更新错题集合
    const updatedMistakes = updateMistakes(
      currentProgress.mistakes,
      question,
      localMatches,
      context.practiceMode,
      context.replayMode
    )

    // 更新进度
    const progressUpdates = updateProgress(
      currentProgress,
      question,
      localMatches,
      context.replayMode
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

    // 记录到服务端不阻塞本地判分和结果展示。
    // 题目答案由规则层立即判定，云端持久化在后台完成。
    void recordAnswer(context, gradeResult)

    return {
      gradeResult,
      progressUpdates,
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
    resetReplayState,
    getReplayState,
    submittedQuestion: submittedQuestionRef.current,
  }
}
