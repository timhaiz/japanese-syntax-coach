import {expect, test} from '@playwright/test'
import {
  VerificationException,
  VerificationStatus,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'
import {createPOST, type HandlerDependencies} from '../../lib/apple/entitlements-handler'

type Dependencies = HandlerDependencies

const user = {id: '11111111-2222-4333-8444-555555555555'}
const transaction = {
  appAccountToken: user.id,
  transactionId: 'test-transaction-id',
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
    updateMembership: async (
      receivedTransaction: JWSTransactionDecodedPayload,
      notificationType?: string,
    ) => {
      order.push('updateMembership')
      calls.update += 1
      writtenTransaction = receivedTransaction
      writtenNotificationType = notificationType
      return {updated: true, status: 'active', userId: user.id}
    },
    ...overrides,
  } satisfies Dependencies
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

  test('returns 503 only for Apple retryable verification status', async () => {
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
