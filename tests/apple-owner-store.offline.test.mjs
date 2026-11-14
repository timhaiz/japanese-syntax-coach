import { test } from 'node:test'
import assert from 'node:assert/strict'

 test('owner adapter preserves all three outcomes and exact RPC arguments', async () => {
  const { claimAppleLedgerOwner } = await import('../lib/apple/owner-store.mjs')
  for (const outcome of ['inserted', 'duplicate', 'conflict']) {
    const calls = []
    const client = { rpc: async (...args) => { calls.push(args); return { data: outcome, error: null } } }
    assert.equal(await claimAppleLedgerOwner(client, 'Sandbox', 'chain-1', 'user-1'), outcome)
    assert.deepEqual(calls, [['apple_ledger_claim_owner', { p_environment: 'Sandbox', p_original_transaction_id: 'chain-1', p_user_id: 'user-1' }]])
  }
})

test('owner adapter rejects invalid environment and chain identifiers before RPC', async () => {
  const { claimAppleLedgerOwner } = await import('../lib/apple/owner-store.mjs')
  let calls = 0
  const client = { rpc: async () => { calls++; return { data: 'inserted', error: null } } }
  for (const [environment, chain] of [['sandbox', 'chain'], ['', 'chain'], ['Sandbox', ''], ['Sandbox', 'chain id'], ['Sandbox', 'chain\u0000id'], ['Production', null]]) {
    await assert.rejects(claimAppleLedgerOwner(client, environment, chain, 'user-1'), /invalid ownership identity/)
  }
  assert.equal(calls, 0)
})

test('owner adapter rejects malformed responses and RPC errors', async () => {
  const { claimAppleLedgerOwner } = await import('../lib/apple/owner-store.mjs')
  for (const response of [null, {}, { data: 'inserted' }, { data: 'inserted', error: false }, { data: true, error: null }, { data: 'unknown', error: null }, { data: 'inserted', error: new Error('failed') }]) {
    await assert.rejects(claimAppleLedgerOwner({ rpc: async () => response }, 'Sandbox', 'chain-1', 'user-1'))
  }
})
