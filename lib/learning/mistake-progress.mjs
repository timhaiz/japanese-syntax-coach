const BUILTIN_TEXTBOOK_ID = 'builtin-japanese-syntax'
const modes = new Set(['new', 'review', 'mistakes', 'lesson', 'lesson_replay'])
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)

/**
 * Pure candidate reducer for a confirmed answer. This does NOT persist metadata.
 * A future caller must serialize read/modify/write per account and reject stale
 * attempts; rerunning an old operation after newer answers is not safe.
 */
export function updateMistakeProgress(progress, attempt, resolveQuestion, updatedAt) {
  if (!attempt || attempt.textbookId !== BUILTIN_TEXTBOOK_ID ||
      typeof attempt.correct !== 'boolean' || !modes.has(attempt.mode) ||
      typeof attempt.questionId !== 'string') throw new Error('invalid attempt')
  const question = resolveQuestion(attempt.questionId)
  if (!question || question.id !== attempt.questionId) throw new Error('invalid attempt')
  if (progress !== null && progress !== undefined && !object(progress)) throw new Error('unsupported progress')
  const root = progress ?? {}
  if (root.byTextbook !== undefined && !object(root.byTextbook)) throw new Error('unsupported progress')
  const scopes = root.byTextbook ?? {}
  const scoped = Object.hasOwn(scopes, BUILTIN_TEXTBOOK_ID)
  const hasLegacySnapshot = ['lessonDone', 'lessonCorrect', 'completedLessons', 'mistakes', 'updatedAt'].some(key => Object.hasOwn(root, key))
  const source = scoped ? scopes[BUILTIN_TEXTBOOK_ID] : hasLegacySnapshot ? root : undefined
  if (source !== undefined || scoped) {
    if (!object(source) || ![2, 3].includes(source.version) ||
        !object(source.lessonDone) || !object(source.lessonCorrect) ||
        !Array.isArray(source.completedLessons) || !Array.isArray(source.mistakes) ||
        typeof source.updatedAt !== 'string') throw new Error('unsupported progress')
  } else if (root.version !== undefined && ![2, 3].includes(root.version)) {
    throw new Error('unsupported progress')
  }
  const base = source ?? { lessonDone: {}, lessonCorrect: {}, completedLessons: [], mistakes: [] }
  const seen = new Set()
  const mistakes = base.mistakes.flatMap(item => {
    if (!object(item) || typeof item.id !== 'string' || seen.has(item.id)) return []
    const canonical = resolveQuestion(item.id)
    if (!canonical) return []
    seen.add(item.id)
    return [canonical]
  }).filter(item => !(attempt.correct && ['mistakes', 'lesson_replay'].includes(attempt.mode) && item.id === question.id))
  if (!attempt.correct && !seen.has(question.id)) mistakes.push(question)
  const next = { ...base, version: 3, mistakes, updatedAt }
  return { ...root, ...next, byTextbook: { ...scopes, [BUILTIN_TEXTBOOK_ID]: next } }
}
