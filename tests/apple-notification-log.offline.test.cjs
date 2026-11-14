'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { stripTypeScriptTypes } = require('node:module')
const vm = require('node:vm')
const appleLibrary = require('@apple/app-store-server-library')
class AppleVerifierConfigurationError extends Error {}

const route = readFileSync(new URL('../app/api/apple/notifications/route.ts', `file://${__filename}`), 'utf8')
const nextImport = "import { NextResponse } from 'next/server'"
const appleImport = "import { updateMembershipFromAppleTransaction, verifyAppleNotification, verifyAppleTransaction } from '@/lib/apple/server'"
const stripped = stripTypeScriptTypes(route, { mode: 'strip' })
assert.ok(stripped.includes(nextImport) && stripped.includes(appleImport))
const code = stripped.replace(nextImport, "const { NextResponse } = require('next/server')")
  .replace(appleImport, "const { updateMembershipFromAppleTransaction, verifyAppleNotification, verifyAppleTransaction } = require('@/lib/apple/server')")
  .replace("import { AppleVerifierConfigurationError } from '@/lib/apple/server'", "const { AppleVerifierConfigurationError } = require('@/lib/apple/server')")
  .replace("import { VerificationException, VerificationStatus } from '@apple/app-store-server-library'", "const { VerificationException, VerificationStatus } = require('@apple/app-store-server-library')")
  .replace('export const runtime', 'const runtime')
  .replace('export async function POST', 'async function POST') + '\nmodule.exports = { POST }'

test('verified notification cannot confirm success while real entitlement writes are disabled', async () => {
  const { updateMembershipFromAppleTransaction } = require('../lib/apple/server.ts')
  const module = { exports: {} }
  const context = vm.createContext({ module, console: { error() {} }, require(id) {
    if (id === '@apple/app-store-server-library') return appleLibrary
    if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
    if (id === '@/lib/apple/server') return {
      AppleVerifierConfigurationError,
      verifyAppleNotification: async () => ({ notificationType: 'SUBSCRIBED', data: { signedTransactionInfo: 'fictional' } }),
      verifyAppleTransaction: async () => ({ transactionId: 'fictional', productId: 'fictional' }),
      updateMembershipFromAppleTransaction,
    }
    throw new Error('Unexpected dependency')
  } })
  new vm.Script(code).runInContext(context)
  const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
  assert.equal(response.status, 503)
  assert.equal(response.body.error, 'Apple notification not processed')
})

for (const stage of ['notification', 'transaction']) {
  test(`${stage} retryable SDK verification error returns 503`, async () => {
    const module = { exports: {} }
    const logs = []
    const context = vm.createContext({ module, console: { error: (...args) => logs.push(args) }, require(id) {
      if (id === '@apple/app-store-server-library') return appleLibrary
      if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
      if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
        verifyAppleNotification: async () => { if (stage === 'notification') throw new appleLibrary.VerificationException(appleLibrary.VerificationStatus.RETRYABLE_VERIFICATION_FAILURE); return { data: { signedTransactionInfo: 'fictional' } } },
        verifyAppleTransaction: async () => { throw new appleLibrary.VerificationException(appleLibrary.VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) },
        updateMembershipFromAppleTransaction: async () => { throw new Error('unexpected update') },
      }
      throw new Error('Unexpected dependency')
    } })
    new vm.Script(code).runInContext(context)
    const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
    assert.equal(response.status, 503)
    assert.deepEqual(logs, [['Apple notification verification unavailable']])
  })
}

for (const stage of ['notification', 'transaction']) {
  for (const kind of ['forged', 'nonretryable']) {
    test(`${stage} ${kind} verification failure is not classified as retryable`, async () => {
      const module = { exports: {} }
      const logs = []
      const failure = kind === 'forged'
        ? { status: appleLibrary.VerificationStatus.RETRYABLE_VERIFICATION_FAILURE }
        : new appleLibrary.VerificationException(appleLibrary.VerificationStatus.VERIFICATION_FAILURE)
      const context = vm.createContext({ module, console: { error: (...args) => logs.push(args) }, require(id) {
        if (id === '@apple/app-store-server-library') return appleLibrary
        if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
        if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
          verifyAppleNotification: async () => { if (stage === 'notification') throw failure; return { data: { signedTransactionInfo: 'fictional' } } },
          verifyAppleTransaction: async () => { throw failure },
          updateMembershipFromAppleTransaction: async () => { throw new Error('unexpected update') },
        }
        throw new Error('Unexpected dependency')
      } })
      new vm.Script(code).runInContext(context)
      const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
      assert.equal(response.status, 400)
      assert.deepEqual(logs, [['Apple notification rejected']])
    })
  }
}

for (const stage of ['notification', 'transaction']) {
  test(`${stage} verifier configuration failure returns 503`, async () => {
    const module = { exports: {} }
    const logs = []
    const context = vm.createContext({ module, console: { error: (...args) => logs.push(args) }, require(id) {
      if (id === '@apple/app-store-server-library') return appleLibrary
      if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
      if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
        verifyAppleNotification: async () => { if (stage === 'notification') throw new AppleVerifierConfigurationError(); return { data: { signedTransactionInfo: 'fictional' } } },
        verifyAppleTransaction: async () => { throw new AppleVerifierConfigurationError() },
        updateMembershipFromAppleTransaction: async () => { throw new Error('unexpected update') },
      }
      throw new Error('Unexpected dependency')
    } })
    new vm.Script(code).runInContext(context)
    const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
    assert.equal(response.status, 503)
    assert.deepEqual(logs, [['Apple notification verification unavailable']])
  })
}

for (const scenario of ['test-without-transaction', 'invalid-signature', 'test-with-transaction']) {
  test(`Apple TEST notification: ${scenario}`, async () => {
    const module = { exports: {} }
    let transactionVerifications = 0
    let updates = 0
    const context = vm.createContext({ module, console: { error() {} }, require(id) {
      if (id === '@apple/app-store-server-library') return appleLibrary
      if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
      if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
        verifyAppleNotification: async () => {
          if (scenario === 'invalid-signature') throw new appleLibrary.VerificationException(appleLibrary.VerificationStatus.VERIFICATION_FAILURE)
          return { notificationType: 'TEST', data: scenario === 'test-with-transaction' ? { signedTransactionInfo: 'fictional' } : {} }
        },
        verifyAppleTransaction: async () => { transactionVerifications += 1; return {} },
        updateMembershipFromAppleTransaction: async () => { updates += 1; return { updated: false } },
      }
      throw new Error('Unexpected dependency')
    } })
    new vm.Script(code).runInContext(context)
    const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
    assert.equal(response.status, scenario === 'test-without-transaction' ? 200 : scenario === 'invalid-signature' ? 400 : 503)
    if (scenario === 'test-without-transaction') assert.equal(response.body.received, true)
    assert.equal(transactionVerifications, scenario === 'test-with-transaction' ? 1 : 0)
    assert.equal(updates, scenario === 'test-with-transaction' ? 1 : 0)
  })
}

test('verified notification without a signed transaction stays retryable', async () => {
  const module = { exports: {} }
  let transactionVerifications = 0
  const context = vm.createContext({
    module,
    console: { error() {} },
    require(id) {
      if (id === '@apple/app-store-server-library') return appleLibrary
      if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
      if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
        verifyAppleNotification: async () => ({ data: {} }),
        verifyAppleTransaction: async () => { transactionVerifications += 1; return {} },
        updateMembershipFromAppleTransaction: async () => ({ updated: true }),
      }
      throw new Error('Unexpected dependency')
    },
  })
  new vm.Script(code).runInContext(context)
  const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
  assert.equal(response.status, 503)
  assert.equal(transactionVerifications, 0)
})

for (const updated of [false, true, 'true', 1]) {
  test(`transaction update ${JSON.stringify(updated)} has appropriate status`, async () => {
    const module = { exports: {} }
    const context = vm.createContext({
      module,
      console: { error() {} },
      require(id) {
        if (id === '@apple/app-store-server-library') return appleLibrary
        if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
        if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
          verifyAppleNotification: async () => ({ data: { signedTransactionInfo: 'fictional' } }),
          verifyAppleTransaction: async () => ({}),
          updateMembershipFromAppleTransaction: async () => ({ updated }),
        }
        throw new Error('Unexpected dependency')
      },
    })
    new vm.Script(code).runInContext(context)
    const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
    assert.equal(response.status, updated === true ? 200 : 503)
  })
}

for (const stage of ['notification', 'transaction', 'update']) {
  for (const kind of ['error', 'object']) {
    test(`${stage} ${kind} failure logs only a fixed message`, async () => {
      const logs = []
      const module = { exports: {} }
      const fail = () => { throw kind === 'error' ? new Error('fictional-private-marker') : { detail: 'fictional-private-marker' } }
      const context = vm.createContext({
        module,
        console: { error: (...args) => logs.push(args) },
        require(id) {
          if (id === '@apple/app-store-server-library') return appleLibrary
        if (id === 'next/server') return { NextResponse: { json: (body, init) => ({ body, status: init?.status ?? 200 }) } }
          if (id === '@/lib/apple/server') return {
        AppleVerifierConfigurationError,
            verifyAppleNotification: async () => stage === 'notification' ? fail() : { data: { signedTransactionInfo: 'fictional' } },
            verifyAppleTransaction: async () => stage === 'transaction' ? fail() : {},
            updateMembershipFromAppleTransaction: async () => stage === 'update' ? fail() : { updated: true },
          }
          throw new Error('Unexpected dependency')
        },
      })
      new vm.Script(code).runInContext(context)
      const response = await module.exports.POST({ json: async () => ({ signedPayload: 'fictional' }) })
      assert.equal(response.status, stage === 'update' ? 503 : 400)
      assert.equal(response.body.error, stage === 'update' ? 'Apple notification not processed' : 'Invalid Apple notification')
      assert.deepEqual(logs, [[stage === 'update' ? 'Apple notification processing failed' : 'Apple notification rejected']])
    })
  }
}
