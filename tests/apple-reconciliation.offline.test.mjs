import { test } from 'node:test'
import assert from 'node:assert/strict'
import { GetTransactionHistoryVersion } from '@apple/app-store-server-library'
import { readAppleTransactionHistory } from '../lib/apple/reconciliation.ts'

function fixture(pages, failVerification) {
  const calls = []
  const verified = []
  return {
    calls, verified,
    client: { async getTransactionHistory(...args) { calls.push(args); const page = pages.shift(); if (page instanceof Error) throw page; return page } },
    verifier: { async verifyAndDecodeTransaction(value) { verified.push(value); if (value === failVerification) throw new Error('sensitive signature'); return { transactionId: value } } },
  }
}

test('reads all pages with unchanged unfiltered V2 request and verifies every transaction', async () => {
  const f = fixture([{ hasMore: true, revision: 'next', signedTransactions: ['a', 'b'] }, { hasMore: false, signedTransactions: ['c'] }])
  assert.deepEqual(await readAppleTransactionHistory('id', f.client, f.verifier), [{ transactionId: 'a' }, { transactionId: 'b' }, { transactionId: 'c' }])
  assert.deepEqual(f.calls, [['id', null, {}, GetTransactionHistoryVersion.V2], ['id', 'next', {}, GetTransactionHistoryVersion.V2]])
  assert.deepEqual(f.verified, ['a', 'b', 'c'])
})

test('an empty complete history succeeds', async () => {
  const f = fixture([{ hasMore: false, signedTransactions: [] }])
  assert.deepEqual(await readAppleTransactionHistory('id', f.client, f.verifier), [])
})

for (const response of [undefined, {}, { hasMore: false }, { hasMore: true, signedTransactions: [] }, { hasMore: true, revision: '', signedTransactions: [] }, { hasMore: false, signedTransactions: [''] }, { hasMore: false, signedTransactions: [1] }]) {
  test(`malformed page fails closed: ${JSON.stringify(response)}`, async () => {
    const f = fixture([response])
    await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier))
  })
}

test('rejects sparse transaction pages before invoking the verifier', async () => {
  const f = fixture([{ hasMore: false, signedTransactions: ['a', ,] }], 'never-fail')
  await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier), { name: 'AppleReconciliationReadError' })
  assert.deepEqual(f.verified, [])
})

test('oversized revision fails before requesting the next page', async () => {
  const f = fixture([{ hasMore: true, revision: '界'.repeat(5462), signedTransactions: [] }])
  await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier), { name: 'AppleReconciliationReadError' })
  assert.equal(f.calls.length, 1)
})

test('repeated revision fails rather than looping', async () => {
  const f = fixture([{ hasMore: true, revision: 'same', signedTransactions: [] }, { hasMore: true, revision: 'same', signedTransactions: [] }])
  await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier))
  assert.equal(f.calls.length, 2)
})

test('page limit fails without returning the earlier verified transactions', async () => {
  const f = fixture([{ hasMore: true, revision: '1', signedTransactions: ['a'] }, { hasMore: true, revision: '2', signedTransactions: ['b'] }])
  await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier, 2))
  assert.equal(f.calls.length, 2)
})

test('API and verification errors reject without leaking their messages', async () => {
  for (const f of [fixture([{ hasMore: true, revision: 'next', signedTransactions: ['a'] }, new Error('sensitive API')]), fixture([{ hasMore: false, signedTransactions: ['a', 'b'] }], 'b')]) {
    await assert.rejects(readAppleTransactionHistory('id', f.client, f.verifier), error => !String(error).includes('sensitive'))
  }
})

test('local transaction count limit accepts the boundary and rejects excess across pages', async () => {
  const entries = Array(2000).fill('a')
  const atLimit = fixture([{ hasMore: false, signedTransactions: entries }])
  assert.equal((await readAppleTransactionHistory('id', atLimit.client, atLimit.verifier)).length, 2000)
  const over = fixture([{ hasMore: true, revision: 'next', signedTransactions: entries }, { hasMore: false, signedTransactions: ['b'] }])
  await assert.rejects(readAppleTransactionHistory('id', over.client, over.verifier), { name: 'AppleReconciliationReadError' })
  assert.equal(over.verified.length, 2000)
})

test('local signature byte limit accepts boundary and rejects oversized UTF-8 before verifying a page', async () => {
  const atLimit = fixture([{ hasMore: false, signedTransactions: ['a'.repeat(16384)] }])
  assert.equal((await readAppleTransactionHistory('id', atLimit.client, atLimit.verifier)).length, 1)
  const over = fixture([{ hasMore: false, signedTransactions: ['a', '界'.repeat(5462)] }])
  await assert.rejects(readAppleTransactionHistory('id', over.client, over.verifier), { name: 'AppleReconciliationReadError' })
  assert.equal(over.verified.length, 0)
})

test('invalid identifier and limits fail before calling Apple', async () => {
  for (const [id, limit] of [['', 1], ['id', 0], ['id', 1.5], ['id', Infinity], ['id', 101]]) {
    const f = fixture([])
    await assert.rejects(readAppleTransactionHistory(id, f.client, f.verifier, limit))
    assert.equal(f.calls.length, 0)
  }
})
