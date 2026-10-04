import { courses, type Lesson } from '@/lib/courses'
import { questionBank } from '@/lib/question-bank'

export const TEXTBOOK_SCHEMA_VERSION = 1 as const

export type TextbookQuestionType = '翻译' | '助词' | '选择' | '问答'

export type TextbookGrammarPoint = {
  pattern: string
  meaning: string
  example: string
  connection: string
  explanation: string
  responses?: string[]
  pitfalls?: string[]
}

export type TextbookLesson = {
  id: number
  title: string
  goal: string
  description?: string
  grammar: TextbookGrammarPoint[]
}

export type TextbookQuestion = {
  id: string
  lessonId: number
  type: TextbookQuestionType
  prompt: string
  answer: string
  hint: string
  options?: string[]
  acceptedAnswers?: string[]
}

export type Textbook = {
  id: string
  title: string
  shortTitle?: string
  cover?: string
  description?: string
  lessons: TextbookLesson[]
  questions: TextbookQuestion[]
}

export type TextbookPackage = {
  schemaVersion: typeof TEXTBOOK_SCHEMA_VERSION
  textbook: Textbook
}

export type TextbookSource = Textbook | TextbookPackage

const copyLesson = (lesson: TextbookLesson): TextbookLesson => ({
  ...lesson,
  grammar: lesson.grammar.map((point) => ({
    ...point,
    ...(point.responses ? { responses: [...point.responses] } : {}),
    ...(point.pitfalls ? { pitfalls: [...point.pitfalls] } : {}),
  })),
})

const copyQuestion = (question: TextbookQuestion): TextbookQuestion => ({
  ...question,
  ...(question.options ? { options: [...question.options] } : {}),
  ...(question.acceptedAnswers ? { acceptedAnswers: [...question.acceptedAnswers] } : {}),
})

export const builtInTextbookPackage: TextbookPackage = {
  schemaVersion: TEXTBOOK_SCHEMA_VERSION,
  textbook: {
    id: 'builtin-japanese-syntax',
    title: '日语句型课程',
    description: '应用内置课程与题库。',
    lessons: courses.map(copyLesson),
    questions: Object.values(questionBank).flat().map(copyQuestion),
  },
}

const unwrapTextbook = (source: TextbookSource): Textbook =>
  'textbook' in source ? source.textbook : source

const questionTypeOrder: Record<TextbookQuestionType, number> = {
  选择: 0,
  助词: 1,
  翻译: 2,
  问答: 3,
}

export function textbookToCourseLessons(source: TextbookSource): Lesson[] {
  return unwrapTextbook(source).lessons.map(copyLesson)
}

export function textbookQuestionsForLesson(
  source: TextbookSource,
  lessonId: number,
): TextbookQuestion[] {
  return unwrapTextbook(source).questions
    .filter((question) => question.lessonId === lessonId)
    .map(copyQuestion)
    .sort((a, b) => questionTypeOrder[a.type] - questionTypeOrder[b.type])
}

export function textbookQuestionForId(
  source: TextbookSource,
  questionId: string,
): TextbookQuestion | undefined {
  const question = unwrapTextbook(source).questions.find((item) => item.id === questionId)
  return question ? copyQuestion(question) : undefined
}
