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
const DEFAULT_TEXTBOOK_ID = 'builtin-japanese-syntax'

const storageKey = (key: string, textbookId: string) =>
  textbookId === DEFAULT_TEXTBOOK_ID
    ? key
    : `syntax-coach:textbook:${textbookId}:${key.slice('syntax-coach-'.length)}`

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
  get: (
    textbookId = DEFAULT_TEXTBOOK_ID,
    resolveQuestion?: (id: string) => Question | undefined,
  ): Question[] => {
    const data = safeJsonParse(storageKey(STORAGE_KEYS.MISTAKES, textbookId), [])
    return normalizeMistakes(data, resolveQuestion)
  },
  set: (mistakes: Question[], textbookId = DEFAULT_TEXTBOOK_ID): void => {
    safeJsonSet(storageKey(STORAGE_KEYS.MISTAKES, textbookId), mistakes)
  },
  clear: (textbookId = DEFAULT_TEXTBOOK_ID): void => {
    localStorage.removeItem(storageKey(STORAGE_KEYS.MISTAKES, textbookId))
  },
}

/**
 * 课程进度管理
 */
export const lessonProgressStorage = {
  get: (textbookId = DEFAULT_TEXTBOOK_ID): Record<number, number> => {
    return safeJsonParse(storageKey(STORAGE_KEYS.LESSON_PROGRESS, textbookId), {})
  },
  set: (progress: Record<number, number>, textbookId = DEFAULT_TEXTBOOK_ID): void => {
    safeJsonSet(storageKey(STORAGE_KEYS.LESSON_PROGRESS, textbookId), progress)
  },
  merge: (
    progress: Record<number, number>,
    textbookId = DEFAULT_TEXTBOOK_ID,
    questionLimits: number[] = [],
  ): void => {
    const saved = lessonProgressStorage.get(textbookId)
    const merged = {
      ...saved,
      ...Object.fromEntries(
        Object.entries(progress).map(([index, count]) => [
          index,
          clampLessonAnswered(
            Math.max(Number(saved?.[index]) || 0, Number(count) || 0),
            questionLimits[Number(index)],
          ),
        ]),
      ),
    }
    lessonProgressStorage.set(merged, textbookId)
  },
  clear: (textbookId = DEFAULT_TEXTBOOK_ID): void => {
    localStorage.removeItem(storageKey(STORAGE_KEYS.LESSON_PROGRESS, textbookId))
  },
}

/**
 * 课程正确数管理
 */
export const lessonCorrectStorage = {
  get: (textbookId = DEFAULT_TEXTBOOK_ID): Record<number, number> => {
    return safeJsonParse(storageKey(STORAGE_KEYS.LESSON_CORRECT, textbookId), {})
  },
  set: (correct: Record<number, number>, textbookId = DEFAULT_TEXTBOOK_ID): void => {
    safeJsonSet(storageKey(STORAGE_KEYS.LESSON_CORRECT, textbookId), correct)
  },
  clear: (textbookId = DEFAULT_TEXTBOOK_ID): void => {
    localStorage.removeItem(storageKey(STORAGE_KEYS.LESSON_CORRECT, textbookId))
  },
}

/**
 * 已完成课程管理
 */
export const completedLessonsStorage = {
  get: (textbookId = DEFAULT_TEXTBOOK_ID): number[] => {
    return safeJsonParse(storageKey(STORAGE_KEYS.COMPLETED_LESSONS, textbookId), [])
  },
  set: (lessons: number[], textbookId = DEFAULT_TEXTBOOK_ID): void => {
    safeJsonSet(storageKey(STORAGE_KEYS.COMPLETED_LESSONS, textbookId), lessons)
  },
  clear: (textbookId = DEFAULT_TEXTBOOK_ID): void => {
    localStorage.removeItem(storageKey(STORAGE_KEYS.COMPLETED_LESSONS, textbookId))
  },
}

/**
 * 清除所有学习数据
 */
export const clearAllProgress = (textbookId = DEFAULT_TEXTBOOK_ID): void => {
  mistakesStorage.clear(textbookId)
  lessonProgressStorage.clear(textbookId)
  lessonCorrectStorage.clear(textbookId)
  completedLessonsStorage.clear(textbookId)
}
