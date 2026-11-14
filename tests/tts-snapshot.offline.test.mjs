import test from 'node:test'
import assert from 'node:assert/strict'
import { buildTtsSnapshot } from '../lib/tts/snapshot.mjs'
import { TTS_INPUT_LIMITS } from '../lib/tts/limits.mjs'

const limits = {
  maxLessons: 10,
  maxGrammarPoints: 10,
  maxSentences: 10,
  maxSentenceBytes: 100,
  maxSnapshotBytes: 1000,
}
const input = (examples, overrides = {}) => ({
  textbook: { lessons: [{ grammar: examples.map((example) => ({ example })) }] },
  speaker: 3,
  limits: { ...limits, ...overrides },
})
const invalid = (value) =>
  assert.throws(
    () => buildTtsSnapshot(value),
    (error) => error.kind === 'invalid_input' && error.message === 'Invalid TTS snapshot',
  )
const overLimit = (value) =>
  assert.throws(
    () => buildTtsSnapshot(value),
    (error) =>
      error.kind === 'resource_limit' && error.message === 'TTS input exceeds a resource limit',
  )

test('trims and deduplicates examples in encounter order, discarding blanks', () => {
  const value = input([' あ ', 'あ', ' \n ', 'い'], {
    maxLessons: 1,
    maxGrammarPoints: 4,
    maxSentences: 2,
    maxSentenceBytes: 3,
  })
  assert.deepEqual(buildTtsSnapshot(value), { speaker: 3, sentences: ['あ', 'い'] })
})

test('preserves encounter order and deduplicates across lessons', () => {
  const value = input([])
  value.textbook.lessons = [
    { grammar: [{ example: ' a ' }, { example: 'b' }] },
    { grammar: [{ example: 'a' }, { example: ' c ' }] },
  ]
  assert.deepEqual(buildTtsSnapshot(value), { speaker: 3, sentences: ['a', 'b', 'c'] })
})

test('accepts zero speaker and an empty lesson list', () => {
  const value = input([])
  value.speaker = 0
  value.textbook.lessons = []
  assert.deepEqual(buildTtsSnapshot(value), { speaker: 0, sentences: [] })
})

test('accepts each exact limit and rejects exceeding it', () => {
  const cases = [
    ['maxLessons', input(['a']), 1, 2, (value) => value.textbook.lessons.push({ grammar: [] })],
    [
      'maxGrammarPoints',
      input(['a']),
      1,
      2,
      (value) => value.textbook.lessons[0].grammar.push({ example: 'a' }),
    ],
    [
      'maxSentences',
      input(['a']),
      1,
      2,
      (value) => value.textbook.lessons[0].grammar.push({ example: 'b' }),
    ],
    [
      'maxSentenceBytes',
      input(['あ']),
      3,
      4,
      (value) => {
        value.textbook.lessons[0].grammar[0].example = 'あa'
      },
    ],
  ]
  for (const [key, value, exact, , exceed] of cases) {
    value.limits[key] = exact
    assert.doesNotThrow(() => buildTtsSnapshot(value), key)
    exceed(value)
    overLimit(value)
  }
  const value = input(['あ"'])
  const bytes = Buffer.byteLength(JSON.stringify({ speaker: 3, sentences: ['あ"'] }), 'utf8')
  value.limits.maxSnapshotBytes = bytes
  assert.doesNotThrow(() => buildTtsSnapshot(value))
  value.limits.maxSnapshotBytes = bytes - 1
  overLimit(value)
})

test('duplicates consume grammar budget but not sentence budget', () => {
  assert.deepEqual(
    buildTtsSnapshot(input(['x', ' x ', ''], { maxGrammarPoints: 3, maxSentences: 1 })),
    { speaker: 3, sentences: ['x'] },
  )
  overLimit(input(['x', ' x '], { maxGrammarPoints: 1, maxSentences: 1 }))
})

test('accepts the approved exact lesson, grammar, sentence-count and sentence-byte ceilings', () => {
  const byLessons = {
    textbook: {
      lessons: Array.from({ length: TTS_INPUT_LIMITS.maxLessons }, () => ({ grammar: [] })),
    },
    speaker: 3,
    limits: TTS_INPUT_LIMITS,
  }
  assert.equal(buildTtsSnapshot(byLessons).sentences.length, 0)

  const repeatedPoints = Array.from({ length: TTS_INPUT_LIMITS.maxGrammarPoints }, () => ({
    example: 'same',
  }))
  const byGrammar = {
    textbook: { lessons: [{ grammar: repeatedPoints }] },
    speaker: 3,
    limits: TTS_INPUT_LIMITS,
  }
  assert.deepEqual(buildTtsSnapshot(byGrammar).sentences, ['same'])

  const distinctPoints = Array.from({ length: TTS_INPUT_LIMITS.maxSentences }, (_, index) => ({
    example: `s${index}`,
  }))
  const bySentences = {
    textbook: { lessons: [{ grammar: distinctPoints }] },
    speaker: 3,
    limits: TTS_INPUT_LIMITS,
  }
  assert.equal(buildTtsSnapshot(bySentences).sentences.length, 1000)

  const exactSentence = {
    textbook: {
      lessons: [{ grammar: [{ example: 'x'.repeat(TTS_INPUT_LIMITS.maxSentenceBytes) }] }],
    },
    speaker: 3,
    limits: TTS_INPUT_LIMITS,
  }
  assert.equal(Buffer.byteLength(buildTtsSnapshot(exactSentence).sentences[0], 'utf8'), 4096)
})

test('rejects malformed structures, limits and speakers as invalid input', () => {
  for (const value of [
    undefined,
    null,
    [],
    {},
    { ...input([]), textbook: null },
    { ...input([]), textbook: { lessons: {} } },
    { ...input([]), textbook: { lessons: [null] } },
    { ...input([]), textbook: { lessons: [{ grammar: [null] }] } },
    { ...input([]), textbook: { lessons: [{ grammar: [{ example: 42 }] }] } },
    { ...input([]), limits: null },
    { ...input([]), speaker: -1 },
    { ...input([]), speaker: 1.5 },
    { ...input([]), speaker: Number.MAX_SAFE_INTEGER + 1 },
  ])
    invalid(value)
  for (const key of Object.keys(limits)) {
    for (const value of [
      undefined,
      null,
      0,
      -1,
      1.5,
      NaN,
      Infinity,
      Number.MAX_SAFE_INTEGER + 1,
      '1',
    ])
      invalid(input([], { [key]: value }))
  }
  overLimit(input(['secret synthetic example'], { maxSentenceBytes: 1 }))
  overLimit(input(['secret synthetic example'], { maxSnapshotBytes: 1 }))
})

test('does not mutate inputs and returns isolated arrays', () => {
  const value = input([' a ', 'b'])
  const before = structuredClone(value)
  const first = buildTtsSnapshot(value)
  assert.deepEqual(value, before)
  first.sentences.push('changed')
  assert.deepEqual(buildTtsSnapshot(value), { speaker: 3, sentences: ['a', 'b'] })
  assert.deepEqual(value, before)
})
