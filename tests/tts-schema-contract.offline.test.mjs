import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const path = new URL('../supabase/candidates/202611050001_tts_durable_tasks.sql', import.meta.url)
const sql = await readFile(path, 'utf8')

function table(name) {
  return (
    sql.match(new RegExp(`create table public\\.${name}\\s*\\(([\\s\\S]*?)\\n\\);`, 'i'))?.[1] ?? ''
  )
}

test('candidate creates the durable TTS table contract', () => {
  assert.match(sql, /candidate[- ]only|not ready for deployment|do not apply/i)
  for (const name of [
    'tts_textbook_guards',
    'tts_generation_counters',
    'tts_jobs',
    'tts_job_chunks',
    'tts_outbox',
    'tts_manifest_heads',
  ])
    assert.ok(table(name), `public.${name} must be defined`)

  const jobs = table('tts_jobs')
  for (const column of [
    'user_id',
    'textbook_id',
    'idempotency_key',
    'request_digest',
    'schema_version',
    'speaker',
    'engine_version',
    'sentences',
    'snapshot_sha256',
    'snapshot_byte_length',
    'status',
    'total',
    'completed',
    'terminal_at',
    'snapshot_retain_until',
  ])
    assert.match(jobs, new RegExp(`\\b${column}\\b`, 'i'))
  assert.match(jobs, /request_digest[\s\S]*schema_version/i)
  assert.match(jobs, /idempotency_key[\s\S]*unique\s*\(\s*user_id\s*,\s*idempotency_key\s*\)/i)
  assert.match(
    jobs,
    /status\s+text\s+not null\s+check\s*\(\s*status\s+in\s*\(\s*'queued'\s*,\s*'running'\s*,\s*'retry_wait'\s*,\s*'publishing'\s*,\s*'succeeded'\s*,\s*'failed'/i,
  )
  assert.match(jobs, /check\s*\([\s\S]*succeeded[\s\S]*failed[\s\S]*terminal_at/i)
})

test('active-job and idempotency uniqueness match the repository contract', () => {
  assert.match(
    sql,
    /create unique index[\s\S]*on public\.tts_jobs\s*\(\s*user_id\s*,\s*textbook_id\s*\)[\s\S]*where\s+status\s+in\s*\(\s*'queued'\s*,\s*'running'\s*,\s*'retry_wait'\s*,\s*'publishing'\s*\)/i,
  )
  assert.match(sql, /unique\s*\(\s*user_id\s*,\s*idempotency_key\s*\)/i)
})

test('chunk, outbox, lease fencing, object and manifest metadata are constrained', () => {
  const chunks = table('tts_job_chunks')
  const outbox = table('tts_outbox')
  const heads = table('tts_manifest_heads')
  assert.match(chunks, /job_id/i)
  assert.match(chunks, /object_key/i)
  assert.match(chunks, /object_sha256/i)
  assert.match(chunks, /object_byte_length/i)
  assert.match(chunks, /lease_owner/i)
  assert.match(chunks, /lease_expires_at/i)
  assert.match(chunks, /fencing_epoch/i)
  assert.match(outbox, /dispatch_generation/i)
  assert.match(outbox, /available_at/i)
  assert.match(outbox, /lease_owner/i)
  assert.match(outbox, /lease_expires_at/i)
  assert.match(outbox, /fencing_epoch/i)
  assert.match(heads, /manifest_revision/i)
  assert.match(heads, /object_key/i)
  assert.match(heads, /object_sha256/i)
  assert.match(heads, /object_byte_length/i)
  assert.match(heads, /retain_until/i)
  assert.match(sql, /foreign key[\s\S]*references public\.tts_jobs/i)
})

test('indexes support active lookup, outbox leasing, recovery, retention and manifest reads', () => {
  assert.match(
    sql,
    /create unique index[\s\S]*on public\.tts_jobs\s*\(\s*user_id\s*,\s*textbook_id\s*\)/i,
  )
  assert.match(sql, /create index[\s\S]*on public\.tts_outbox\s*\(\s*available_at/i)
  assert.match(sql, /create index[\s\S]*on public\.tts_job_chunks\s*\(\s*lease_expires_at/i)
  assert.match(sql, /create index[\s\S]*on public\.tts_jobs\s*\(\s*snapshot_retain_until/i)
  assert.match(
    sql,
    /create index[\s\S]*on public\.tts_manifest_heads\s*\(\s*user_id\s*,\s*textbook_id\s*(?:,|\))/i,
  )
})

test('all foreign keys restrict deletion and retention windows are represented', () => {
  assert.match(sql, /on delete restrict/i)
  assert.doesNotMatch(sql, /on delete cascade/i)
  assert.match(sql, /idempotency_retain_until/i)
  assert.match(sql, /diagnostics_retain_until/i)
  assert.match(sql, /retain_until/i)
  assert.match(sql, /idempotency_retain_until\s*>=\s*terminal_at\s*\+\s*interval\s+'180 days'/i)
  assert.match(sql, /unreferenced_confirmed_at/i)
})
