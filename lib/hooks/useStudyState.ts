import { useEffect, useState, useRef } from 'react'
import type { Question } from '@/lib/question-bank'
import {
  clampLessonAnswered,
  clampLessonCorrect,
  completedFromLessonProgress,
} from '@/lib/utils/lesson-utils'

export type StudyState = {
  dueQuestionIds: string[]
  knowledgePointMastery: Record<string, number>
  learningMetrics: {
    correctStreak: number
    errorRate: number
    forgettingRate?: number
    topErrorTags: { tag: string; count: number }[]
  }
}

type UseStudyStateReturn = {
  studyState: StudyState
  studyStateLoaded: boolean
  studyStateError: string
  loadStudyState: () => void
}

/**
 * 管理云端学习状态（复习计划、知识点掌握度、学习指标）
 */
export function useStudyState(
  userId: string,
  onLessonProgressLoaded?: (data: {
    lessonDone: Record<number, number>
    lessonCorrect: Record<number, number>
    completedLessons: number[]
  }) => void,
  textbookId = 'builtin-japanese-syntax',
  questionLimits: number[] = [],
  questions: Question[] = [],
): UseStudyStateReturn {
  const [dueQuestionIds, setDueQuestionIds] = useState<string[]>([])
  const [knowledgePointMastery, setKnowledgePointMastery] = useState<Record<string, number>>({})
  const [learningMetrics, setLearningMetrics] = useState<{
    correctStreak: number
    errorRate: number
    forgettingRate?: number
    topErrorTags: { tag: string; count: number }[]
  }>({ correctStreak: 0, errorRate: 0, topErrorTags: [] })
  const [studyStateLoaded, setStudyStateLoaded] = useState(false)
  const [studyStateError, setStudyStateError] = useState('')
  const [studyStateRetry, setStudyStateRetry] = useState(0)
  const loadedStudyUserId = useRef('')

  useEffect(() => {
    if (!userId) return
    if (textbookId !== 'builtin-japanese-syntax') {
      setDueQuestionIds([])
      setKnowledgePointMastery({})
      setLearningMetrics({ correctStreak: 0, errorRate: 0, topErrorTags: [] })
      setStudyStateError('')
      setStudyStateLoaded(true)
      loadedStudyUserId.current = userId
      return
    }
    let cancelled = false
    setStudyStateLoaded(false)
    setStudyStateError('')

    void (async () => {
      try {
        const response = await fetch(
          `/api/study-state?textbookId=${encodeURIComponent(textbookId)}`,
        )
        if (!response.ok) {
          if (!cancelled)
            setStudyStateError('云端学习记录暂时无法读取，将继续使用当前设备数据。')
          return
        }
        const state = await response.json()
        if (cancelled) return

        const questionIds = new Set(questions.map((question) => question.id))
        setDueQuestionIds(
          Array.isArray(state.dueQuestionIds)
            ? state.dueQuestionIds.filter(
                (id: unknown): id is string =>
                  typeof id === 'string' && (questionIds.size === 0 || questionIds.has(id)),
              )
            : [],
        )
        setKnowledgePointMastery(
          Object.fromEntries(
            (state.knowledgePoints || []).map(
              (item: { knowledge_point: string; mastery: number }) => [
                item.knowledge_point,
                Number(item.mastery) || 0,
              ],
            ),
          ),
        )
        if (state.metrics) setLearningMetrics(state.metrics)

        // 如果云端有持久化的课程进度，回调通知上层
        if (onLessonProgressLoaded) {
          const persistedLessons = Object.fromEntries(
            (state.lessons || []).map(
              (lesson: { lesson_id: number; answered_count: number }) => [
                lesson.lesson_id - 1,
                clampLessonAnswered(lesson.answered_count, questionLimits[lesson.lesson_id - 1]),
              ],
            ),
          )
          const persistedCorrect = Object.fromEntries(
            (state.lessons || [])
              .filter((lesson: { correct_count?: number }) => typeof lesson.correct_count === 'number')
              .map((lesson: { lesson_id: number; correct_count: number }) => [
                lesson.lesson_id - 1,
                clampLessonCorrect(lesson.correct_count, questionLimits[lesson.lesson_id - 1]),
              ]),
          )
          if (Object.keys(persistedLessons).length) {
            onLessonProgressLoaded({
              lessonDone: persistedLessons,
              lessonCorrect: persistedCorrect,
              completedLessons: completedFromLessonProgress(
                persistedLessons,
                (state.lessons || [])
                  .filter((lesson: { completed_at: string | null }) => lesson.completed_at)
                  .map((lesson: { lesson_id: number }) => lesson.lesson_id - 1),
                persistedCorrect,
                questionLimits.length || 24,
                questionLimits,
              ),
            })
          }
        }
      } catch {
        if (!cancelled)
          setStudyStateError('云端学习记录暂时无法读取，将继续使用当前设备数据。')
        console.warn('Unable to load durable study state; using local fallback')
      } finally {
        if (!cancelled) {
          loadedStudyUserId.current = userId
          setStudyStateLoaded(true)
        }
      }
    })()

    return () => {
      cancelled = true
    }
  }, [userId, studyStateRetry, onLessonProgressLoaded, textbookId, questionLimits, questions])

  const loadStudyState = () => {
    setStudyStateRetry((v) => v + 1)
  }

  return {
    studyState: {
      dueQuestionIds,
      knowledgePointMastery,
      learningMetrics,
    },
    studyStateLoaded,
    studyStateError,
    loadStudyState,
  }
}
