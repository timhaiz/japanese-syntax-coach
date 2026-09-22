/**
 * 统一的 localStorage 存储工具
 * 提供类型安全的读写接口和错误处理
 */

import type { Question } from '@/lib/question-bank'
import { normalizeMistakes, clampLessonAnswered } from './lesson-utils'

const STORAGE_KEYS = {
  MISTAKES: 'syntax-coach-mistakes',
  LESSON_PROGRESS: 'syntax-coach-lesson-progress',
  LESSON_CORRECT: 'syntax-coach-lesson-correct',
  COMPLETED_LESSONS: 'syntax-coach-completed-lessons',
} as const

/**
 * 安全读取 JSON 数据
 */
const safeJsonParse = <T>(key: string, fallback: T): T => {
  try {
    const value = localStorage.getItem(key)
    return value ? JSON.parse(value) : fallback
  } catch {
    localStorage.removeItem(key)
    return fallback
  }
}

/**
 * 安全写入 JSON 数据
 */
const safeJsonSet = (key: string, value: unknown): void => {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch (error) {
    console.warn(`Failed to save to localStorage: ${key}`, error)
  }
}

/**
 * 错题记录管理
 */
export const mistakesStorage = {
  get: (): Question[] => {
    const data = safeJsonParse(STORAGE_KEYS.MISTAKES, [])
    return normalizeMistakes(data)
  },
  set: (mistakes: Question[]): void => {
    safeJsonSet(STORAGE_KEYS.MISTAKES, mistakes)
  },
  clear: (): void => {
    localStorage.removeItem(STORAGE_KEYS.MISTAKES)
  },
}

/**
 * 课程进度管理
 */
export const lessonProgressStorage = {
  get: (): Record<number, number> => {
    return safeJsonParse(STORAGE_KEYS.LESSON_PROGRESS, {})
  },
  set: (progress: Record<number, number>): void => {
    safeJsonSet(STORAGE_KEYS.LESSON_PROGRESS, progress)
  },
  merge: (progress: Record<number, number>): void => {
    const saved = lessonProgressStorage.get()
    const merged = {
      ...saved,
      ...Object.fromEntries(
        Object.entries(progress).map(([index, count]) => [
          index,
          clampLessonAnswered(Math.max(Number(saved?.[index]) || 0, Number(count) || 0)),
        ]),
      ),
    }
    lessonProgressStorage.set(merged)
  },
  clear: (): void => {
    localStorage.removeItem(STORAGE_KEYS.LESSON_PROGRESS)
  },
}

/**
 * 课程正确数管理
 */
export const lessonCorrectStorage = {
  get: (): Record<number, number> => {
    return safeJsonParse(STORAGE_KEYS.LESSON_CORRECT, {})
  },
  set: (correct: Record<number, number>): void => {
    safeJsonSet(STORAGE_KEYS.LESSON_CORRECT, correct)
  },
  clear: (): void => {
    localStorage.removeItem(STORAGE_KEYS.LESSON_CORRECT)
  },
}

/**
 * 已完成课程管理
 */
export const completedLessonsStorage = {
  get: (): number[] => {
    return safeJsonParse(STORAGE_KEYS.COMPLETED_LESSONS, [])
  },
  set: (lessons: number[]): void => {
    safeJsonSet(STORAGE_KEYS.COMPLETED_LESSONS, lessons)
  },
  clear: (): void => {
    localStorage.removeItem(STORAGE_KEYS.COMPLETED_LESSONS)
  },
}

/**
 * 清除所有学习数据
 */
export const clearAllProgress = (): void => {
  mistakesStorage.clear()
  lessonProgressStorage.clear()
  lessonCorrectStorage.clear()
  completedLessonsStorage.clear()
}
