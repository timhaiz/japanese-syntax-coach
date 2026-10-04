import {
  TEXTBOOK_SCHEMA_VERSION,
  builtInTextbookPackage,
  type Textbook,
  type TextbookPackage,
  type TextbookQuestionType,
} from '@/lib/textbooks'

export type TextbookImportResult =
  | { success: true; data: TextbookPackage; errors: [] }
  | { success: false; errors: string[] }

export type StoredTextbookSummary = {
  id: string
  title: string
  description?: string
  lessonCount: number
  questionCount: number
}

const STORAGE_KEY = 'japanese-syntax-coach:textbook-packages:v1'
const validId = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
const questionTypes = new Set<TextbookQuestionType>(['翻译', '助词', '选择', '问答'])
const requiredPackageKeys = ['schemaVersion', 'textbook']
const requiredTextbookKeys = ['id', 'title', 'lessons', 'questions']
const optionalTextbookKeys = ['shortTitle', 'cover', 'description']
const requiredLessonKeys = ['id', 'title', 'goal', 'grammar']
const optionalLessonKeys = ['description']
const grammarPointRequiredKeys = ['pattern', 'meaning', 'example', 'connection', 'explanation']
const grammarPointOptionalKeys = ['responses', 'pitfalls']
const requiredQuestionKeys = ['id', 'lessonId', 'type', 'prompt', 'answer', 'hint']
const optionalQuestionKeys = ['options', 'acceptedAnswers']

type UnknownRecord = Record<string, unknown>

const isImageReference = (value: string) =>
  (value.startsWith('data:image/') || value.startsWith('/')) && value.length <= 500_000

/**
 * Convert the user-facing lesson-embedded format into the runtime format.
 * The runtime keeps questions at textbook level so review and lookup code has
 * one stable shape, while imports can follow the simpler plan format.
 */
export function normalizeTextbookPackageInput(input: unknown): unknown {
  if (!isRecord(input) || !isRecord(input.textbook)) return input
  const root = input
  const textbook = input.textbook
  const rootLessons = Array.isArray(root.lessons) ? root.lessons : null
  const textbookLessons = Array.isArray(textbook.lessons) ? textbook.lessons : null
  const lessonValues = rootLessons ?? textbookLessons
  const textbookQuestions = Array.isArray(textbook.questions) ? textbook.questions : []
  if (!lessonValues) return input

  const questions = [...textbookQuestions]
  const lessons = lessonValues.map((value) => {
    if (!isRecord(value)) return value
    const nested = Array.isArray(value.questions) ? value.questions : []
    questions.push(...nested.map((question) => ({ ...question, lessonId: value.id })))
    const goal = typeof value.goal === 'string' ? value.goal : value.description
    const { questions: _questions, ...lessonWithoutQuestions } = value
    return {
      ...lessonWithoutQuestions,
      ...(typeof goal === 'string' ? { goal } : {}),
      grammar: Array.isArray(value.grammar) ? value.grammar : [],
    }
  })
  const normalizedTextbook = {
    ...textbook,
    lessons,
    questions,
  }
  const normalized = { ...root, textbook: normalizedTextbook }
  delete (normalized as UnknownRecord).lessons
  return normalized
}

const isRecord = (value: unknown): value is UnknownRecord =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const checkKeys = (
  value: UnknownRecord,
  required: string[],
  optional: string[],
  path: string,
  errors: string[],
) => {
  for (const key of required) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      errors.push(`${path}缺少必填字段「${key}」。`)
    }
  }
  const allowed = new Set([...required, ...optional])
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) errors.push(`${path}包含不支持的字段「${key}」。`)
  }
}

const validateNonEmptyString = (value: unknown, path: string, errors: string[]): value is string => {
  if (typeof value !== 'string' || value.trim().length === 0) {
    errors.push(`${path}必须是非空字符串。`)
    return false
  }
  return true
}

const validateOptionalStringArray = (
  record: UnknownRecord,
  key: string,
  path: string,
  errors: string[],
) => {
  if (!Object.prototype.hasOwnProperty.call(record, key)) return
  const value = record[key]
  if (!Array.isArray(value)) {
    errors.push(`${path}必须是字符串数组。`)
    return
  }
  value.forEach((item, index) => {
    validateNonEmptyString(item, `${path}[${index + 1}]`, errors)
  })
}

const normalizeExistingIds = (existingIds?: Iterable<string>): Set<string> => {
  if (!existingIds) return new Set()
  return typeof existingIds === 'string' ? new Set([existingIds]) : new Set(existingIds)
}

export function validateTextbookPackage(
  input: unknown,
  existingIds?: Iterable<string>,
): TextbookImportResult {
  input = normalizeTextbookPackageInput(input)
  const errors: string[] = []
  if (!isRecord(input)) {
    return { success: false, errors: ['教材包必须是 JSON 对象。'] }
  }

  checkKeys(input, requiredPackageKeys, [], '教材包', errors)
  if (input.schemaVersion !== TEXTBOOK_SCHEMA_VERSION) {
    errors.push(`教材包「schemaVersion」必须为 ${TEXTBOOK_SCHEMA_VERSION}。`)
  }

  const textbookValue = input.textbook
  if (!isRecord(textbookValue)) {
    errors.push('教材包「textbook」必须是对象。')
    return { success: false, errors }
  }

  const textbook = textbookValue
  checkKeys(textbook, requiredTextbookKeys, optionalTextbookKeys, '教材', errors)

  const textbookId = textbook.id
  const existing = normalizeExistingIds(existingIds)
  if (validateNonEmptyString(textbookId, '教材「id」', errors)) {
    if (!validId.test(textbookId)) {
      errors.push('教材「id」只能包含英文字母、数字、点、下划线和连字符，且不能以符号开头。')
    }
    if (existing.has(textbookId)) errors.push(`教材 ID「${textbookId}」已存在。`)
  }
  validateNonEmptyString(textbook.title, '教材「title」', errors)
  if (Object.prototype.hasOwnProperty.call(textbook, 'description')) {
    validateNonEmptyString(textbook.description, '教材「description」', errors)
  }
  if (Object.prototype.hasOwnProperty.call(textbook, 'shortTitle')) {
    validateNonEmptyString(textbook.shortTitle, '教材「shortTitle」', errors)
  }
  if (Object.prototype.hasOwnProperty.call(textbook, 'cover')) {
    if (typeof textbook.cover !== 'string' || !isImageReference(textbook.cover)) {
      errors.push('教材「cover」必须是 data:image/ 开头的图片或 / 开头的本地资源，且不能超过 500KB。')
    }
  }

  const lessonIds = new Set<number>()
  const lessonsValue = textbook.lessons
  if (!Array.isArray(lessonsValue)) {
    errors.push('教材「lessons」必须是数组。')
  } else {
    if (lessonsValue.length === 0) errors.push('教材至少需要包含一个课次。')
    lessonsValue.forEach((lessonValue, lessonIndex) => {
      const lessonPath = `第 ${lessonIndex + 1} 课`
      if (!isRecord(lessonValue)) {
        errors.push(`${lessonPath}必须是对象。`)
        return
      }
      const lesson = lessonValue
      checkKeys(lesson, requiredLessonKeys, optionalLessonKeys, `${lessonPath}：`, errors)
      if (typeof lesson.id !== 'number' || !Number.isSafeInteger(lesson.id) || lesson.id < 1) {
        errors.push(`${lessonPath}「id」必须是大于 0 的整数。`)
      } else if (lessonIds.has(lesson.id)) {
        errors.push(`${lessonPath}课次 ID「${lesson.id}」重复。`)
      } else {
        lessonIds.add(lesson.id)
      }
      validateNonEmptyString(lesson.title, `${lessonPath}「title」`, errors)
      validateNonEmptyString(lesson.goal, `${lessonPath}「goal」`, errors)
      if (Object.prototype.hasOwnProperty.call(lesson, 'description')) {
        validateNonEmptyString(lesson.description, `${lessonPath}「description」`, errors)
      }
      if (!Array.isArray(lesson.grammar)) {
        errors.push(`${lessonPath}「grammar」必须是数组。`)
      } else {
        lesson.grammar.forEach((pointValue, pointIndex) => {
          const pointPath = `${lessonPath}第 ${pointIndex + 1} 个语法点`
          if (!isRecord(pointValue)) {
            errors.push(`${pointPath}必须是对象。`)
            return
          }
          checkKeys(pointValue, grammarPointRequiredKeys, grammarPointOptionalKeys, `${pointPath}：`, errors)
          for (const key of grammarPointRequiredKeys) {
            validateNonEmptyString(pointValue[key], `${pointPath}「${key}」`, errors)
          }
          validateOptionalStringArray(pointValue, 'responses', `${pointPath}「responses」`, errors)
          validateOptionalStringArray(pointValue, 'pitfalls', `${pointPath}「pitfalls」`, errors)
        })
      }
    })
  }

  const questionIds = new Set<string>()
  const questionsValue = textbook.questions
  if (!Array.isArray(questionsValue)) {
    errors.push('教材「questions」必须是数组。')
  } else {
    questionsValue.forEach((questionValue, questionIndex) => {
      const questionPath = `第 ${questionIndex + 1} 道题`
      if (!isRecord(questionValue)) {
        errors.push(`${questionPath}必须是对象。`)
        return
      }
      const question = questionValue
      checkKeys(question, requiredQuestionKeys, optionalQuestionKeys, `${questionPath}：`, errors)
      if (validateNonEmptyString(question.id, `${questionPath}「id」`, errors)) {
        if (!validId.test(question.id)) {
          errors.push(`${questionPath}「id」格式无效，只能包含英文字母、数字、点、下划线和连字符。`)
        }
        if (questionIds.has(question.id)) errors.push(`${questionPath}题目 ID「${question.id}」重复。`)
        questionIds.add(question.id)
      }
      if (typeof question.lessonId !== 'number' || !Number.isSafeInteger(question.lessonId) || question.lessonId < 1) {
        errors.push(`${questionPath}「lessonId」必须是大于 0 的整数课次 ID。`)
      } else if (!lessonIds.has(question.lessonId)) {
        errors.push(`${questionPath}引用了不存在的课次 ID「${question.lessonId}」。`)
      }
      if (typeof question.type !== 'string' || !questionTypes.has(question.type as TextbookQuestionType)) {
        errors.push(`${questionPath}「type」必须是「翻译」「助词」「选择」或「问答」之一。`)
      }
      for (const key of ['prompt', 'answer', 'hint']) {
        validateNonEmptyString(question[key], `${questionPath}「${key}」`, errors)
      }
      validateOptionalStringArray(question, 'options', `${questionPath}「options」`, errors)
      validateOptionalStringArray(question, 'acceptedAnswers', `${questionPath}「acceptedAnswers」`, errors)
      if (question.type === '选择' && (!Array.isArray(question.options) || question.options.length === 0)) {
        errors.push(`${questionPath}题型为「选择」时必须提供非空「options」选项数组。`)
      }
    })
  }

  if (errors.length > 0) return { success: false, errors }
  return { success: true, data: input as unknown as TextbookPackage, errors: [] }
}

export function parseTextbookJson(
  text: string,
  existingIds?: Iterable<string>,
): TextbookImportResult {
  let input: unknown
  try {
    input = JSON.parse(text)
  } catch {
    return { success: false, errors: ['JSON 格式错误，请检查引号、逗号和括号。'] }
  }
  return validateTextbookPackage(input, existingIds)
}

const getBrowserStorage = (): Storage | null => {
  if (typeof window === 'undefined') return null
  try {
    return window.localStorage
  } catch {
    return null
  }
}

const readStoredPackages = (storage: Storage): TextbookPackage[] => {
  try {
    const stored = storage.getItem(STORAGE_KEY)
    if (!stored) return []
    const values: unknown = JSON.parse(stored)
    if (!Array.isArray(values)) return []
    return values.flatMap((value) => {
      const result = validateTextbookPackage(value)
      return result.success ? [result.data] : []
    })
  } catch {
    return []
  }
}

export function getStoredTextbookPackages(): TextbookPackage[] {
  const storage = getBrowserStorage()
  return storage ? readStoredPackages(storage) : []
}

export function getStoredTextbooks(): Textbook[] {
  return getStoredTextbookPackages().map((item) => item.textbook)
}

export function getAvailableTextbookPackages(): TextbookPackage[] {
  return [builtInTextbookPackage, ...getStoredTextbookPackages()]
}

export function getAvailableTextbookPackage(textbookId: string): TextbookPackage | undefined {
  return getAvailableTextbookPackages().find((item) => item.textbook.id === textbookId)
}

export function getStoredTextbookList(): StoredTextbookSummary[] {
  return getStoredTextbooks().map(({ id, title, description, lessons, questions }) => ({
    id,
    title,
    ...(description ? { description } : {}),
    lessonCount: lessons.length,
    questionCount: questions.length,
  }))
}

export function getAvailableTextbookList(): StoredTextbookSummary[] {
  return getAvailableTextbookPackages().map(({ textbook: { id, title, description, lessons, questions } }) => ({
    id,
    title,
    ...(description ? { description } : {}),
    lessonCount: lessons.length,
    questionCount: questions.length,
  }))
}

export function saveTextbookPackage(input: unknown): TextbookImportResult {
  const storage = getBrowserStorage()
  if (!storage) return { success: false, errors: ['当前环境无法使用本地存储。'] }

  const packages = readStoredPackages(storage)
  const result = validateTextbookPackage(input, packages.map((item) => item.textbook.id))
  if (!result.success) return result

  try {
    storage.setItem(STORAGE_KEY, JSON.stringify([...packages, result.data]))
    return result
  } catch {
    return { success: false, errors: ['保存失败：浏览器本地存储不可用或空间不足。'] }
  }
}

export function saveTextbookJson(text: string): TextbookImportResult {
  const existingIds = getStoredTextbooks().map((textbook) => textbook.id)
  const result = parseTextbookJson(text, existingIds)
  if (!result.success) return result
  return saveTextbookPackage(result.data)
}

export function removeStoredTextbook(textbookId: string): boolean {
  const storage = getBrowserStorage()
  if (!storage) return false
  try {
    const remaining = readStoredPackages(storage).filter((item) => item.textbook.id !== textbookId)
    storage.setItem(STORAGE_KEY, JSON.stringify(remaining))
    return true
  } catch {
    return false
  }
}
