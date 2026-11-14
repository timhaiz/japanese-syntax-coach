import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createDeletionOperationStore } from '../lib/account/deletion-store.mjs'
import { createDeletionOperations } from '../lib/account/deletion-operation.mjs'

const migration = readFileSync(new URL('../supabase/migrations/202611030002_account_deletion_operation_store.sql', import.meta.url), 'utf8')

test('persistent store maps reads and CAS writes through service RPCs only', async () => {
  const calls = []
  const client = { rpc: async (name, args) => { calls.push({ name, args }); return { data: name.endsWith('_get') ? { operationId: 'op', identity: 'user-a', steps: ['data'], index: 0, pending: null, version: 0 } : true, error: null } } }
  const store = createDeletionOperationStore(client)
  assert.equal((await store.get('op')).operationId, 'op')
  assert.equal(await store.compareAndSwap('op', null, { operationId: 'op', identity: 'user-a', steps: ['data'], index: 0, pending: null, version: 0 }), true)
  assert.deepEqual(calls.map(({ name }) => name), ['account_deletion_operation_get', 'account_deletion_operation_cas'])
  assert.equal(calls[1].args.p_expected_version, null)
})

test('core create and replay round-trip the SQL JSON record through the real adapter', async () => {
  const records = new Map()
  const client = {
    async rpc(name, args) {
      if (name === 'account_deletion_operation_get') {
        // The SQL function returns the jsonb record itself, without column aliases.
        return { data: records.get(args.p_operation_id) ?? null, error: null }
      }
      const { p_operation_id: id, p_expected_version: expected, p_record: next } = args
      const current = records.get(id)
      if (expected === null) {
        if (current) return { data: false, error: null }
        records.set(id, structuredClone(next))
        return { data: true, error: null }
      }
      if (!current || current.version !== expected || current.identity !== next.identity) return { data: false, error: null }
      records.set(id, structuredClone(next))
      return { data: true, error: null }
    },
  }
  const core = createDeletionOperations(createDeletionOperationStore(client), ['data', 'account'])
  const key = { identity: 'user-a', operationId: 'op-json' }
  assert.deepEqual(await core.create(key), { status: 'ready', version: 0 })
  assert.deepEqual(await core.get(key), { status: 'ready', version: 0 })
  assert.deepEqual(await core.create(key), { status: 'ready', version: 0 })
  assert.deepEqual(await core.begin(key, 'data'), { status: 'unknown', acquired: true, version: 1 })
  await assert.rejects(core.get({ ...key, identity: 'user-b' }), /identity mismatch/)
})

test('RPC errors and malformed responses remain indeterminate', async () => {
  const store = createDeletionOperationStore({ rpc: async () => ({ data: null, error: new Error('offline') }) })
  await assert.rejects(store.get('op'), /offline/)
  const malformed = createDeletionOperationStore({ rpc: async () => ({ data: null, error: null }) })
  await assert.rejects(malformed.compareAndSwap('op', null, { operationId: 'op' }), /invalid CAS response/)
})

test('incomplete RPC envelopes never imply absence or successful CAS', async () => {
  for (const response of [{ data: null }, { data: true }, { data: null, error: false }, { data: null, error: undefined }, { error: null }]) {
    const store = createDeletionOperationStore({ rpc: async () => response })
    await assert.rejects(store.get('op'), /invalid RPC response/)
    await assert.rejects(store.findOperationIdByIdentity('user-a'), /invalid RPC response/)
    await assert.rejects(store.compareAndSwap('op', null, {}), /invalid RPC response/)
  }
})

test('adapter rejects malformed or mismatched read records rather than treating them as valid', async () => {
  for (const data of [[], { operationId: 'other' }, {}]) {
    const store = createDeletionOperationStore({ rpc: async () => ({ data, error: null }) })
    await assert.rejects(store.get('op'), /invalid operation response/)
  }
})

test('server-only recovery looks up the operation ID using the trusted identity', async () => {
  const calls = []
  const store = createDeletionOperationStore({ rpc: async (name, args) => {
    calls.push({ name, args })
    return { data: 'original-op', error: null }
  } })
  assert.equal(await store.findOperationIdByIdentity('user-a'), 'original-op')
  assert.deepEqual(calls, [{ name: 'account_deletion_operation_find_by_identity', args: { p_identity: 'user-a' } }])
  for (const identity of ['', null, {}, 1]) await assert.rejects(store.findOperationIdByIdentity(identity), /invalid identity/)
  assert.equal(calls.length, 1)
})

test('recovery preserves absence and rejects RPC errors and malformed IDs', async () => {
  const withResponse = data => createDeletionOperationStore({ rpc: async () => ({ data, error: null }) })
  assert.equal(await withResponse(null).findOperationIdByIdentity('user-a'), null)
  for (const data of ['', {}, [], 'bad id', 'x'.repeat(129)]) {
    await assert.rejects(withResponse(data).findOperationIdByIdentity('user-a'), /invalid operation response/)
  }
  const store = createDeletionOperationStore({ rpc: async () => ({ data: null, error: new Error('offline') }) })
  await assert.rejects(store.findOperationIdByIdentity('user-a'), /offline/)
})

test('review-only recovery SQL is exact identity lookup restricted to service role', () => {
  const candidate = readFileSync(new URL('../supabase/candidates/202611030002_account_deletion_identity_fence.sql', import.meta.url), 'utf8')
  assert.match(candidate, /create function public\.account_deletion_operation_find_by_identity\(p_identity text\)/i)
  assert.match(candidate, /where record->>'identity' = p_identity/i)
  assert.match(candidate, /returns text/i)
  assert.match(candidate, /revoke all on function public\.account_deletion_operation_find_by_identity\(text\) from public, anon, authenticated/i)
  assert.match(candidate, /grant execute on function public\.account_deletion_operation_find_by_identity\(text\) to service_role/i)
})

test('review-only candidate fences concurrent operation IDs for the same identity', () => {
  const candidate = readFileSync(new URL('../supabase/candidates/202611030002_account_deletion_identity_fence.sql', import.meta.url), 'utf8')
  assert.match(candidate, /create unique index[\s\S]*on public\.account_deletion_operations\s*\(\(record->>'identity'\)\)/i)
  assert.match(candidate, /do not apply/i)
})

test('migration enforces a global operation ID key and service-role-only RPC access', () => {
  assert.match(migration, /operation_id text primary key/)
  assert.match(migration, /revoke all on function public\.account_deletion_operation_get\(text\) from public, anon, authenticated/)
  assert.match(migration, /grant execute on function public\.account_deletion_operation_get\(text\) to service_role/)
  assert.match(migration, /revoke all on function public\.account_deletion_operation_cas\(text, bigint, jsonb\) from public, anon, authenticated/)
  assert.match(migration, /grant execute on function public\.account_deletion_operation_cas\(text, bigint, jsonb\) to service_role/)
  assert.match(migration, /where operation_id = p_operation_id\s+and version = p_expected_version\s+and record->'identity' = p_record->'identity'/)
  assert.match(migration, /is not distinct from/)
  assert.match(migration, /is distinct from 'string'/)
  assert.match(migration, /length\(p_record->>'identity'\) = 0/)
})
