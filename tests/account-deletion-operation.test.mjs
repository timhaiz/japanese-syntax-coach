import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createDeletionOperations } from '../lib/account/deletion-operation.mjs'

// Test double only: production storage must implement atomic, durable compare-and-swap.
function memoryStore() {
  const records = new Map()
  return {
    async get(id) { return structuredClone(records.get(id) ?? null) },
    async compareAndSwap(id, expected, value) {
      const current = records.get(id) ?? null
      if ((current?.version ?? null) !== expected) return false
      records.set(id, structuredClone(value))
      return true
    },
  }
}
const key = { identity: 'a', operationId: 'op' }
const setup = () => createDeletionOperations(memoryStore(), ['data', 'account'])

test('ordered steps, replay, and identity isolation', async () => {
  const core = setup()
  assert.equal((await core.create(key)).status, 'ready')
  assert.equal((await core.create(key)).version, 0)
  await assert.rejects(core.get({ ...key, identity: 'b' }), /identity/)
  await assert.rejects(core.create({ ...key, identity: 'b' }), /identity/)
  await assert.rejects(core.begin(key, 'account'), /step/)
  assert.deepEqual(await core.begin(key, 'data'), { status: 'unknown', acquired: true, version: 1 })
  assert.deepEqual(await core.begin(key, 'data'), { status: 'unknown', acquired: false, version: 1 })
  await core.resolve(key, 'data', 'completed', 1)
  assert.equal((await core.get(key)).status, 'ready')
  const attempt = await core.begin(key, 'account')
  assert.equal((await core.resolve(key, 'account', 'completed', attempt.version)).status, 'completed')
  assert.equal((await core.create(key)).status, 'completed')
  await assert.rejects(core.resolve(key, 'account', 'completed', attempt.version), /step/)
  assert.equal((await core.get(key)).status, 'completed')
  await assert.rejects(core.begin(key, 'data'), /step/)
})

test('unknown and partial outcomes never become completion or silently retry', async () => {
  const core = setup()
  await core.create(key)
  await core.begin(key, 'data')
  await assert.rejects(core.begin(key, 'account'), /step/)
  await assert.rejects(core.resolve(key, 'data', 'unknown'), /evidence/)
  assert.equal((await core.get(key)).status, 'unknown')
  await core.resolve(key, 'data', 'not-applied', 1)
  assert.equal((await core.get(key)).status, 'ready')
  const retry = await core.begin(key, 'data')
  await assert.rejects(core.resolve(key, 'data', 'completed', 1), /attempt/)
  await core.resolve(key, 'data', 'completed', retry.version)
  await core.begin(key, 'account')
  assert.equal((await core.get(key)).status, 'unknown')
})

test('storage failures and lost acknowledgements are not interpreted as outcomes', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data', 'account'])
  await core.create(key)
  const cas = store.compareAndSwap
  store.compareAndSwap = async (...args) => { await cas(...args); throw Error('lost acknowledgement') }
  await assert.rejects(core.begin(key, 'data'), /lost acknowledgement/)
  store.compareAndSwap = cas
  assert.equal((await core.get(key)).status, 'unknown')
  store.compareAndSwap = async () => { throw Error('write unavailable') }
  await assert.rejects(core.resolve(key, 'data', 'completed', 1), /write unavailable/)
  store.compareAndSwap = cas
  assert.equal((await core.get(key)).status, 'unknown')
  store.compareAndSwap = async (...args) => { await cas(...args); throw Error('lost acknowledgement') }
  await assert.rejects(core.resolve(key, 'data', 'completed', 1), /lost acknowledgement/)
  store.compareAndSwap = cas
  assert.equal((await core.get(key)).status, 'ready')
  store.get = async () => { throw Error('storage unavailable') }
  await assert.rejects(core.get(key), /storage unavailable/)
})

test('concurrent claims use CAS and only one transition wins', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data'])
  await core.create(key)
  const results = await Promise.allSettled([core.begin(key, 'data'), core.begin(key, 'data')])
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1)
  assert.equal(results.filter(r => r.status === 'rejected').length, 1)
  assert.equal((await core.get(key)).status, 'unknown')
})

test('concurrent creates preserve one globally keyed operation', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data'])
  const results = await Promise.allSettled([core.create(key), core.create(key)])
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1)
  assert.equal(results.filter(r => r.status === 'rejected').length, 1)
  assert.match(results.find(r => r.status === 'rejected').reason.message, /concurrent modification/)
  assert.deepEqual(await core.get(key), { status: 'ready', version: 0 })
})

test('concurrent resolutions cannot both apply the same attempt', async () => {
  const core = setup()
  await core.create(key)
  const attempt = await core.begin(key, 'data')
  const results = await Promise.allSettled([
    core.resolve(key, 'data', 'completed', attempt.version),
    core.resolve(key, 'data', 'not-applied', attempt.version),
  ])
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1)
  assert.equal(results.filter(r => r.status === 'rejected').length, 1)
  assert.match(results.find(r => r.status === 'rejected').reason.message, /concurrent modification/)
  const result = await core.get(key)
  assert.ok(result.status === 'ready' || result.status === 'completed')
  assert.equal(result.version, 2)
})

test('safe integer version exhaustion rejects transitions without writing', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data'])
  const exhausted = { operationId: key.operationId, identity: key.identity, steps: ['data'], index: 0, pending: null, version: Number.MAX_SAFE_INTEGER }
  assert.equal(await store.compareAndSwap(key.operationId, null, exhausted), true)
  await assert.rejects(core.begin(key, 'data'), /version exhausted/)
  assert.deepEqual(await core.get(key), { status: 'ready', version: Number.MAX_SAFE_INTEGER })
})

test('begin reserves a safe version for resolving the attempt', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data'])
  const record = { operationId: key.operationId, identity: key.identity, steps: ['data'], index: 0, pending: null, version: Number.MAX_SAFE_INTEGER - 1 }
  await store.compareAndSwap(key.operationId, null, record)
  await assert.rejects(core.begin(key, 'data'), /version exhausted/)
  assert.deepEqual(await store.get(key.operationId), record)
})

test('last admissible attempt can resolve using the final safe version', async () => {
  for (const evidence of ['completed', 'not-applied']) {
    const store = memoryStore()
    const core = createDeletionOperations(store, ['data'])
    const record = { operationId: key.operationId, identity: key.identity, steps: ['data'], index: 0, pending: null, version: Number.MAX_SAFE_INTEGER - 2 }
    await store.compareAndSwap(key.operationId, null, record)
    const attempt = await core.begin(key, 'data')
    assert.equal(attempt.version, Number.MAX_SAFE_INTEGER - 1)
    assert.deepEqual(await core.resolve(key, 'data', evidence, attempt.version), {
      status: evidence === 'completed' ? 'completed' : 'ready', version: Number.MAX_SAFE_INTEGER,
    })
  }
})

test('create write with lost acknowledgement is recovered by reading the operation', async () => {
  const store = memoryStore()
  const core = createDeletionOperations(store, ['data'])
  const cas = store.compareAndSwap
  store.compareAndSwap = async (...args) => { await cas(...args); throw Error('create acknowledgement lost') }
  await assert.rejects(core.create(key), /create acknowledgement lost/)
  store.compareAndSwap = cas
  assert.deepEqual(await core.get(key), { status: 'ready', version: 0 })
  assert.deepEqual(await core.create(key), { status: 'ready', version: 0 })
})

test('rejects malformed truthy CAS acknowledgements rather than claiming acquisition', async () => {
  for (const result of ['true', 1, {}]) {
    const store = memoryStore()
    const core = createDeletionOperations(store, ['data'])
    await core.create(key)
    store.compareAndSwap = async () => result
    await assert.rejects(core.begin(key, 'data'), /invalid CAS response/)
  }
})

test('rejects sparse step definitions before creating operations', () => {
  for (const steps of [Array(1), ['data', ,]]) {
    assert.throws(() => createDeletionOperations(memoryStore(), steps), /invalid steps/)
  }
})

test('invalid inputs and corrupt storage fail closed', async () => {
  assert.throws(() => createDeletionOperations(memoryStore(), []), /steps/)
  const core = setup()
  await assert.rejects(core.create({ identity: '', operationId: 'op' }), /identity/)
  const broken = createDeletionOperations({ get: async () => ({ identity: 'a', version: 0 }), compareAndSwap: async () => true }, ['data'])
  await assert.rejects(broken.get(key), /record/)
})
