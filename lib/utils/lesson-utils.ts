import type { Question } from '@/lib/question-bank'
import { questionsForLesson, questionForId } from '@/lib/question-bank'
import { courses } from '@/lib/courses'

export const LESSON_QUESTION_LIMIT = 20

export const clampLessonAnswered = (value: unknown) =>
  typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.min(LESSON_QUESTION_LIMIT, Math.trunc(value)))
    : 0

export const clampLessonCorrect = (value: unknown) =>
  typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.min(LESSON_QUESTION_LIMIT, Math.trunc(value)))
    : 0

export const normalizeMistakes = (value: unknown): Question[] =>
  Array.isArray(value)
    ? value
        .map((item) => {
          if (!item || typeof item !== 'object') return null
          const id = (item as { id?: unknown }).id
          return typeof id === 'string' ? questionForId(id) ?? null : null
        })
        .filter((item): item is Question => Boolean(item))
    : []

export const mistakesForLesson = (items: Question[], lessonId: number) => {
  const prefix = `L${String(lessonId).padStart(2, '0')}-`
  return items.filter((item) => item.id.startsWith(prefix))
}

export const coreQuestionsForLesson = (lessonId: number) =>
  questionsForLesson(lessonId).slice(0, LESSON_QUESTION_LIMIT)

export const contiguousCompletedLessons = (values: number[]) => {
  const set = new Set(values)
  const result: number[] = []
  for (let index = 0; index < courses.length && set.has(index); index++) result.push(index)
  return result
}

export const completedFromLessonProgress = (
  progress: Record<number, number>,
  explicit: unknown,
  correct: Record<number, number> = {},
) => {
  const qualifies = (index: number) => {
    const answered = clampLessonAnswered(progress[index])
    const right = clampLessonCorrect(correct[index])
    const requiredCorrect = Math.ceil(LESSON_QUESTION_LIMIT * 0.9)
    return (
      typeof answered === 'number' &&
      answered >= LESSON_QUESTION_LIMIT &&
      typeof right === 'number' &&
      right >= requiredCorrect
    )
  }
  const values = Array.isArray(explicit)
    ? explicit.filter(
        (n): n is number => Number.isInteger(n) && n >= 0 && n < courses.length && qualifies(n),
      )
    : []
  const derived = Object.entries(progress)
    .filter(([index]) => qualifies(Number(index)))
    .map(([index]) => Number(index))
  return contiguousCompletedLessons(
    Array.from(new Set([...values, ...derived])).sort((a, b) => a - b),
  )
}
