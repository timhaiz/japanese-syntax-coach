import test from 'node:test'
import assert from 'node:assert/strict'
import { updateMistakeProgress } from '../lib/learning/mistake-progress.mjs'

const textbookId = 'builtin-japanese-syntax'
const questions = new Map([
  ['q1', { id: 'q1', lessonId: 1, prompt: 'canonical one' }],
  ['q2', { id: 'q2', lessonId: 2, prompt: 'canonical two' }],
])
const resolveQuestion = id => questions.get(id)
const snapshot = mistakes => ({ version: 3, lessonDone: { 0: 4 }, lessonCorrect: { 0: 2 }, completedLessons: [], mistakes, updatedAt: 'before' })
const attempt = (correct = false, mode = 'lesson') => ({ textbookId, questionId: 'q1', correct, mode })
const apply = (progress, answer = attempt()) => updateMistakeProgress(progress, answer, resolveQuestion, 'after')

test('incorrect answer adds a canonical question and preserves other progress', () => {
  const previous = { ...snapshot([{ id: 'q2', prompt: 'stale' }]), custom: { retained: true } }
  const result = apply(previous)
  assert.deepEqual(result.mistakes, [questions.get('q2'), questions.get('q1')])
  assert.deepEqual(result.lessonDone, { 0: 4 })
  assert.deepEqual(result.custom, { retained: true })
  assert.equal(result.updatedAt, 'after')
  assert.equal(previous.mistakes.length, 1)
})

test('repeating an incorrect answer does not duplicate the mistake', () => {
  const once = apply(snapshot([]))
  assert.deepEqual(apply(once), once)
})

test('correct mistake or replay answers remove only the answered question', () => {
  for (const mode of ['mistakes', 'lesson_replay']) {
    const result = apply(snapshot([{ id: 'q1' }, { id: 'q2' }]), attempt(true, mode))
    assert.deepEqual(result.mistakes.map(q => q.id), ['q2'])
  }
})

test('ordinary correct lesson and review answers retain existing mistakes', () => {
  for (const mode of ['lesson', 'review', 'new']) {
    assert.deepEqual(apply(snapshot([{ id: 'q1' }]), attempt(true, mode)).mistakes.map(q => q.id), ['q1'])
  }
})

test('scoped snapshots take precedence and unrelated textbook metadata survives', () => {
  const other = { version: 8, opaque: ['preserve'] }
  const root = { ...snapshot([{ id: 'q2' }]), byTextbook: { [textbookId]: snapshot([]), other } }
  const result = apply(root)
  assert.deepEqual(result.mistakes.map(q => q.id), ['q1'])
  assert.deepEqual(result.byTextbook[textbookId].mistakes.map(q => q.id), ['q1'])
  assert.deepEqual(result.byTextbook.other, other)
  assert.deepEqual(root.byTextbook[textbookId].mistakes, [])
})

test('missing progress starts an empty supported snapshot', () => {
  const result = apply(null)
  assert.equal(result.version, 3)
  assert.deepEqual(result.mistakes.map(q => q.id), ['q1'])
  assert.deepEqual(result.lessonDone, {})
})

test('unknown versions and malformed snapshots fail closed without replacing data', () => {
  for (const previous of [{ ...snapshot([]), version: 9 }, { ...snapshot([]), mistakes: 'broken' }, { byTextbook: { [textbookId]: null } }]) {
    const before = structuredClone(previous)
    assert.throws(() => apply(previous), /unsupported progress/)
    assert.deepEqual(previous, before)
  }
})

test('partial legacy snapshots are never treated as a fresh account', () => {
  for (const previous of [
    { version: 2, mistakes: 'legacy-broken', opaque: { keep: true } },
    { mistakes: [{ id: 'q2' }] },
    { lessonCorrect: { 0: 10 } },
    { completedLessons: [4] },
    { updatedAt: 'legacy' },
  ]) {
    const before = structuredClone(previous)
    assert.throws(() => apply(previous), /unsupported progress/)
    assert.deepEqual(previous, before)
  }
})

test('unknown questions, textbooks and invalid attempts are rejected', () => {
  for (const bad of [
    { ...attempt(), questionId: 'missing' },
    { ...attempt(), textbookId: 'other' },
    { ...attempt(), correct: 'false' },
    { ...attempt(), mode: 'unknown' },
  ]) assert.throws(() => apply(snapshot([]), bad), /invalid attempt/)
})
