import test from 'node:test'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'

const env = process.env
const optIn = env.TTS_PG_INTEGRATION === '1'
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function configurationIsSafe() {
  const required = [
    env.TTS_PG_PROJECT_URL,
    env.TTS_PG_TARGET_ID,
    env.TTS_PG_EXPECTED_TARGET_ID,
    env.TTS_PG_TARGET_CLASS,
    env.TTS_PG_CREDENTIAL,
    env.TTS_PG_ANON_CREDENTIAL,
    env.TTS_PG_TEST_USER_ID,
  ]
  if (required.some((value) => typeof value !== 'string' || value.trim() === '')) return false
  if (!uuidPattern.test(env.TTS_PG_TEST_USER_ID)) return false
  if (env.TTS_PG_TARGET_CLASS !== 'isolated-non-production') return false

  try {
    const url = new URL(env.TTS_PG_PROJECT_URL)
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash)
      return false
    const match = url.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i)
    if (!match) return false
    const projectRef = match[1]
    if (env.TTS_PG_TARGET_ID !== projectRef || env.TTS_PG_EXPECTED_TARGET_ID !== projectRef)
      return false
    if (/production|prod|live/i.test(projectRef)) return false
  } catch {
    return false
  }
  return true
}

if (optIn && !configurationIsSafe()) {
  throw new Error('TTS integration configuration rejected; verify isolated target settings')
}

const describeIntegration = optIn ? test : test.skip
const bytes = (hex) => `\\x${hex.repeat(32)}`
const isPermissionDenied = (error) => error?.code === '42501' || [401, 403].includes(error?.status)

describeIntegration('isolated TTS PostgreSQL integration', async (t) => {
  const { createClient } = await import('@supabase/supabase-js')
  const client = createClient(env.TTS_PG_PROJECT_URL, env.TTS_PG_CREDENTIAL, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })
  const anonClient = createClient(env.TTS_PG_PROJECT_URL, env.TTS_PG_ANON_CREDENTIAL, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })
  const userId = env.TTS_PG_TEST_USER_ID
  const owner = `tts-it-${randomUUID()}`

  function createArgs(textbookId, idempotencyKey) {
    const sentences = [`synthetic ${idempotencyKey}`]
    return {
      p_user_id: userId,
      p_textbook_id: textbookId,
      p_idempotency_key: idempotencyKey,
      p_request_digest: bytes('a'),
      p_schema_version: 1,
      p_speaker: 3,
      p_engine_version: 'integration-synthetic-v1',
      p_sentences: sentences,
      p_snapshot_sha256: bytes('b'),
      p_snapshot_byte_length: 32,
      p_total: sentences.length,
      p_configuration_available: true,
    }
  }

  async function createJob(textbookId, key) {
    const result = await client.rpc('tts_create_job', createArgs(textbookId, key))
    assert.ok(result.error === null, 'synthetic job creation should succeed')
    assert.ok(
      ['created', 'replayed'].includes(result.data?.category),
      'create should return a recognized category',
    )
    assert.ok(uuidPattern.test(result.data?.job_id ?? ''), 'create should return a job UUID')
    return result.data
  }

  t.after(() => {
    // Synthetic rows may persist; no cleanup or delete operation is performed.
  })

  await t.test('concurrent idempotent creates return one persisted job', async () => {
    const textbookId = `synthetic-${randomUUID()}`
    const key = `synthetic-${randomUUID()}`
    const args = createArgs(textbookId, key)
    const results = await Promise.all([
      client.rpc('tts_create_job', args),
      client.rpc('tts_create_job', args),
    ])
    assert.ok(
      results.every(({ error }) => error === null),
      'concurrent create should succeed',
    )
    assert.deepEqual(results.map(({ data }) => data?.category).sort(), ['created', 'replayed'])
    assert.ok(uuidPattern.test(results[0].data?.job_id ?? ''), 'create should return a job UUID')
    assert.ok(
      results[0].data?.job_id === results[1].data?.job_id,
      'idempotent calls should return one job',
    )
  })

  await t.test('failed job insert rolls back generation allocation', async () => {
    const textbookId = `synthetic-${randomUUID()}`
    const oversizedIndexKey = Array.from({ length: 320 }, () => randomUUID()).join('')
    const failed = await client.rpc('tts_create_job', createArgs(textbookId, oversizedIndexKey))
    assert.equal(
      failed.error === null,
      true,
      'the RPC should return its sanitized failure category',
    )
    assert.equal(failed.data?.category, 'internal_error')

    const retry = await client.rpc(
      'tts_create_job',
      createArgs(textbookId, `synthetic-${randomUUID()}`),
    )
    assert.equal(retry.error === null, true, 'retry should succeed after the failed insert')
    assert.equal(retry.data?.category, 'created')
    assert.equal(retry.data?.generation, 1, 'failed transaction must not consume a generation')
  })

  await t.test('anon role is denied direct table insert', async () => {
    const { error } = await anonClient.from('tts_jobs').insert({ user_id: userId })
    assert.ok(
      isPermissionDenied(error),
      'direct insert should be rejected by database permissions or RLS',
    )
  })

  await t.test('anon role is denied the worker RPC', async () => {
    const { data, error } = await anonClient.rpc('tts_claim_chunk', {
      p_job_id: '00000000-0000-4000-8000-000000000000',
      p_chunk_index: 0,
      p_owner: owner,
      p_lease_seconds: 30,
    })
    assert.ok(isPermissionDenied(error), 'worker RPC should be rejected by execute privilege')
    assert.ok(data === null, 'denied RPC should not return data')
  })

  await t.test('stale fencing epoch cannot complete a claimed chunk', async () => {
    const textbookId = `synthetic-${randomUUID()}`
    const job = await createJob(textbookId, `synthetic-${randomUUID()}`)
    const claim = await client.rpc('tts_claim_chunk', {
      p_job_id: job.job_id,
      p_chunk_index: 0,
      p_owner: owner,
      p_lease_seconds: 300,
    })
    assert.ok(claim.error === null, 'chunk claim should succeed')
    assert.equal(claim.data?.category, 'claimed')
    assert.ok(Number.isInteger(claim.data?.epoch) && claim.data.epoch > 0)

    const completion = await client.rpc('tts_complete_chunk', {
      p_job_id: job.job_id,
      p_chunk_index: 0,
      p_owner: owner,
      p_epoch: claim.data.epoch + 1,
      p_object_key: `${owner}/synthetic-chunk`,
      p_object_sha256: bytes('c'),
      p_object_byte_length: 32,
    })
    assert.ok(completion.error === null, 'stale epoch should be represented as an RPC category')
    assert.equal(completion.data?.category, 'stale_lease')
  })

  await t.test('manifest CAS rejects a stale revision after a valid chunk succeeds', async () => {
    const textbookId = `synthetic-${randomUUID()}`
    const job = await createJob(textbookId, `synthetic-${randomUUID()}`)
    const claim = await client.rpc('tts_claim_chunk', {
      p_job_id: job.job_id,
      p_chunk_index: 0,
      p_owner: owner,
      p_lease_seconds: 300,
    })
    assert.ok(claim.error === null, 'chunk claim should succeed')
    assert.equal(claim.data?.category, 'claimed')

    const objectKey = `${owner}/synthetic-manifest-chunk`
    const chunkHash = bytes('d')
    const completion = await client.rpc('tts_complete_chunk', {
      p_job_id: job.job_id,
      p_chunk_index: 0,
      p_owner: owner,
      p_epoch: claim.data.epoch,
      p_object_key: objectKey,
      p_object_sha256: chunkHash,
      p_object_byte_length: 32,
    })
    assert.ok(completion.error === null, 'synthetic chunk completion should succeed')
    assert.equal(completion.data?.category, 'completed')

    const publisherLease = await client.rpc('tts_claim_publisher', {
      p_job_id: job.job_id,
      p_owner: owner,
      p_lease_seconds: 300,
    })
    assert.ok(publisherLease.error === null, 'publisher lease claim should succeed')
    assert.equal(publisherLease.data?.category, 'claimed')

    const manifest = await client.rpc('tts_publish_manifest', {
      p_job_id: job.job_id,
      p_user_id: userId,
      p_textbook_id: textbookId,
      p_expected_revision: 99,
      p_publisher_owner: owner,
      p_publisher_epoch: publisherLease.data.epoch,
      p_manifest_key: `${owner}/synthetic-manifest`,
      p_manifest_sha256: bytes('e'),
      p_manifest_byte_length: 32,
      p_descriptors: [
        { chunk_index: 0, object_key: objectKey, sha256: 'd'.repeat(64), byte_length: 32 },
      ],
    })
    assert.ok(manifest.error === null, 'CAS outcome should be returned by the RPC')
    assert.equal(manifest.data?.category, 'cas_conflict')
  })
})
