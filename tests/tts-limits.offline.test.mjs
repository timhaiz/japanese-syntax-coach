import test from 'node:test'
import assert from 'node:assert/strict'
import { TTS_INPUT_LIMITS } from '../lib/tts/limits.mjs'

test('exports the approved immutable TTS input limits', () => {
  assert.deepEqual(TTS_INPUT_LIMITS, {
    maxRequestBytes: 2 * 1024 * 1024,
    maxLessons: 100,
    maxGrammarPoints: 1000,
    maxSentences: 1000,
    maxSentenceBytes: 4 * 1024,
    maxSnapshotBytes: 4 * 1024 * 1024,
  })
  assert.equal(Object.isFrozen(TTS_INPUT_LIMITS), true)
  assert.throws(() => {
    TTS_INPUT_LIMITS.maxRequestBytes = 1
  }, TypeError)
})
