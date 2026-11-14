import test from 'node:test'
import assert from 'node:assert/strict'
import {createMistakeQueue, matchesMistakeScope} from '../lib/learning/mistake-queue.mjs'

function memoryStorage() {
  const values = new Map()
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    raw: values,
  }
}

const operation = (overrides = {}) => ({
  clientRequestId: 'op-1', userId: 'user-a', textbookId: 'book-a', questionId: 'q-1',
  expectedMistakeVersion: 2, correct: true, answer: 'answer', ...overrides,
})

const ack = (item, overrides = {}) => ({status: 200, body: {
  mistakeStateAvailable: true,
  duplicate: false,
  record: {id: item.clientRequestId},
  mistakeState: {questionId: item.questionId, isMistake: !item.correct, version: item.expectedMistakeVersion + 1},
  ...overrides,
}})

test('queue persists by user and textbook and retains failures without changing payload version', async () => {
  const storage = memoryStorage()
  const queue = createMistakeQueue(storage)
  await queue.enqueue(operation())
  const retry = createMistakeQueue(storage)
  const calls = []
  await retry.flush(async (item) => { calls.push(item); return {status: 503} }, 'user-a', 'book-a')
  assert.equal(calls[0].expectedMistakeVersion, 2)
  assert.equal(retry.list('user-a', 'book-a')[0].expectedMistakeVersion, 2)
  assert.equal(retry.list('user-a', 'book-a')[0].status, 'failed')
  assert.deepEqual(retry.list('user-b', 'book-a'), [])
  assert.deepEqual(retry.list('user-a', 'book-b'), [])
})

test('version conflicts are retained and never reported as persisted', async () => {
  const queue = createMistakeQueue(memoryStorage())
  await queue.enqueue(operation())
  const results = await queue.flush(async () => ({status: 409}), 'user-a', 'book-a')
  assert.equal(results[0].status, 409)
  assert.equal(queue.list('user-a', 'book-a').length, 1)
})

test('same-question operations reserve immutable sequential versions', async () => {
  const queue = createMistakeQueue(memoryStorage())
  const first = await queue.enqueue(operation())
  const second = await queue.enqueue(operation({clientRequestId: undefined, expectedMistakeVersion: undefined, correct: false}))
  assert.equal(first.clientRequestId, 'op-1')
  assert.equal(second.expectedMistakeVersion, 3)
  assert.equal(second.status, 'blocked')
  assert.notEqual(second.clientRequestId, first.clientRequestId)
  await queue.flush(async (item) => ack(item), 'user-a', 'book-a')
  assert.equal(queue.list('user-a', 'book-a')[0].expectedMistakeVersion, 3)
})

test('corrupt queue storage fails closed and is never overwritten', async () => {
  const storage = memoryStorage()
  const key = 'syntax-coach-mistake-queue:user-a:book-a'
  storage.raw.set(key, '{corrupt')
  const queue = createMistakeQueue(storage)
  assert.throws(() => queue.list('user-a', 'book-a'))
  await assert.rejects(queue.enqueue(operation()))
  assert.equal(storage.getItem(key), '{corrupt')
})

test('status 200 without an exact atomic acknowledgement retains the operation', async () => {
  for (const body of [
    {},
    {mistakeStateAvailable: false, mistakeState: {questionId: 'q-1', isMistake: false, version: 3}},
    {mistakeStateAvailable: true, mistakeState: {questionId: 'other', isMistake: false, version: 3}},
    {mistakeStateAvailable: true, mistakeState: {questionId: 'q-1', isMistake: true, version: 3}},
    {mistakeStateAvailable: true, mistakeState: {questionId: 'q-1', isMistake: false, version: 4}},
  ]) {
    const queue = createMistakeQueue(memoryStorage())
    const item = await queue.enqueue(operation())
    const results = await queue.flush(async () => ({status: 200, body}), 'user-a', 'book-a')
    assert.equal(results[0].persisted, false)
    assert.equal(queue.list('user-a', 'book-a')[0].clientRequestId, item.clientRequestId)
  }
})

test('correct ordinary answers preserve an existing mistake state in the acknowledgement', async () => {
  const queue = createMistakeQueue(memoryStorage())
  const item = await queue.enqueue(operation({expectedIsMistake: true, mode: 'lesson'}))
  const results = await queue.flush(async () => ack(item, {mistakeState: {questionId: 'q-1', isMistake: true, version: 3}}), 'user-a', 'book-a')
  assert.equal(results[0].persisted, true)
  assert.equal(queue.list('user-a', 'book-a').length, 0)
})

test('enqueue during flush is preserved and cannot be overwritten by the flush snapshot', async () => {
  const storage = memoryStorage()
  const queue = createMistakeQueue(storage)
  await queue.enqueue(operation())
  let release
  const waiting = new Promise((resolve) => { release = resolve })
  const flushing = queue.flush(async (item) => { await waiting; return ack(item) }, 'user-a', 'book-a')
  await new Promise((resolve) => setTimeout(resolve, 0))
  const appended = await queue.enqueue(operation({questionId: 'q-2', clientRequestId: 'op-2'}))
  release()
  await flushing
  assert.ok(queue.list('user-a', 'book-a').some((item) => item.clientRequestId === appended.clientRequestId))
})

test('queue rejects malformed persisted rows without overwriting the original data', async () => {
  const storage = memoryStorage()
  const key = 'syntax-coach-mistake-queue:user-a:book-a'
  const corrupt = JSON.stringify([{questionId: 'q-1'}])
  storage.raw.set(key, corrupt)
  const queue = createMistakeQueue(storage)
  assert.throws(() => queue.list('user-a', 'book-a'))
  await assert.rejects(queue.enqueue(operation()))
  assert.equal(storage.getItem(key), corrupt)
})

test('local-only or unconfirmed 200 responses are retained', async () => {
  for (const overrides of [
    {localOnly: true},
    {record: null, duplicate: false},
    {record: 'not-a-record', duplicate: false},
  ]) {
    const queue = createMistakeQueue(memoryStorage())
    const item = await queue.enqueue(operation())
    const results = await queue.flush(async () => ack(item, overrides), 'user-a', 'book-a')
    assert.equal(results[0].persisted, false)
    assert.equal(queue.list('user-a', 'book-a').length, 1)
  }
})

test('atomic enqueue without a version is persisted blocked and never sent', async () => {
  const queue = createMistakeQueue(memoryStorage())
  const item = await queue.enqueue(operation({expectedMistakeVersion: undefined, requireVersioned: true}))
  assert.equal(item.expectedMistakeVersion, null)
  assert.equal(item.status, 'blocked')
  const sent = []
  await queue.flush(async (value) => { sent.push(value); return ack(value) }, 'user-a', 'book-a')
  assert.equal(sent.length, 0)
})

test('reserved versions at the safe-integer boundary block instead of overflowing', async () => {
  const queue = createMistakeQueue(memoryStorage())
  const first = await queue.enqueue(operation({expectedMistakeVersion: Number.MAX_SAFE_INTEGER - 1}))
  assert.equal(first.status, 'pending')
  const second = await queue.enqueue(operation({expectedMistakeVersion: undefined, clientRequestId: 'op-overflow'}))
  assert.equal(second.expectedMistakeVersion, null)
  assert.equal(second.status, 'blocked')
})

test('scope fencing distinguishes logout and relogin for the same user and textbook', () => {
  const active = {userId: 'user-a', textbookId: 'book-a', generation: 9}
  assert.equal(matchesMistakeScope(active, 'user-a', 'book-a', 9), true)
  assert.equal(matchesMistakeScope(active, 'user-a', 'book-a', 8), false)
})

test('legacy operations without a fixed version block their question chain', async () => {
  const storage = memoryStorage()
  const key = 'syntax-coach-mistake-queue:user-a:book-a'
  storage.raw.set(key, JSON.stringify([operation({expectedMistakeVersion: undefined})]))
  const queue = createMistakeQueue(storage)
  const sent = []
  await queue.flush(async (item) => { sent.push(item); return ack(item) }, 'user-a', 'book-a')
  assert.equal(sent.length, 0)
  await queue.enqueue(operation({questionId: 'q-1', clientRequestId: 'op-next'}))
  const items = queue.list('user-a', 'book-a')
  assert.equal(items[1].status, 'blocked')
})
