import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const originalAudioDir = process.env.VOICEVOX_AUDIO_DIR
const originalFetch = globalThis.fetch

test('TTS queue persists before generation and cancellation is user-scoped', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'syntax-coach-tts-'))
  process.env.VOICEVOX_AUDIO_DIR = directory
  let releaseHealth
  let healthRequested
  const healthStarted = new Promise((resolve) => { healthRequested = resolve })
  const healthResponse = new Promise((resolve) => { releaseHealth = resolve })
  globalThis.fetch = async (url) => {
    if (String(url).endsWith('/version')) {
      const jobFiles = await import('node:fs/promises').then(({ readdir }) => readdir(path.join(directory, 'jobs')))
      assert.equal(jobFiles.length, 1, 'job record exists before VOICEVOX starts')
      healthRequested()
      return healthResponse
    }
    throw new Error(`Unexpected VOICEVOX request: ${url}`)
  }

  try {
    const server = await import('../lib/tts/server.ts')
    const textbook = { id: 'test-book', lessons: [{ grammar: [{ example: 'test sentence' }] }] }
    const job = await server.queueTtsGeneration('user-one', textbook)
    await healthStarted
    const persisted = JSON.parse(await readFile(path.join(directory, 'jobs', `${job.id}.json`), 'utf8'))
    assert.ok(['queued', 'running'].includes(persisted.status))

    await server.cancelUserTtsJobs('user-two')
    assert.notEqual((await server.getTtsJob(job.id)).status, 'cancelled')

    const cancellation = server.cancelUserTtsJobs('user-one')
    releaseHealth(new Response('1.0.0', { status: 200 }))
    await cancellation
    assert.equal((await server.getTtsJob(job.id)).status, 'cancelled')

    await server.deleteUserTtsData('user-one')
    assert.equal(await server.getTtsJob(job.id), null)
  } finally {
    releaseHealth?.(new Response('1.0.0', { status: 200 }))
    globalThis.fetch = originalFetch
    await rm(directory, { recursive: true, force: true })
    if (originalAudioDir === undefined) delete process.env.VOICEVOX_AUDIO_DIR
    else process.env.VOICEVOX_AUDIO_DIR = originalAudioDir
  }
})

test('Apple migration uses a service-role-only ordered entitlement RPC and preserves profile reads', async () => {
  const sql = await readFile(new URL('../supabase/migrations/202610270001_apple_entitlement_ordering.sql', import.meta.url), 'utf8')
  assert.match(sql, /grant select on public\.profiles to authenticated/i)
  assert.match(sql, /revoke all on public\.profiles from public,\s*anon,\s*authenticated/i)
  assert.match(sql, /security definer/i)
  assert.match(sql, /set search_path\s*=\s*''/i)
  assert.match(sql, /grant execute on function public\.apply_apple_entitlement\([\s\S]+?\)\s+to service_role/i)
  assert.match(sql, /for update/i)
  assert.match(sql, /apple_original_transaction_id/i)
})
