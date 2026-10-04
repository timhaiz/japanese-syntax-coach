import { useEffect } from 'react'
import type { Question } from '@/lib/question-bank'
import {
  mistakesStorage,
  lessonProgressStorage,
  lessonCorrectStorage,
  completedLessonsStorage,
} from '@/lib/utils/storage-utils'

type LocalStorageSyncProps = {
  cloudLoaded: boolean
  hasAuthUser: boolean
  lessonLoaded: boolean
  mistakesLoaded: boolean
  completedLoaded: boolean
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
  onMistakesLoad: (mistakes: Question[]) => void
  textbookId?: string
  resolveQuestion?: (id: string) => Question | undefined
  questionLimits?: number[]
}

/**
 * 管理本地存储的读写同步
 * 负责在适当时机加载和保存学习数据到 localStorage
 */
export function useLocalStorageSync({
  cloudLoaded,
  hasAuthUser,
  lessonLoaded,
  mistakesLoaded,
  completedLoaded,
  lessonDone,
  lessonCorrect,
  completedLessons,
  mistakes,
  onMistakesLoad,
  textbookId = 'builtin-japanese-syntax',
  resolveQuestion,
  questionLimits = [],
}: LocalStorageSyncProps) {
  // 加载错题记录
  useEffect(() => {
    if (!cloudLoaded) return
    // 如果有认证用户且未应用云端数据，清空本地错题
    if (hasAuthUser) {
      onMistakesLoad([])
      return
    }
    // 从本地存储加载错题
    const saved = mistakesStorage.get(textbookId, resolveQuestion)
    onMistakesLoad(saved)
  }, [cloudLoaded, hasAuthUser, onMistakesLoad, textbookId, resolveQuestion])

  // 保存错题记录
  useEffect(() => {
    if (mistakesLoaded) {
      mistakesStorage.set(mistakes, textbookId)
    }
  }, [mistakes, mistakesLoaded, textbookId])

  // 保存课程进度（合并策略）
  useEffect(() => {
    if (!lessonLoaded) return
    lessonProgressStorage.merge(lessonDone, textbookId, questionLimits)
  }, [lessonDone, lessonLoaded, textbookId, questionLimits])

  // 保存课程正确数
  useEffect(() => {
    if (lessonLoaded) {
      lessonCorrectStorage.set(lessonCorrect, textbookId)
    }
  }, [lessonCorrect, lessonLoaded, textbookId])

  // 保存已完成课程列表
  useEffect(() => {
    if (completedLoaded) {
      completedLessonsStorage.set(completedLessons, textbookId)
    }
  }, [completedLessons, completedLoaded, textbookId])
}

/**
 * 初始化本地存储数据
 * 在组件挂载时从 localStorage 加载数据
 */
export function loadInitialLocalStorage(textbookId = 'builtin-japanese-syntax') {
  return {
    lessonDone: lessonProgressStorage.get(textbookId),
    lessonCorrect: lessonCorrectStorage.get(textbookId),
    completedLessons: completedLessonsStorage.get(textbookId),
  }
}
