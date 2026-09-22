import { useEffect, useState } from 'react'
import { getSupabaseBrowser } from '@/lib/supabase'
import type { Question } from '@/lib/question-bank'
import { courses } from '@/lib/courses'
import {
  clampLessonAnswered,
  clampLessonCorrect,
  completedFromLessonProgress,
} from '@/lib/utils/lesson-utils'
import {
  lessonProgressStorage,
  lessonCorrectStorage,
  completedLessonsStorage,
  mistakesStorage,
} from '@/lib/utils/storage-utils'

type LocalProgressState = {
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
  completedLoaded: boolean
  lessonLoaded: boolean
  mistakesLoaded: boolean
}

/**
 * 管理本地存储的初始加载
 * 负责在组件挂载时从 localStorage 读取学习数据
 */
export function useLocalProgressLoader(
  cloudLoaded: boolean,
  cloudApplied: boolean,
  hasAuthUser: boolean,
) {
  const [lessonDone, setLessonDone] = useState<Record<number, number>>({})
  const [lessonCorrect, setLessonCorrect] = useState<Record<number, number>>({})
  const [completedLessons, setCompletedLessons] = useState<number[]>([])
  const [mistakes, setMistakes] = useState<Question[]>([])
  const [completedLoaded, setCompletedLoaded] = useState(false)
  const [lessonLoaded, setLessonLoaded] = useState(false)
  const [mistakesLoaded, setMistakesLoaded] = useState(false)

  // 加载已完成课程列表
  useEffect(() => {
    if (!cloudLoaded) return
    if (cloudApplied) {
      setCompletedLoaded(true)
      return
    }
    if (getSupabaseBrowser() && !hasAuthUser) {
      setCompletedLessons([])
      setCompletedLoaded(true)
      return
    }
    const saved = completedLessonsStorage.get()
    setCompletedLessons(
      saved.filter((n) => Number.isInteger(n) && n >= 0 && n < courses.length),
    )
    setCompletedLoaded(true)
  }, [cloudLoaded, cloudApplied, hasAuthUser])

  // 加载课程进度和正确数
  useEffect(() => {
    if (!cloudLoaded) return
    if (cloudApplied) {
      setLessonLoaded(true)
      return
    }
    if (getSupabaseBrowser() && !hasAuthUser) {
      setLessonDone({})
      setLessonCorrect({})
      setLessonLoaded(true)
      return
    }

    const savedProgress = lessonProgressStorage.get()
    const normalized = Object.fromEntries(
      Object.entries(savedProgress)
        .filter(
          ([index, count]) =>
            Number.isInteger(Number(index)) &&
            Number(index) >= 0 &&
            Number(index) < courses.length &&
            typeof count === 'number',
        )
        .map(([index, count]) => [Number(index), clampLessonAnswered(count)]),
    )
    setLessonDone(normalized)
    setCompletedLessons((value) => completedFromLessonProgress(normalized, value))

    const savedCorrect = lessonCorrectStorage.get()
    const normalizedCorrect = Object.fromEntries(
      Object.entries(savedCorrect)
        .filter(
          ([index, count]) =>
            Number.isInteger(Number(index)) &&
            Number(index) >= 0 &&
            Number(index) < courses.length &&
            typeof count === 'number',
        )
        .map(([index, count]) => [Number(index), clampLessonCorrect(count)]),
    )
    setLessonCorrect(normalizedCorrect)
    setLessonLoaded(true)
  }, [cloudLoaded, cloudApplied, hasAuthUser])

  // 加载错题记录
  useEffect(() => {
    if (!cloudLoaded) return
    if (cloudApplied) {
      setMistakesLoaded(true)
      return
    }
    if (getSupabaseBrowser() && !hasAuthUser) {
      setMistakes([])
      setMistakesLoaded(true)
      return
    }
    const saved = mistakesStorage.get()
    setMistakes(saved)
    setMistakesLoaded(true)
  }, [cloudLoaded, cloudApplied, hasAuthUser])

  return {
    lessonDone,
    lessonCorrect,
    completedLessons,
    mistakes,
    completedLoaded,
    lessonLoaded,
    mistakesLoaded,
    setLessonDone,
    setLessonCorrect,
    setCompletedLessons,
    setMistakes,
  }
}
