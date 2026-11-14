import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import {
  selectAudioCandidates,
  selectJobCandidates,
  selectSnapshotCandidates,
} from '../lib/tts/retention.mjs'

const sqlUrl = new URL('../supabase/candidates/202611050001_tts_durable_tasks.sql', import.meta.url)
const sql = await readFile(sqlUrl, 'utf8')
const day = 24 * 60 * 60 * 1000
const now = Date.parse('2026-11-05T00:00:00.000Z')

const terminalJob = (overrides = {}) => ({
  id: 'job-1',
  status: 'succeeded',
  terminalAt: now - 180 * day,
  snapshotRetainUntil: now - 30 * day,
  diagnosticsRetainUntil: now,
  idempotencyRetainUntil: now,
  ...overrides,
})

test('snapshots require a terminal timestamp and the exact 30-day cutoff', () => {
  const edge = terminalJob({ terminalAt: now - 30 * day, snapshotRetainUntil: now })
  assert.deepEqual(selectSnapshotCandidates([edge], now), ['job-1'])
  assert.deepEqual(
    selectSnapshotCandidates([terminalJob({ terminalAt: now - 30 * day + 1 })], now),
    [],
  )
  assert.deepEqual(
    selectSnapshotCandidates([terminalJob({ status: 'running', terminalAt: null })], now),
    [],
  )
})

test('terminal metadata and idempotency require 180 days and always exclude active jobs', () => {
  assert.deepEqual(selectJobCandidates([terminalJob()], now), ['job-1'])
  assert.deepEqual(selectJobCandidates([terminalJob({ terminalAt: now - 180 * day + 1 })], now), [])
  const active = terminalJob({
    id: 'active',
    status: 'running',
    terminalAt: null,
    idempotencyRetainUntil: now - day,
  })
  assert.deepEqual(selectJobCandidates([active], now), [])
})

test('bounded selectors are idempotent for unchanged input', () => {
  const jobs = ['a', 'b', 'c'].map((id) => terminalJob({ id }))
  assert.deepEqual(selectJobCandidates(jobs, now, { limit: 2 }), ['a', 'b'])
  assert.deepEqual(selectJobCandidates(jobs, now, { limit: 2 }), ['a', 'b'])
  assert.throws(() => selectJobCandidates(jobs, now, { limit: 0 }), RangeError)
})

test('audio needs 30 full unreferenced days, no current-manifest reference, and elapsed write grace', () => {
  const object = {
    key: 'audio/a',
    unreferencedAt: now - 30 * day,
    objectCreatedAt: now - day,
    currentManifestReferences: false,
    writeGraceMs: 60_000,
  }
  assert.deepEqual(selectAudioCandidates([object], now), ['audio/a'])
  assert.deepEqual(
    selectAudioCandidates([{ ...object, unreferencedAt: now - 30 * day + 1 }], now),
    [],
  )
  assert.deepEqual(selectAudioCandidates([{ ...object, currentManifestReferences: true }], now), [])
  assert.deepEqual(selectAudioCandidates([{ ...object, objectCreatedAt: now - 59_999 }], now), [])
})

function retentionFunction(name) {
  return (
    sql.match(
      new RegExp(
        `create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\b[\\s\\S]*?as\\s+\\$function\\$[\\s\\S]*?\\$function\\$`,
        'i',
      ),
    )?.[0] ?? ''
  )
}

test('SQL contract is candidate-only, database-timed, bounded, and two-phase', () => {
  assert.match(sql, /candidate[- ]only/i)
  assert.match(sql, /for update skip locked[\s\S]*limit p_limit/i)
  assert.match(sql, /terminal_at\s*\+\s*interval\s+'30 days'/i)
  assert.match(sql, /terminal_at\s*\+\s*interval\s+'180 days'/i)
  assert.match(sql, /unreferenced_at\s*\+\s*interval\s+'30 days'/i)
  assert.match(sql, /tts_mark_unreferenced_candidates/i)
  const markFunction = retentionFunction('tts_mark_unreferenced_candidates')
  const checkFunction = retentionFunction('tts_check_audio_deletion_candidates')
  for (const [name, definition] of [
    ['mark', markFunction],
    ['check', checkFunction],
  ]) {
    assert.ok(definition, `${name} candidate function must exist`)
    assert.match(
      definition,
      /from public\.tts_manifest_heads h[\s\S]*join public\.tts_jobs manifest_job[\s\S]*manifest_job\.id\s*=\s*h\.job_id/i,
    )
    assert.match(
      definition,
      /manifest_job\.user_id\s*=\s*h\.user_id[\s\S]*manifest_job\.textbook_id\s*=\s*h\.textbook_id/i,
    )
    assert.match(
      definition,
      /join public\.tts_job_chunks manifest_chunk[\s\S]*manifest_chunk\.job_id\s*=\s*manifest_job\.id/i,
    )
    assert.match(definition, /manifest_chunk\.object_key\s*=\s*c\.object_key/i)
    assert.doesNotMatch(definition, /h\.object_key\s*=\s*c\.object_key/i)
  }
  assert.match(sql, /object_created_at[\s\S]*interval\s+'5 minutes'/i)
  assert.doesNotMatch(sql, /delete\s+from\s+storage\./i)
  assert.doesNotMatch(sql, /create\s+trigger[\s\S]*retention/i)
})
