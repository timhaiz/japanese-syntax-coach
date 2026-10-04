import { completedLessonsStorage, lessonProgressStorage } from '@/lib/utils/storage-utils'

export function textbookProgress(
  textbookId: string,
  questionCounts: number[],
): number {
  if (!questionCounts.length) return 0
  const progress = lessonProgressStorage.get(textbookId)
  const total = questionCounts.reduce((sum, count) => sum + Math.max(0, count), 0)
  if (!total) return 0
  const answered = questionCounts.reduce(
    (sum, count, index) => sum + Math.min(Math.max(0, Number(progress[index]) || 0), count),
    0,
  )
  return Math.min(100, Math.round((answered / total) * 100))
}

export function textbookCompletedCount(textbookId: string, lessonCount: number): number {
  return completedLessonsStorage
    .get(textbookId)
    .filter((index) => Number.isInteger(index) && index >= 0 && index < lessonCount).length
}
