import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createAccountWriteFenceStore } from '../lib/account/write-fence-store.mjs'

const ok = data => ({ data, error: null })

test('maps all write-fence operations to their server RPCs', async () => {
  const calls = []
  const client = { rpc: async (name, args) => {
    calls.push({ name, args })
    return ok(name.endsWith('begin_write') ? '9007199254740993' : true)
  } }
  const store = createAccountWriteFenceStore(client)

  assert.equal(await store.beginWrite('user-a', 'write-1'), 9007199254740993n)
  assert.equal(await store.beginDeletion('user-a', 'delete-1'), true)
  assert.equal(await store.finishWrite('user-a', 'write-1', 9007199254740993n), true)
  assert.deepEqual(calls, [
    { name: 'account_write_fence_begin_write', args: { p_identity: 'user-a', p_write_id: 'write-1' } },
    { name: 'account_write_fence_begin_deletion', args: { p_identity: 'user-a', p_deletion_id: 'delete-1' } },
    { name: 'account_write_fence_finish_write', args: { p_identity: 'user-a', p_write_id: 'write-1', p_epoch: '9007199254740993' } },
  ])
})

test('validates injected client, identifiers, and bigint epoch without calling RPC', async () => {
  assert.throws(() => createAccountWriteFenceStore(null), /invalid service client/)
  const calls = []
  const store = createAccountWriteFenceStore({ rpc: async (...args) => { calls.push(args); return ok(true) } })
  for (const value of ['', 'x'.repeat(513), null, {}, 1]) {
    await assert.rejects(store.beginWrite(value, 'write-1'), /invalid identity/)
    await assert.rejects(store.beginWrite('user-a', value), /invalid write id/)
    await assert.rejects(store.beginDeletion('user-a', value), /invalid deletion id/)
  }
  for (const epoch of ['', 'x'.repeat(513), null, {}, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(store.finishWrite('user-a', 'write-1', epoch), /invalid epoch/)
  }
  await assert.rejects(store.finishWrite('user-a', 'write-1', Number.MAX_SAFE_INTEGER + 1), /invalid epoch/)
  assert.equal(calls.length, 0)
})

test('preserves epoch precision through a JSON response round trip', async () => {
  const epoch = '9223372036854775807'
  const response = JSON.parse(JSON.stringify({ data: epoch, error: null }))
  const store = createAccountWriteFenceStore({ rpc: async () => response })
  assert.equal(await store.beginWrite('user-a', 'write-1'), 9223372036854775807n)
})

test('preserves epoch precision and rejects malformed begin-write responses', async () => {
  for (const [data, expected] of [[0, 0n], [42, 42n], ['9223372036854775807', 9223372036854775807n], [7n, 7n]]) {
    const store = createAccountWriteFenceStore({ rpc: async () => ok(data) })
    assert.equal(await store.beginWrite('user-a', 'write-1'), expected)
  }
  for (const data of [null, -1, Number.MAX_SAFE_INTEGER + 1, '', '01', '-1', '1.2', {}, [], true]) {
    const store = createAccountWriteFenceStore({ rpc: async () => ok(data) })
    await assert.rejects(store.beginWrite('user-a', 'write-1'), /invalid epoch response/)
  }
})

test('rejects epochs beyond PostgreSQL bigint before use', async () => {
  const calls = []
  const store = createAccountWriteFenceStore({ rpc: async (...args) => { calls.push(args); return ok('9223372036854775808') } })
  await assert.rejects(store.beginWrite('user-a', 'write-1'), /invalid epoch response/)
  await assert.rejects(store.finishWrite('user-a', 'write-1', 9223372036854775808n), /invalid epoch/)
  assert.equal(calls.length, 1)
})

test('requires literal boolean responses and propagates RPC errors', async () => {
  for (const data of [null, 0, 1, 'true', {}, []]) {
    const store = createAccountWriteFenceStore({ rpc: async () => ok(data) })
    await assert.rejects(store.beginDeletion('user-a', 'delete-1'), /invalid fence response/)
    await assert.rejects(store.finishWrite('user-a', 'write-1', 0n), /invalid fence response/)
  }
  const failure = new Error('offline')
  const store = createAccountWriteFenceStore({ rpc: async () => ({ data: true, error: failure }) })
  await assert.rejects(store.beginDeletion('user-a', 'delete-1'), error => error === failure)
})

test('rejects falsy non-null RPC errors rather than treating them as success', async () => {
  for (const error of [undefined, false, 0, '']) {
    const store = createAccountWriteFenceStore({ rpc: async () => ({ data: true, error }) })
    await assert.rejects(store.beginDeletion('user-a', 'delete-1'), /invalid RPC response/)
  }
})

test('preserves false when deletion is not drained or a write cannot be finished', async () => {
  const store = createAccountWriteFenceStore({ rpc: async () => ok(false) })
  assert.equal(await store.beginDeletion('user-a', 'delete-1'), false)
  assert.equal(await store.finishWrite('user-a', 'write-1', 0n), false)
})

test('rejects malformed RPC envelopes and never auto-finishes writes', async () => {
  for (const response of [null, {}, { data: true }]) {
    const store = createAccountWriteFenceStore({ rpc: async () => response })
    await assert.rejects(store.beginDeletion('user-a', 'delete-1'), /invalid RPC response/)
  }
  const calls = []
  const store = createAccountWriteFenceStore({ rpc: async (name) => { calls.push(name); return ok(name.endsWith('begin_write') ? '1' : true) } })
  await store.beginWrite('user-a', 'write-1')
  await store.beginDeletion('user-a', 'delete-1')
  assert.deepEqual(calls, ['account_write_fence_begin_write', 'account_write_fence_begin_deletion'])
})
