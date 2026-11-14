import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isAppleTransactionHistoryOnChain } from '../lib/apple/chain-validation.ts'

const trustedOriginalId = 'original-transaction-1'

test('accepts history only when every transaction carries the explicitly trusted original ID', () => {
  assert.equal(isAppleTransactionHistoryOnChain([
    { originalTransactionId: trustedOriginalId, transactionId: 'ordinary-1' },
    { originalTransactionId: trustedOriginalId, transactionId: trustedOriginalId },
  ], trustedOriginalId), true)
})

test('rejects missing or blank trusted original ID', () => {
  for (const id of [undefined, null, '', '  ']) {
    assert.equal(isAppleTransactionHistoryOnChain([{ originalTransactionId: trustedOriginalId }], id), false)
  }
})

test('rejects trusted IDs containing whitespace or control characters even when the history matches', () => {
  for (const id of ['abc def', 'abc\tdef', 'abc\ndef', 'abc\u0000def']) {
    assert.equal(isAppleTransactionHistoryOnChain([{ originalTransactionId: id }], id), false)
  }
})

test('rejects missing or mismatched original ID on any transaction', () => {
  for (const history of [
    [{ originalTransactionId: trustedOriginalId }, {}],
    [{ originalTransactionId: trustedOriginalId }, { originalTransactionId: 'another-chain' }],
  ]) {
    assert.equal(isAppleTransactionHistoryOnChain(history, trustedOriginalId), false)
  }
})

test('does not infer chain membership from transactionId, even when it equals the trusted ID', () => {
  assert.equal(isAppleTransactionHistoryOnChain([{ transactionId: trustedOriginalId }], trustedOriginalId), false)
})

test('rejects malformed and sparse history rather than skipping missing transactions', () => {
  const sparse = Array(1)
  const sparseAfterValid = [{ originalTransactionId: trustedOriginalId }, ,]
  for (const history of [undefined, null, {}, [null], [], sparse, sparseAfterValid]) {
    assert.equal(isAppleTransactionHistoryOnChain(history, trustedOriginalId), false)
  }
})
