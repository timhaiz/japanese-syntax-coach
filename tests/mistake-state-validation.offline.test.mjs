import test from 'node:test'
import assert from 'node:assert/strict'
import {projectMistakeIds, validateMistakeStateSnapshot} from '../lib/learning/mistake-state-validation.mjs'

const canonical = new Set(['q-1', 'q-2'])
const row = (questionId, overrides = {}) => ({questionId, isMistake: true, version: 1, ...overrides})

test('missing or disabled atomic availability remains legacy-compatible', () => {
  assert.deepEqual(validateMistakeStateSnapshot({}, canonical), {kind: 'legacy'})
  assert.deepEqual(validateMistakeStateSnapshot({mistakeStateAvailable: false}, canonical), {kind: 'legacy'})
})

test('enabled atomic snapshots fail closed on missing, malformed, duplicate, or unknown rows', () => {
  for (const state of [
    {mistakeStateAvailable: true},
    {mistakeStateAvailable: true, mistakeStates: [null]},
    {mistakeStateAvailable: true, mistakeStates: [row('q-1', {version: 0})]},
    {mistakeStateAvailable: true, mistakeStates: [row('q-1'), row('q-1', {isMistake: false})]},
    {mistakeStateAvailable: true, mistakeStates: [row('unknown')]},
    {mistakeStateAvailable: true, mistakeStates: [row('q-1', {version: Number.MAX_SAFE_INTEGER + 1})]},
  ]) assert.deepEqual(validateMistakeStateSnapshot(state, canonical), {kind: 'invalid'})
})

test('valid atomic snapshots return a canonical state map', () => {
  const result = validateMistakeStateSnapshot({mistakeStateAvailable: true, mistakeStates: [row('q-1'), row('q-2', {isMistake: false, version: 7})]}, canonical)
  assert.equal(result.kind, 'atomic')
  assert.deepEqual([...result.states], [['q-1', {isMistake: true, version: 1}], ['q-2', {isMistake: false, version: 7}]])
})

test('local pending operation projection applies removals and re-additions over authoritative snapshot', () => {
  const snapshot = new Map([['q-1', {isMistake: true, version: 2}], ['q-2', {isMistake: false, version: 3}]])
  const projected = projectMistakeIds(snapshot, [
    {questionId: 'q-1', expectedIsMistake: false},
    {questionId: 'q-2', expectedIsMistake: true},
  ], canonical)
  assert.deepEqual([...projected], ['q-2'])
})
