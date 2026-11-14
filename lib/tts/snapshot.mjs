const invalid = () => {
  const error = new Error('Invalid TTS snapshot')
  error.kind = 'invalid_input'
  throw error
}
const resourceLimit = () => {
  const error = new Error('TTS input exceeds a resource limit')
  error.kind = 'resource_limit'
  throw error
}
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

export function buildTtsSnapshot(input) {
  if (!isObject(input)) invalid()
  const { textbook, speaker, limits } = input
  if (!Number.isSafeInteger(speaker) || speaker < 0 || !isObject(limits)) invalid()
  for (const key of [
    'maxLessons',
    'maxGrammarPoints',
    'maxSentences',
    'maxSentenceBytes',
    'maxSnapshotBytes',
  ]) {
    if (!Number.isSafeInteger(limits[key]) || limits[key] <= 0) invalid()
  }
  if (!isObject(textbook) || !Array.isArray(textbook.lessons)) invalid()
  if (textbook.lessons.length > limits.maxLessons) resourceLimit()

  const sentences = []
  const seen = new Set()
  let grammarPoints = 0
  for (const lesson of textbook.lessons) {
    if (!isObject(lesson) || !Array.isArray(lesson.grammar)) invalid()
    for (const point of lesson.grammar) {
      if (++grammarPoints > limits.maxGrammarPoints) resourceLimit()
      if (!isObject(point) || typeof point.example !== 'string') invalid()
      const sentence = point.example.trim()
      if (!sentence || seen.has(sentence)) continue
      if (
        Buffer.byteLength(sentence, 'utf8') > limits.maxSentenceBytes ||
        sentences.length >= limits.maxSentences
      )
        resourceLimit()
      seen.add(sentence)
      sentences.push(sentence)
    }
  }
  const snapshot = { speaker, sentences }
  if (Buffer.byteLength(JSON.stringify(snapshot), 'utf8') > limits.maxSnapshotBytes) resourceLimit()
  return snapshot
}
