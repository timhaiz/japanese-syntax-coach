import test from 'node:test'
import assert from 'node:assert/strict'
import {readMistakeState, recordAnswerWithMistakes, mistakeStateResponse} from '../lib/learning/mistake-state-api.mjs'

test('study state uses an explicit rollout gate and preserves atomic tombstones', async () => {
  let calls = 0
  const rows = [{questionId: 'L01-Q001', isMistake: false, version: 4}]
  const client = {rpc: async () => { calls++; return {data: rows} }}
  assert.deepEqual(await mistakeStateResponse(client, 'builtin-japanese-syntax', false), {mistakeStateAvailable: false})
  assert.equal(calls, 0)
  assert.deepEqual(await mistakeStateResponse(client, 'builtin-japanese-syntax', true), {mistakeStateAvailable: true, mistakeStates: rows})
  assert.equal(calls, 1)
})

test('transport exceptions produce safe unavailable responses and never confirm a write', async () => {
  const client = {rpc: async () => { throw new Error('sensitive transport detail') }}
  const result = await recordAnswerWithMistakes(client, answer)
  assert.equal(result.status, 503)
  assert.ok(!JSON.stringify(result).includes('sensitive'))
  await assert.rejects(readMistakeState(client, answer.textbookId), /^Error: Mistake state unavailable$/)
})

const answer = {clientRequestId: 'operation-1', textbookId: 'builtin-japanese-syntax', questionId: 'L01-Q001', lessonId: 1, answer: 'A', correct: true, mode: 'mistakes', expectedMistakeVersion: 2}

test('a version conflict remains explicit and never retries using a newer version', async () => {
  const calls = []
  const result = await recordAnswerWithMistakes({rpc: async (...args) => { calls.push(args); return {error: {code: '40001'}} }}, answer)
  assert.equal(result.status, 409)
  assert.equal(result.body.code, 'mistake_version_conflict')
  assert.equal(calls.length, 1)
  assert.equal(calls[0][1].p_expected_version, 2)
})

test('unversioned legacy answers are held without writing', async () => {
  let writes = 0
  const result = await recordAnswerWithMistakes({rpc: async () => { writes++; return {} }}, {...answer, expectedMistakeVersion: undefined})
  assert.equal(result.status, 428)
  assert.equal(writes, 0)
})

test('atomic writes return the existing record response contract only after a valid acknowledgement', async () => {
  let params
  const result = await recordAnswerWithMistakes({rpc: async (name, input) => {
    assert.equal(name, 'record_textbook_answer_with_mistakes_v1'); params = input
    return {data: {duplicate: false, answer: {saved: true}, questionId: answer.questionId, isMistake: false, version: 3}}
  }}, answer)
  assert.equal(result.status, 200)
  assert.equal(result.body.mistakeStateAvailable, true)
  assert.deepEqual(result.body.record, {saved: true})
  assert.equal(params.p_operation_id, answer.clientRequestId)
  assert.equal(params.p_mode, 'mistakes')
})

test('missing schema or malformed acknowledgement never confirms a write', async () => {
  for (const response of [null, undefined, {error: {code: 'PGRST202', message: 'sensitive server detail'}}, {data: null}, {data: {duplicate: false}}, {data: {duplicate: false, answer: {}, questionId: answer.questionId, version: 3, isMistake: true}}]) {
    const result = await recordAnswerWithMistakes({rpc: async () => response}, answer)
    assert.equal(result.status, 503)
    assert.equal(result.body.record, undefined)
    assert.ok(!JSON.stringify(result).includes('sensitive'))
  }
})

test('read state includes tombstone versions and rejects unknown or malformed state', async () => {
  const rows = [{questionId: answer.questionId, isMistake: false, version: 3}]
  assert.deepEqual(await readMistakeState({rpc: async () => ({data: rows})}, answer.textbookId), rows)
  for (const response of [{error: {code: '22023'}}, {data: {}}, {data: [{...rows[0], version: -1}]}, {data: [...rows, ...rows]}]) {
    await assert.rejects(readMistakeState({rpc: async () => response}, answer.textbookId), /unavailable/)
  }
})
