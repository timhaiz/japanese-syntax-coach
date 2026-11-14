import { test } from 'node:test'
import assert from 'node:assert/strict'

test('requires a valid nonempty explicit allowlist and matches exact product IDs', async () => {
  const { isAllowedAppleProduct } = await import('../lib/apple/product-policy.mjs')
  for (const invalid of [undefined, null, '', ' ', 'a,,b', 'a, ', 'a,a', 'a, b\n', 123]) {
    assert.throws(() => isAllowedAppleProduct('a', invalid), /invalid product configuration/)
  }
  assert.equal(isAllowedAppleProduct('a', 'a,b'), true)
  assert.equal(isAllowedAppleProduct('A', 'a,b'), false)
  assert.equal(isAllowedAppleProduct('c', 'a,b'), false)
  assert.equal(isAllowedAppleProduct(undefined, 'a,b'), false)
})

test('matches the configured iOS monthly and yearly product identifiers exactly', async () => {
  const { isAllowedAppleProduct } = await import('../lib/apple/product-policy.mjs')
  const configured = 'com.juxintong.nihongo.monthly,com.juxintong.nihongo.yearly'
  assert.equal(isAllowedAppleProduct('com.juxintong.nihongo.monthly', configured), true)
  assert.equal(isAllowedAppleProduct('com.juxintong.nihongo.yearly', configured), true)
  assert.equal(isAllowedAppleProduct('com.juxintong.nihongo.Monthly', configured), false)
})
