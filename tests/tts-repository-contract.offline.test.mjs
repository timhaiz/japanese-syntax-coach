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
const context = vm.createContext({ Map, structuredClone, Promise })
const contracts = new vm.SourceTextModule(stripTypeScriptTypes(contractsSource), { context })
const repository = new vm.SourceTextModule(stripTypeScriptTypes(repositorySource), { context })
await repository.link(async (specifier) => {
  if (specifier === './contracts.ts') return contracts
  throw new Error(`Unexpected import: ${specifier}`)
})
await repository.evaluate()
const { createInMemoryTtsRepository } = repository.namespace
const assertShape = (actual, expected) =>
  assert.equal(JSON.stringify(actual), JSON.stringify(expected))

const input = (overrides = {}) => ({
  userId: 'user-1',
  textbookId: 'book-1',
  idempotencyKey: 'key-1',
  requestDigest: 'digest-1',
  snapshot: {
    schemaVersion: 1,
    speaker: 3,
    engineVersion: 'engine-1',
    sentences: ['こんにちは'],
    sha256: 'sha256-1',
    byteLength: 15,
  },
  ...overrides,
})

test('accepts a new job with a stable public queued shape', async () => {
  const repository = createInMemoryTtsRepository()
  assertShape(await repository.createJob(input()), {
    kind: 'created',
    job: { id: 'job-1', textbookId: 'book-1', status: 'queued', total: 1, completed: 0 },
  })
})

test('replays the same key and digest without creating another job', async () => {
  const repository = createInMemoryTtsRepository()
  const created = await repository.createJob(input())
  const replayed = await repository.createJob(input())
  assertShape(replayed, { kind: 'replayed', job: created.job })
})

test('replays an existing key without requiring current snapshot configuration', async () => {
  const repository = createInMemoryTtsRepository()
  const created = await repository.createJob(input())
  assertShape(await repository.createJob(input({ snapshot: null })), {
    kind: 'replayed',
    job: created.job,
  })
})

test('reports unavailable configuration only when a new job needs a snapshot', async () => {
  const repository = createInMemoryTtsRepository()
  assertShape(await repository.createJob(input({ snapshot: null })), {
    kind: 'configuration_unavailable',
  })
  assert.equal(await repository.getJob('user-1', 'job-1'), null)
})

test('conflicts when an idempotency key is reused with another digest', async () => {
  const repository = createInMemoryTtsRepository()
  await repository.createJob(input())
  assertShape(await repository.createJob(input({ requestDigest: 'digest-2' })), {
    kind: 'key_conflict',
  })
})

test('rejects another active job for the same user and textbook', async () => {
  const repository = createInMemoryTtsRepository()
  await repository.createJob(input())
  assertShape(await repository.createJob(input({ idempotencyKey: 'key-2' })), {
    kind: 'active_job',
  })
})

test('scopes status lookup to the owning user', async () => {
  const repository = createInMemoryTtsRepository()
  const { job } = await repository.createJob(input())
  assert.deepEqual(await repository.getJob('user-1', job.id), job)
  assert.equal(await repository.getJob('user-2', job.id), null)
  assert.equal(await repository.getJob('user-1', 'missing'), null)
})
