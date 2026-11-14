import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const contractsSource = await readFile(new URL('../lib/tts/contracts.ts', import.meta.url), 'utf8')
const repositorySource = await readFile(
  new URL('../lib/tts/repository.ts', import.meta.url),
  'utf8',
)
const adapterSource = await readFile(
  new URL('../lib/tts/supabase-repository.ts', import.meta.url),
  'utf8',
)
const context = vm.createContext({ Promise, Map, Object, Array, Set, JSON })
const contracts = new vm.SourceTextModule(stripTypeScriptTypes(contractsSource), { context })
const repository = new vm.SourceTextModule(stripTypeScriptTypes(repositorySource), { context })
const adapter = new vm.SourceTextModule(stripTypeScriptTypes(adapterSource), { context })
await adapter.link(async (specifier) => {
  if (specifier === './contracts.ts') return contracts
  if (specifier === './repository.ts') return repository
  if (specifier === 'server-only') return new vm.SourceTextModule('', { context })
  throw new Error(`Unexpected import: ${specifier}`)
})
await adapter.evaluate()
const { createSupabaseTtsRepository } = adapter.namespace

const makeClient = (handler) => ({ rpc: async (name, args) => handler(name, args) })
const input = {
  userId: 'user-1',
  textbookId: 'book-1',
  idempotencyKey: 'key-1',
  requestDigest: 'a'.repeat(64),
  snapshot: {
    schemaVersion: 1,
    speaker: 3,
    engineVersion: 'engine',
    sentences: ['こんにちは'],
    sha256: 'b'.repeat(64),
    byteLength: 15,
  },
}
const jobRow = {
  job_id: 'job-1',
  textbook_id: 'book-1',
  status: 'queued',
  total: 1,
  completed: 0,
  error_code: null,
}

test('maps create outcomes using the narrowly scoped create RPC', async () => {
  const calls = []
  const repo = createSupabaseTtsRepository(
    makeClient(async (name, args) => {
      calls.push({ name, args })
      return { data: { category: 'created', ...jobRow }, error: null }
    }),
  )
  assert.equal(
    JSON.stringify(await repo.createJob(input)),
    JSON.stringify({
      kind: 'created',
      job: { id: 'job-1', textbookId: 'book-1', status: 'queued', total: 1, completed: 0 },
    }),
  )
  assert.equal(calls[0].name, 'tts_create_job')
  assert.equal(calls[0].args.p_user_id, 'user-1')
  assert.deepEqual(calls[0].args.p_sentences, ['こんにちは'])
})

test('maps replay from persisted fields even when current request differs', async () => {
  const persisted = {
    category: 'replayed',
    job_id: 'job-1',
    textbook_id: 'original-book',
    status: 'succeeded',
    total: 8,
    completed: 8,
    error_code: 'render_failed',
  }
  const repo = createSupabaseTtsRepository(
    makeClient(async () => ({ data: persisted, error: null })),
  )
  assert.equal(
    JSON.stringify(
      await repo.createJob({
        ...input,
        textbookId: 'current-book',
        snapshot: { ...input.snapshot, sentences: ['changed'] },
      }),
    ),
    JSON.stringify({
      kind: 'replayed',
      job: {
        id: 'job-1',
        textbookId: 'original-book',
        status: 'succeeded',
        total: 8,
        completed: 8,
        errorCode: 'render_failed',
      },
    }),
  )
})

test('returns null for absent or foreign-user reads and sends both owner and job ID', async () => {
  const calls = []
  const repo = createSupabaseTtsRepository(
    makeClient(async (name, args) => {
      calls.push({ name, args })
      return { data: null, error: null }
    }),
  )
  assert.equal(await repo.getJob('user-2', 'job-1'), null)
  assert.equal(calls[0].name, 'tts_get_job_for_user')
  assert.equal(
    JSON.stringify(calls[0].args),
    JSON.stringify({ p_user_id: 'user-2', p_job_id: 'job-1' }),
  )
})

test('redacts transient Supabase errors and rejected RPC messages', async () => {
  for (const response of [
    async () => ({ data: null, error: { message: 'secret sql and snapshot text' } }),
    async () => {
      throw new Error('secret rejected sql and snapshot text')
    },
  ]) {
    const repo = createSupabaseTtsRepository({ rpc: async () => response() })
    await assert.rejects(repo.getJob('user-1', 'job-1'), (error) => {
      assert.equal(error.message, 'TTS repository unavailable')
      assert.doesNotMatch(error.message, /secret|snapshot|sql/i)
      return true
    })
  }
})

test('exposes typed worker RPC methods through RPC only', async () => {
  const calls = []
  const repo = createSupabaseTtsRepository(
    makeClient(async (name, args) => {
      calls.push({ name, args })
      return { data: { category: 'claimed', rows: [] }, error: null }
    }),
  )
  await repo.claimChunk({ jobId: 'job-1', chunkIndex: 0, owner: 'worker', leaseSeconds: 30 })
  await repo.renewChunkLease({
    jobId: 'job-1',
    chunkIndex: 0,
    owner: 'worker',
    epoch: 1,
    leaseSeconds: 30,
  })
  await repo.completeChunk({
    jobId: 'job-1',
    chunkIndex: 0,
    owner: 'worker',
    epoch: 1,
    objectKey: 'key',
    sha256: 'c'.repeat(64),
    byteLength: 4,
  })
  await repo.claimPublisher({ jobId: 'job-1', owner: 'publisher', leaseSeconds: 60 })
  await repo.renewPublisherLease({ jobId: 'job-1', owner: 'publisher', epoch: 2, leaseSeconds: 60 })
  await repo.claimOutbox({ owner: 'worker', limit: 5, leaseSeconds: 30 })
  await repo.markOutboxSent({ id: 'outbox-1', dispatchGeneration: 1, owner: 'worker', epoch: 1 })
  await repo.publishManifest({
    jobId: 'job-1',
    userId: 'user-1',
    textbookId: 'book-1',
    expectedRevision: 0,
    publisherOwner: 'publisher',
    publisherEpoch: 2,
    manifestKey: 'manifest',
    sha256: 'd'.repeat(64),
    byteLength: 9,
    descriptors: [],
  })
  assert.deepEqual(
    calls.map(({ name }) => name),
    [
      'tts_claim_chunk',
      'tts_renew_chunk_lease',
      'tts_complete_chunk',
      'tts_claim_publisher',
      'tts_renew_publisher_lease',
      'tts_claim_outbox',
      'tts_mark_outbox_sent',
      'tts_publish_manifest',
    ],
  )
  assert.equal(
    JSON.stringify(calls[3].args),
    JSON.stringify({
      p_job_id: 'job-1',
      p_owner: 'publisher',
      p_lease_seconds: 60,
    }),
  )
  assert.equal(
    JSON.stringify(calls[4].args),
    JSON.stringify({
      p_job_id: 'job-1',
      p_owner: 'publisher',
      p_epoch: 2,
      p_lease_seconds: 60,
    }),
  )
  assert.equal(calls[7].args.p_expected_revision, 0)
  assert.equal(calls[7].args.p_publisher_owner, 'publisher')
  assert.equal(calls[7].args.p_publisher_epoch, 2)
})
