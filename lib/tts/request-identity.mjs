import { createHash } from 'node:crypto'

const canonicalUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function parseIdempotencyKey(value) {
  if (typeof value !== 'string' || !canonicalUuid.test(value)) return { ok: false }
  return { ok: true, value: value.toLowerCase() }
}

const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]))
  }
  return value
}

export function digestTtsRequest({ textbookId, schemaVersion, sentences, generationParameters = null }) {
  const normalizedSentences = [...new Set(sentences.map((sentence) => sentence.trim()).filter(Boolean))]
  const canonical = JSON.stringify({
    textbookId,
    schemaVersion,
    sentences: normalizedSentences,
    generationParameters: canonicalize(generationParameters),
  })
  return createHash('sha256').update(canonical).digest('hex')
}
