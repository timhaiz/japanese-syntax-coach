/**
 * 课程进度管理 Hook
 *
 * 统一管理课程进度计算逻辑，包括：
 * - 课程完成度计算
 * - 锁定状态判断
 * - 进度百分比
 * - 下一课推荐
 */

import { useMemo } from 'react'
import type { Question } from '@/lib/question-bank'
import {
  LESSON_QUESTION_LIMIT,
  clampLessonAnswered,
  contiguousCompletedLessons,
} from '@/lib/utils/lesson-utils'

export type LessonWithProgress = {
  id: number
  title: string
  progress: number
  locked: boolean
  description?: string
  mistakeCount?: number
}

export type ProgressMetrics = {
  overallProgress: number
  completedCount: number
  totalCount: number
  totalAnswered: number
  nextLessonIndex: number
  allCompleted: boolean
}

export function useLessonProgress(
  lessons: Array<{ id: number; title: string; description?: string }>,
  lessonDone: Record<number, number>,
  lessonCorrect: Record<number, number>,
  completedLessons: number[],
  mistakes: Question[]
) {
  /**
   * 计算有效的完成课程列表
   */
  const effectiveCompletedLessons = useMemo(() => {
    return contiguousCompletedLessons(completedLessons)
  }, [completedLessons])

  /**
   * 计算下一课索引
   */
  const nextLessonIndex = useMemo(() => {
    if (effectiveCompletedLessons.length === 0) return 0
    const lastCompleted = Math.max(...effectiveCompletedLessons)
    return Math.min(lastCompleted + 1, lessons.length - 1)
  }, [effectiveCompletedLessons, lessons.length])

  /**
   * 计算每课的进度和锁定状态
   */
  const lessonsWithProgress = useMemo((): LessonWithProgress[] => {
    return lessons.map((lesson, index) => {
      const answered = clampLessonAnswered(lessonDone[index] ?? 0)
      const progress = Math.round((answered / LESSON_QUESTION_LIMIT) * 100)

      // 锁定逻辑：必须完成前一课才能解锁
      const locked = index > 0 && !effectiveCompletedLessons.includes(index - 1)

      // 统计当前课的错题数量
      const lessonIdStr = String(lesson.id).padStart(2, '0')
      const mistakeCount = mistakes.filter(
        (m) => m.id.startsWith(`L${lessonIdStr}-`)
      ).length

      return {
        id: lesson.id,
        title: lesson.title,
        description: lesson.description,
        progress,
        locked,
        mistakeCount,
      }
    })
  }, [lessons, lessonDone, effectiveCompletedLessons, mistakes])

  /**
   * 计算总体进度指标
   */
  const metrics = useMemo((): ProgressMetrics => {
    const overallProgress = Math.round(
      lessonsWithProgress.reduce((sum, lesson) => sum + lesson.progress, 0) /
        lessonsWithProgress.length
    )

    const totalAnswered = Object.values(lessonDone).reduce(
      (sum, count) => sum + clampLessonAnswered(count),
      0
    )

    return {
      overallProgress,
      completedCount: effectiveCompletedLessons.length,
      totalCount: lessons.length,
      totalAnswered,
      nextLessonIndex,
      allCompleted: effectiveCompletedLessons.length === lessons.length,
    }
  }, [lessonsWithProgress, lessonDone, effectiveCompletedLessons, lessons.length, nextLessonIndex])

  /**
   * 获取当前推荐课程
   */
  const currentLesson = useMemo(() => {
    return lessonsWithProgress[nextLessonIndex] ?? lessonsWithProgress[0]
  }, [lessonsWithProgress, nextLessonIndex])

  /**
   * 判断某课是否已完成
   */
  const isLessonCompleted = useMemo(() => {
    return (lessonIndex: number) => effectiveCompletedLessons.includes(lessonIndex)
  }, [effectiveCompletedLessons])

  /**
   * 判断某课是否可以解锁
   */
  const canUnlockLesson = useMemo(() => {
    return (lessonIndex: number) => {
      if (lessonIndex === 0) return true
      return effectiveCompletedLessons.includes(lessonIndex - 1)
    }
  }, [effectiveCompletedLessons])

  /**
   * 获取课程学习建议
   */
  const getLessonRecommendation = useMemo(() => {
    return (lessonIndex: number): string => {
      const lesson = lessonsWithProgress[lessonIndex]
      if (!lesson) return ''

      if (lesson.locked) {
        return '请先完成前面的课程'
      }

      if (lesson.progress === 0) {
        return '开始学习'
      }

      if (lesson.progress < 100) {
        return '继续学习'
      }

      if (lesson.mistakeCount && lesson.mistakeCount > 0) {
        return `复习错题（${lesson.mistakeCount}）`
      }

      return '已完成'
    }
  }, [lessonsWithProgress])

  return {
    lessonsWithProgress,
    metrics,
    currentLesson,
    effectiveCompletedLessons,
    isLessonCompleted,
    canUnlockLesson,
    getLessonRecommendation,
  }
}
