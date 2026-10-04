import { useEffect, useState } from 'react'
import type { Question } from '@/lib/question-bank'
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
  textbookId = 'builtin-japanese-syntax',
  questionCounts: number[] = [],
  questions: Question[] = [],
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
    const saved = completedLessonsStorage.get(textbookId)
    setCompletedLessons(
      saved.filter((n) => Number.isInteger(n) && n >= 0 && n < questionCounts.length),
    )
    setCompletedLoaded(true)
  }, [cloudLoaded, cloudApplied, textbookId, questionCounts.length])

  // 加载课程进度和正确数
  useEffect(() => {
    if (!cloudLoaded) return
    if (cloudApplied) {
      setLessonLoaded(true)
      return
    }
    const savedProgress = lessonProgressStorage.get(textbookId)
    const normalized = Object.fromEntries(
      Object.entries(savedProgress)
        .filter(
          ([index, count]) =>
            Number.isInteger(Number(index)) &&
            Number(index) >= 0 &&
            Number(index) < questionCounts.length &&
            typeof count === 'number',
        )
        .map(([index, count]) => {
          const lessonIndex = Number(index)
          return [lessonIndex, clampLessonAnswered(count, questionCounts[lessonIndex])]
        }),
    )
    setLessonDone(normalized)
    setCompletedLessons((value) =>
      completedFromLessonProgress(
        normalized,
        value,
        {},
        questionCounts.length,
        questionCounts,
      ),
    )

    const savedCorrect = lessonCorrectStorage.get(textbookId)
    const normalizedCorrect = Object.fromEntries(
      Object.entries(savedCorrect)
        .filter(
          ([index, count]) =>
            Number.isInteger(Number(index)) &&
            Number(index) >= 0 &&
            Number(index) < questionCounts.length &&
            typeof count === 'number',
        )
        .map(([index, count]) => {
          const lessonIndex = Number(index)
          return [lessonIndex, clampLessonCorrect(count, questionCounts[lessonIndex])]
        }),
    )
    setLessonCorrect(normalizedCorrect)
    setLessonLoaded(true)
  }, [cloudLoaded, cloudApplied, textbookId, questionCounts])

  // 加载错题记录
  useEffect(() => {
    if (!cloudLoaded) return
    if (cloudApplied) {
      setMistakesLoaded(true)
      return
    }
    const questionsById = new Map(questions.map((question) => [question.id, question]))
    const saved = mistakesStorage.get(textbookId, (id) => questionsById.get(id))
    setMistakes(saved)
    setMistakesLoaded(true)
  }, [cloudLoaded, cloudApplied, textbookId, questions])

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
