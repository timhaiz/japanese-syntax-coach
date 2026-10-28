import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const root = new URL('..', import.meta.url)

function validTransaction(overrides = {}) {
  return {
    appAccountToken: '11111111-1111-4111-8111-111111111111',
    originalTransactionId: 'original-1',
    transactionId: 'transaction-1',
    productId: 'com.example.monthly',
    purchaseDate: Date.now() - 1000,
    signedDate: Date.now(),
    expiresDate: Date.now() + 86400000,
    ...overrides,
  }
}

test('Apple entitlement applies through the ordered service RPC, not direct profiles writes', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.example'
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role'
  process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'com.example.monthly'
  const requests = []
  const transaction = validTransaction()
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url, init) => {
    requests.push({ url: String(url), init })
    return new Response(JSON.stringify({ updated: true, status: 'active', user_id: transaction.appAccountToken }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }
  try {
    const { updateMembershipFromAppleTransaction } = await import('../lib/apple/server.ts')
    const result = await updateMembershipFromAppleTransaction(transaction, 'SUBSCRIBED')
    assert.equal(result.updated, true)
    assert.match(requests[0].url, /\/rpc\/apply_apple_entitlement$/)
    assert.doesNotMatch(requests[0].url, /\/profiles/)
    const body = JSON.parse(requests[0].init.body)
    assert.equal(body.p_user_id, transaction.appAccountToken)
    assert.equal(body.p_original_transaction_id, transaction.originalTransactionId)
    assert.equal(body.p_transaction_id, transaction.transactionId)
    assert.equal(body.p_purchase_date, new Date(transaction.purchaseDate).toISOString())
    assert.equal(body.p_signed_date, new Date(transaction.signedDate).toISOString())
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('missing or invalid transaction timestamps fail closed', async () => {
  const { updateMembershipFromAppleTransaction } = await import('../lib/apple/server.ts')
  assert.deepEqual(
    await updateMembershipFromAppleTransaction(validTransaction({ purchaseDate: undefined }), 'SUBSCRIBED'),
    { updated: false, reason: 'invalid-transaction-data' },
  )
  assert.deepEqual(
    await updateMembershipFromAppleTransaction(validTransaction({ signedDate: Number.NaN }), 'SUBSCRIBED'),
    { updated: false, reason: 'invalid-transaction-data' },
  )
})

test('migration revokes profile writes and enforces ordering and chain ownership', async () => {
  const sql = await readFile(new URL('./supabase/migrations/202610270001_apple_entitlement_ordering.sql', root), 'utf8')
  assert.match(sql, /create table[^;]+apple_entitlement_owners/i)
  assert.match(sql, /original_transaction_id\s+text\s+primary key/i)
  assert.match(sql, /purchase_date/i)
  assert.match(sql, /signed_date/i)
  assert.match(sql, /pg_advisory_xact_lock/i)
  assert.match(sql, /revoke\s+all\s+on\s+public\.profiles\s+from\s+public,\s*anon,\s*authenticated/i)
  assert.match(sql, /security definer/i)
  assert.match(sql, /set search_path\s*=\s*''/i)
  assert.match(sql, /grant execute on function public\.apply_apple_entitlement\([\s\S]+?\)\s+to service_role/i)
})
