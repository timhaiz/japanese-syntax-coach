import {expect, test} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {stripTypeScriptTypes} from 'node:module'
import vm from 'node:vm'
import {isAllowedAppleProduct} from '../../lib/apple/product-policy.mjs'
import {
  VerificationException,
  VerificationStatus,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'
import {createPOST, productionDependencies, type HandlerDependencies} from '../../lib/apple/entitlements-handler'
import {AppleEntitlementWritesDisabledError, AppleVerifierConfigurationError} from '../../lib/apple/server'
import {accountTokenBelongsToUser} from '../../lib/apple/account-token'

type Dependencies = HandlerDependencies

const user = {id: '11111111-2222-4333-8444-555555555555'}
const transaction = {
  appAccountToken: user.id,
  transactionId: 'test-transaction-id',
  productId: 'com.juxintong.nihongo.monthly',
} satisfies JWSTransactionDecodedPayload

function makeDeps(overrides: Partial<Dependencies> = {}) {
  const calls = {verify: 0, update: 0}
  const order: string[] = []
  let writtenTransaction: JWSTransactionDecodedPayload | undefined
  let writtenNotificationType: string | undefined
  const deps = {
    authenticate: async () => {
      order.push('authenticate')
      return {user}
    },
    verifyTransaction: async (_signedTransaction: string) => {
      order.push('verify')
      calls.verify += 1
      return transaction
    },
    accountTokenMatches: (token: string | null | undefined, userId: string) => {
      order.push('accountTokenMatches')
      return token === userId
    },
    productAllowed: (_productId: unknown) => true,
    updateMembership: async (
      receivedTransaction: JWSTransactionDecodedPayload,
      notificationType?: string,
    ) => {
      order.push('updateMembership')
      writtenTransaction = receivedTransaction
      writtenNotificationType = notificationType
      return {updated: true, status: 'active', userId: user.id}
    },
    ...overrides,
  } satisfies Dependencies
  const updateMembership = deps.updateMembership
  deps.updateMembership = async (...args) => {
    calls.update += 1
    return updateMembership(...args)
  }
  return {post: createPOST(deps), calls, order, getWritten: () => ({writtenTransaction, writtenNotificationType})}
}

function request(body: unknown = {signedTransaction: 'test-jws'}, rawBody?: string) {
  return new Request('http://localhost/api/apple/entitlements', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: rawBody ?? JSON.stringify(body),
  })
}

async function json(response: Response) {
  return response.json() as Promise<Record<string, unknown>>
}

test.describe('Apple entitlement route error classification', () => {
  test('actual route applies its product policy before membership update', async () => {
    const source = readFileSync('app/api/apple/entitlements/route.ts', 'utf8')
    const code = stripTypeScriptTypes(source, {mode: 'strip'})
      .replace(/^import \{([^}]+)\} from '([^']+)'$/gm, 'const {$1} = require("$2")')
      .replace('export const runtime', 'const runtime')
      .replace('export const POST', 'const POST') + '\nmodule.exports = {POST}'
    const module = {exports: {} as {POST: (request: Request) => Promise<Response>}}
    let productId = 'com.juxintong.nihongo.other'
    let writes = 0
    const env: Record<string, string | undefined> = {APPLE_SUBSCRIPTION_PRODUCT_IDS: 'com.juxintong.nihongo.monthly'}
    const context = vm.createContext({module, process: {env}, require(id: string) {
      if (id === '@/lib/apple/entitlements-handler') return {createPOST}
      if (id === '@/lib/auth/request-supabase') return {getAuthenticatedSupabase: async () => ({user})}
      if (id === '@/lib/apple/account-token') return {accountTokenBelongsToUser}
      if (id === '@/lib/apple/product-policy.mjs') return {isAllowedAppleProduct}
      if (id === '@/lib/apple/server') return {
        verifyAppleTransaction: async () => ({...transaction, productId}),
        updateMembershipFromAppleTransaction: async () => { writes++; return {updated: true} },
      }
      throw new Error('Unexpected dependency')
    }})
    new vm.Script(code).runInContext(context)
    const post = module.exports.POST
    expect((await post(request())).status).toBe(400)
    expect(writes).toBe(0)
    productId = 'com.juxintong.nihongo.monthly'
    delete env.APPLE_SUBSCRIPTION_PRODUCT_IDS
    expect((await post(request())).status).toBe(503)
    expect(writes).toBe(0)
    env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'com.juxintong.nihongo.monthly'
    expect((await post(request())).status).toBe(200)
    expect(writes).toBe(1)
  })

  test('production product policy reads explicit configuration and fails closed', async () => {
    const previous = process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS
    try {
      delete process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS
      expect(() => productionDependencies.productAllowed(transaction.productId)).toThrow()
      process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'com.juxintong.nihongo.monthly,com.juxintong.nihongo.yearly'
      expect(productionDependencies.productAllowed(transaction.productId)).toBe(true)
      expect(productionDependencies.productAllowed('com.juxintong.nihongo.other')).toBe(false)
      process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = 'com.juxintong.nihongo.monthly, com.juxintong.nihongo.yearly'
      expect(() => productionDependencies.productAllowed(transaction.productId)).toThrow()
    } finally {
      if (previous === undefined) delete process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS
      else process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS = previous
    }
  })

  test('rejects non-allowlisted products before membership write', async () => {
    const {post, calls, order} = makeDeps({productAllowed: () => false})
    const response = await post(request())
    expect(response.status).toBe(400)
    expect(calls.update).toBe(0)
    expect(order).toEqual(['authenticate', 'verify', 'accountTokenMatches'])
  })

  test('fails closed when product allowlist configuration is unavailable', async () => {
    const {post, calls} = makeDeps({productAllowed: () => { throw new Error('private configuration detail') }})
    const response = await post(request())
    expect(response.status).toBe(503)
    expect(await response.text()).not.toContain('private configuration detail')
    expect(calls.update).toBe(0)
  })

  test('returns 401 before validation or database write when unauthenticated', async () => {
    const {post, calls} = makeDeps({
      authenticate: async () => ({response: new Response(null, {status: 401})}),
    })
    const response = await post(request())
    expect(response.status).toBe(401)
    expect(calls).toEqual({verify: 0, update: 0})
  })

  const invalidInputs: {label: string; body: unknown; rawBody?: string}[][] = [
    [{label: '{}', body: {}}, {label: 'malformed JSON', body: null, rawBody: '{'}],
    [{label: '{"signedTransaction":12}', body: {signedTransaction: 12}}],
    [{label: 'null', body: null}],
  ]
  for (const inputs of invalidInputs) {
    test(`returns 400 for invalid transaction input ${inputs.map(({label}) => label).join(' / ')}`, async () => {
      const {post, calls} = makeDeps()
      for (const input of inputs) {
        const response = await post(request(input.body, input.rawBody))
        expect(response.status).toBe(400)
        expect(await json(response)).toEqual({error: 'signedTransaction required'})
      }
      expect(calls).toEqual({verify: 0, update: 0})
    })
  }

  test('returns 403 for account mismatch and does not write membership', async () => {
    const {post, calls, order} = makeDeps({
      verifyTransaction: async () => {
        order.push('verify')
        return {...transaction, appAccountToken: 'different-account'}
      },
    })
    const response = await post(request())
    expect(response.status).toBe(403)
    expect(await json(response)).toEqual({error: '交易账号与当前账号不匹配。'})
    expect(calls.update).toBe(0)
    expect(order).toEqual(['authenticate', 'verify', 'accountTokenMatches'])
  })

  for (const [label, token] of [
    ['missing', undefined],
    ['null', null],
    ['empty', ''],
    ['whitespace', '   '],
    ['malformed', 'not-a-uuid'],
    ['different account', 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'],
  ] as const) {
    test(`rejects ${label} account token without writing membership`, async () => {
      const {post, calls} = makeDeps({
        accountTokenMatches: accountTokenBelongsToUser,
        verifyTransaction: async () => ({...transaction, appAccountToken: token} as JWSTransactionDecodedPayload),
      })
      const response = await post(request())
      expect(response.status).toBe(403)
      expect(await json(response)).toEqual({error: '交易账号与当前账号不匹配。'})
      expect(calls.update).toBe(0)
    })
  }

  test('rejects a malformed token even if it equals the authenticated user id', async () => {
    const {post, calls} = makeDeps({
      authenticate: async () => ({user: {id: 'not-a-uuid'}}),
      accountTokenMatches: accountTokenBelongsToUser,
      verifyTransaction: async () => ({...transaction, appAccountToken: 'not-a-uuid'}),
    })
    const response = await post(request())
    expect(response.status).toBe(403)
    expect(calls.update).toBe(0)
  })

  test('accepts a matching account token regardless of UUID case', async () => {
    const accountId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
    const {post, calls, getWritten} = makeDeps({
      authenticate: async () => ({user: {id: accountId}}),
      accountTokenMatches: accountTokenBelongsToUser,
      verifyTransaction: async () => ({...transaction, appAccountToken: accountId.toUpperCase()}),
    })
    const response = await post(request())
    expect(response.status).toBe(200)
    expect(calls.update).toBe(1)
    expect(getWritten()).toEqual({
      writtenTransaction: {...transaction, appAccountToken: accountId},
      writtenNotificationType: 'SUBSCRIBED',
    })
  })

  test('returns 503 without writing when Apple verifier configuration is unavailable', async () => {
    const {post, calls} = makeDeps({verifyTransaction: async () => { throw new AppleVerifierConfigurationError() }})
    const response = await post(request())
    expect(response.status).toBe(503)
    expect(await json(response)).toEqual({error: '无法验证 Apple 购买记录。'})
    expect(calls.update).toBe(0)
  })

  test('returns a retryable response when Apple entitlement writes are disabled', async () => {
    const {post, calls} = makeDeps({updateMembership: async () => { throw new AppleEntitlementWritesDisabledError() }})
    const response = await post(request())
    expect(response.status).toBe(503)
    expect(await json(response)).toEqual({error: '无法验证 Apple 购买记录。'})
    expect(calls.update).toBe(1)
  })

  test('does not confirm an unprocessed membership result', async () => {
    const {post, calls} = makeDeps({updateMembership: async () => ({updated: false, reason: 'missing-transaction-identity'})})
    const response = await post(request())
    expect(response.status).toBe(503)
    expect(await json(response)).toEqual({error: '无法验证 Apple 购买记录。'})
    expect(calls.update).toBe(1)
  })

  test('preserves successful response payload', async () => {
    const {post, calls, order, getWritten} = makeDeps()
    const response = await post(request())
    expect(response.status).toBe(200)
    expect(await json(response)).toEqual({updated: true, status: 'active', userId: user.id})
    expect(calls).toEqual({verify: 1, update: 1})
    expect(order).toEqual(['authenticate', 'verify', 'accountTokenMatches', 'updateMembership'])
    expect(getWritten()).toEqual({
      writtenTransaction: {...transaction, appAccountToken: user.id},
      writtenNotificationType: 'SUBSCRIBED',
    })
  })

  test('returns 503 for Apple retryable verification status', async () => {
    const secret = 'private-verifier-detail test-jws'
    const {post, calls} = makeDeps({
      verifyTransaction: async () => {
        throw new VerificationException(
          VerificationStatus.RETRYABLE_VERIFICATION_FAILURE,
          new Error(secret),
        )
      },
    })
    const response = await post(request())
    const body = await response.text()
    expect(response.status).toBe(503)
    expect(body).not.toContain(secret)
    expect(body).not.toContain('test-jws')
    expect(calls.update).toBe(0)
  })

  test('returns generic 500 for non-retryable and unknown verification failures', async () => {
    const failures = [
      new VerificationException(VerificationStatus.VERIFICATION_FAILURE, new Error('bad signature details')),
      new Error('unknown verifier secret'),
      {status: VerificationStatus.RETRYABLE_VERIFICATION_FAILURE, database: 'internal-detail'},
      {database: 'internal-detail'},
    ]
    for (const error of failures) {
      const {post, calls} = makeDeps({verifyTransaction: async () => { throw error }})
      const response = await post(request())
      const body = await response.text()
      expect(response.status).toBe(500)
      expect(body).not.toContain('internal-detail')
      expect(body).not.toContain('unknown verifier secret')
      expect(body).not.toContain('bad signature details')
      expect(body).not.toContain('test-jws')
      expect(calls.update).toBe(0)
    }
  })

  test('returns generic 500 for verifier configuration failure', async () => {
    const {post} = makeDeps({
      verifyTransaction: async () => { throw new Error('Apple verifier secret/config') },
    })
    const response = await post(request())
    const body = await response.text()
    expect(response.status).toBe(500)
    expect(body).not.toContain('secret/config')
    expect(body).not.toContain('test-jws')
  })

  test('returns generic 500 for Error and non-Error membership write failures', async () => {
    for (const error of [new Error('database credentials'), {database: 'private-row'}]) {
      const {post} = makeDeps({updateMembership: async () => { throw error }})
      const response = await post(request())
      const body = await response.text()
      expect(response.status).toBe(500)
      expect(body).not.toContain('database credentials')
      expect(body).not.toContain('private-row')
      expect(body).not.toContain('test-jws')
    }
  })
})
