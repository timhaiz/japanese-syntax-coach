import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { updateMembershipFromAppleTransaction } from '../lib/apple/server.ts'

const migration = await readFile(new URL('../supabase/migrations/202611030001_apple_transaction_ownership.sql', import.meta.url), 'utf8')

process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'fictional.product'
process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://invalid.example'
process.env.SUPABASE_SERVICE_ROLE_KEY = 'not-a-real-key'

const originalFetch = globalThis.fetch
let fetchCalls = 0
globalThis.fetch = async () => {
  fetchCalls += 1
  throw new Error('Supabase must not be contacted')
}

const baseTransaction = {
  appAccountToken: '11111111-2222-4333-8444-555555555555',
  originalTransactionId: 'original-transaction-1',
  transactionId: 'transaction-1',
  productId: 'fictional.product',
  expiresDate: Date.now() + 60_000,
}

test('all Apple membership writes validate identifiers before database access', async () => {
  assert.deepEqual(
    await updateMembershipFromAppleTransaction({ ...baseTransaction, originalTransactionId: undefined }),
    { updated: false, reason: 'missing-transaction-identity' },
  )
  assert.deepEqual(
    await updateMembershipFromAppleTransaction({ ...baseTransaction, transactionId: undefined }),
    { updated: false, reason: 'missing-transaction-identity' },
  )
  assert.deepEqual(
    await updateMembershipFromAppleTransaction({ ...baseTransaction, productId: 'unknown.product' }),
    { updated: false, reason: 'unknown-product' },
  )
  assert.equal(fetchCalls, 0)
})

test('candidate ownership migration unconditionally aborts and contains no executable DDL or RPC', async () => {
  const executable = migration.replace(/^\s*(?:--[^\n]*\n)*/gm, '').trimStart()
  const abort = /^do \$\$\s*begin\s+raise exception 'Apple ownership migration is intentionally disabled';\s*end;\s*\$\$;/i.exec(executable)
  assert.ok(abort, 'migration entry must be an unconditional exception block')
  assert.doesNotMatch(executable, /^\s*(?:create table|alter table|create or replace function|revoke|grant)\b/im)
  assert.match(migration, /NOT READY FOR DEPLOYMENT/)
  const candidate = await readFile(new URL('../supabase/candidates/202611030001_apple_transaction_ownership.sql', import.meta.url), 'utf8')
  assert.match(candidate, /create table public\.apple_transaction_ownership/)
  assert.match(candidate, /create or replace function public\.apply_apple_transaction/)
})

test.after(() => {
  globalThis.fetch = originalFetch
})
