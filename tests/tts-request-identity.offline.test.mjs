import test from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { parseIdempotencyKey, digestTtsRequest } from '../lib/tts/request-identity.mjs'

const valid = '550e8400-e29b-41d4-a716-446655440000'

test('accepts canonical UUIDs and normalizes case', () => {
  assert.deepEqual(parseIdempotencyKey(valid.toUpperCase()), { ok: true, value: valid })
  assert.deepEqual(parseIdempotencyKey(valid), { ok: true, value: valid })
})

test('rejects non-canonical UUID text', () => {
  for (const value of [null, '', `{${valid}}`, valid.slice(0, -1), '550e8400-e29b-41d4-c716-446655440000']) {
    assert.deepEqual(parseIdempotencyKey(value), { ok: false })
  }
})

test('digest includes only canonical client input and excludes server defaults', () => {
  const input = {
    textbookId: 'book-1',
    schemaVersion: 1,
    sentences: [' hello ', 'world', 'hello', ''],
    generationParameters: { speed: 1, pitch: 0, intonation: 1, volume: 1 },
    speaker: 3,
    engineVersion: 'server-version-a',
  }
  const digest = digestTtsRequest(input)
  assert.equal(digest, digestTtsRequest({ ...input, speaker: 9, engineVersion: 'server-version-b' }))
  assert.equal(digest, digestTtsRequest({ ...input, generationParameters: { volume: 1, intonation: 1, pitch: 0, speed: 1 } }))
  const canonical = JSON.stringify({
    textbookId: 'book-1', schemaVersion: 1, sentences: ['hello', 'world'],
    generationParameters: { intonation: 1, pitch: 0, speed: 1, volume: 1 },
  })
  assert.equal(digest, createHash('sha256').update(canonical).digest('hex'))
})
