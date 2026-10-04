import type { Question } from '@/lib/question-bank'
import { questionsForLesson, questionForId } from '@/lib/question-bank'
import { courses } from '@/lib/courses'

export const LESSON_QUESTION_LIMIT = 20

export const clampLessonAnswered = (value: unknown, limit = LESSON_QUESTION_LIMIT) =>
  typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.min(Math.max(0, Math.trunc(limit)), Math.trunc(value)))
    : 0

export const clampLessonCorrect = (value: unknown, limit = LESSON_QUESTION_LIMIT) =>
  typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.min(Math.max(0, Math.trunc(limit)), Math.trunc(value)))
    : 0

export const normalizeMistakes = (
  value: unknown,
  resolveQuestion: (id: string) => Question | undefined = questionForId,
): Question[] =>
  Array.isArray(value)
    ? value
        .map((item) => {
          if (!item || typeof item !== 'object') return null
          const id = (item as { id?: unknown }).id
          return typeof id === 'string' ? resolveQuestion(id) ?? null : null
        })
        .filter((item): item is Question => Boolean(item))
    : []

export const mistakesForLesson = (items: Question[], lessonId: number) => {
  return items.filter((item) => item.lessonId === lessonId)
}

export const coreQuestionsForLesson = (
  lessonId: number,
  questions: Question[] = questionsForLesson(lessonId),
  limit = LESSON_QUESTION_LIMIT,
) => questions.filter((question) => question.lessonId === lessonId).slice(0, Math.max(0, limit))

export const contiguousCompletedLessons = (values: number[], lessonCount = courses.length) => {
  const set = new Set(values)
  const result: number[] = []
  for (let index = 0; index < lessonCount && set.has(index); index++) result.push(index)
  return result
}

export const completedFromLessonProgress = (
  progress: Record<number, number>,
  explicit: unknown,
  correct: Record<number, number> = {},
  lessonCount = courses.length,
  questionLimits: number[] = Array.from({ length: lessonCount }, () => LESSON_QUESTION_LIMIT),
) => {
  const qualifies = (index: number) => {
    const limit = questionLimits[index] ?? LESSON_QUESTION_LIMIT
    const answered = clampLessonAnswered(progress[index], limit)
    const right = clampLessonCorrect(correct[index], limit)
    const requiredCorrect = Math.ceil(limit * 0.9)
    return (
      typeof answered === 'number' &&
      limit > 0 &&
      answered >= limit &&
      typeof right === 'number' &&
      right >= requiredCorrect
    )
  }
  const values = Array.isArray(explicit)
    ? explicit.filter(
        (n): n is number => Number.isInteger(n) && n >= 0 && n < lessonCount && qualifies(n),
      )
    : []
  const derived = Object.entries(progress)
    .filter(([index]) => Number(index) < lessonCount && qualifies(Number(index)))
    .map(([index]) => Number(index))
  return contiguousCompletedLessons(
    Array.from(new Set([...values, ...derived])).sort((a, b) => a - b),
    lessonCount,
  )
}
