import { test } from 'node:test'
import assert from 'node:assert/strict'
import { rootCertificates } from 'node:tls'
import { VerificationException } from '@apple/app-store-server-library'
import { updateMembershipFromAppleTransaction, verifyAppleNotification, verifyAppleTransaction } from '../lib/apple/server.ts'

const transaction = {
  appAccountToken: '11111111-2222-4333-8444-555555555555',
  originalTransactionId: 'original-transaction-1',
  transactionId: 'transaction-1',
  productId: 'fictional.product',
  expiresDate: Date.now() + 60_000,
}

// These tests must fail before any database client is created or network is used.
process.env.NEXT_PUBLIC_SUPABASE_URL = ''
process.env.SUPABASE_SERVICE_ROLE_KEY = ''

for (const verify of [verifyAppleNotification, verifyAppleTransaction]) {
  test('missing verifier configuration raises a distinct error', async () => {
    process.env.APPLE_BUNDLE_ID = ''
    process.env.APPLE_ROOT_CA_BASE64 = ''
    await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
  })
}

for (const verify of [verifyAppleNotification, verifyAppleTransaction]) {
  test('invalid root certificate raises a distinct configuration error', async () => {
    process.env.APPLE_BUNDLE_ID = 'fictional.bundle'
    process.env.APPLE_ROOT_CA_BASE64 = Buffer.from('fictional certificate').toString('base64')
    process.env.APPLE_ENVIRONMENT = 'SANDBOX'
    await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
  })
}

test('production verifier without app ID raises a configuration error', async () => {
  process.env.APPLE_BUNDLE_ID = 'fictional.bundle'
  process.env.APPLE_ROOT_CA_BASE64 = Buffer.from(rootCertificates[0]).toString('base64')
  process.env.APPLE_ENVIRONMENT = 'PRODUCTION'
  delete process.env.APPLE_APP_APPLE_ID
  await assert.rejects(verifyAppleNotification('fictional'), { name: 'AppleVerifierConfigurationError' })
})

for (const [name, verify] of [['notification', verifyAppleNotification], ['transaction', verifyAppleTransaction]]) {
  const configure = () => {
    process.env.APPLE_BUNDLE_ID = 'fictional.bundle'
    process.env.APPLE_ROOT_CA_BASE64 = Buffer.from(rootCertificates[0]).toString('base64')
    process.env.APPLE_ENVIRONMENT = 'PRODUCTION'
    process.env.APPLE_APP_APPLE_ID = '12345'
  }

  for (const value of ['', ' ', 'abc', '0', '-1', '1.5', '1e3', '0x10', '9007199254740992']) {
    for (const environment of ['PRODUCTION', 'SANDBOX']) {
      test(`${name}: ${environment} rejects app ID ${JSON.stringify(value)}`, async () => {
        configure()
        process.env.APPLE_ENVIRONMENT = environment
        process.env.APPLE_APP_APPLE_ID = value
        await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
      })
    }
  }

  for (const value of ['', ' ', 'sandbox', 'UNKNOWN']) {
    test(`${name}: rejects environment ${JSON.stringify(value)}`, async () => {
      configure()
      process.env.APPLE_ENVIRONMENT = value
      await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
    })
  }

  test(`${name}: rejects whitespace bundle ID`, async () => {
    configure()
    process.env.APPLE_BUNDLE_ID = '  '
    await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
  })

  for (const value of [' fictional.bundle', 'fictional.bundle ', '\tfictional.bundle\n']) {
    test(`${name}: rejects bundle ID with surrounding whitespace ${JSON.stringify(value)}`, async () => {
      configure()
      process.env.APPLE_BUNDLE_ID = value
      await assert.rejects(verify('fictional'), { name: 'AppleVerifierConfigurationError' })
    })
  }

  for (const environment of [undefined, 'PRODUCTION', 'SANDBOX']) {
    test(`${name}: valid ${environment ?? 'default'} configuration reaches payload verification`, async () => {
      configure()
      if (environment === undefined) delete process.env.APPLE_ENVIRONMENT
      else process.env.APPLE_ENVIRONMENT = environment
      if (environment === 'SANDBOX') delete process.env.APPLE_APP_APPLE_ID
      await assert.rejects(verify('fictional'), VerificationException)
    })
  }
}

test('valid purchase requires configured product IDs before database access', async () => {
  process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = ''
  await assert.rejects(updateMembershipFromAppleTransaction(transaction), /invalid product configuration/)
})

test('missing identifiers are rejected before database access', async () => {
  process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'fictional.product'
  assert.deepEqual(
    await updateMembershipFromAppleTransaction({ ...transaction, originalTransactionId: undefined }),
    { updated: false, reason: 'missing-transaction-identity' },
  )
  assert.deepEqual(
    await updateMembershipFromAppleTransaction({ ...transaction, transactionId: undefined }),
    { updated: false, reason: 'missing-transaction-identity' },
  )
})
