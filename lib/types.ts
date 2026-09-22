/**
 * 全局类型定义
 * 统一管理应用中的共享类型
 */

import type { Question } from '@/lib/question-bank'

/**
 * 同步状态
 */
export type SyncState = 'local' | 'syncing' | 'synced' | 'failed'

/**
 * 练习模式
 */
export type PracticeMode = 'lesson' | 'mistakes' | 'mixed'

/**
 * AI 判分结果
 */
export type AiVerdict = 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect' | null

/**
 * 判分来源
 */
export type GradeSource = 'ai' | 'rule' | null

/**
 * 学习进度
 */
export type LearningProgress = {
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
}

/**
 * 学习指标
 */
export type LearningMetrics = {
  correctStreak: number
  errorRate: number
  forgettingRate?: number
  topErrorTags: { tag: string; count: number }[]
}

/**
 * 课程总结
 */
export type LessonSummary = {
  lessonId: number
  accuracy: number
  mistakeTypes: string[]
  nextLessonId?: number
}

/**
 * 课程信息（带进度）
 */
export type LessonWithProgress = {
  id: number
  title: string
  progress: number
  locked: boolean
  description?: string
}

/**
 * 标签页类型
 */
export type TabType = 'home' | 'lessons' | 'mistakes' | 'profile'

/**
 * 重放模式引用
 */
export type ReplayRef = {
  lesson: number
  count: number
}
