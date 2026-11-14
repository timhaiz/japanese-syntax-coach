import {NextResponse} from 'next/server'
import {
  VerificationException,
  VerificationStatus,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'
import {getAuthenticatedSupabase} from '@/lib/auth/request-supabase'
import {accountTokenBelongsToUser} from '@/lib/apple/account-token'
import {AppleEntitlementWritesDisabledError, AppleVerifierConfigurationError, updateMembershipFromAppleTransaction, verifyAppleTransaction} from '@/lib/apple/server'
import {isAllowedAppleProduct} from '@/lib/apple/product-policy.mjs'

type AuthenticatedUser = {user: {id: string}}
type AuthenticationResult = AuthenticatedUser | {response: Response}
type Transaction = Awaited<ReturnType<typeof verifyAppleTransaction>>

export type HandlerDependencies = {
  authenticate: (request: Request) => Promise<AuthenticationResult>
  verifyTransaction: (signedTransaction: string) => Promise<Transaction>
  accountTokenMatches: typeof accountTokenBelongsToUser
  productAllowed: (productId: unknown) => boolean
  updateMembership: (
    transaction: JWSTransactionDecodedPayload,
    notificationType?: string,
  ) => Promise<unknown>
}

const genericVerificationError = {error: '无法验证 Apple 购买记录。'}

export function createPOST(deps: HandlerDependencies) {
  return async function post(request: Request): Promise<Response> {
    const authenticated = await deps.authenticate(request)
    if ('response' in authenticated) {
      return NextResponse.json({error: '请先登录。'}, {status: 401})
    }
    const {user} = authenticated
    const body = await request.json().catch(() => null) as {signedTransaction?: unknown} | null
    if (typeof body?.signedTransaction !== 'string') {
      return NextResponse.json({error: 'signedTransaction required'}, {status: 400})
    }

    let transaction: Transaction
    try {
      transaction = await deps.verifyTransaction(body.signedTransaction)
    } catch (error) {
      if (
        error instanceof AppleVerifierConfigurationError ||
        (error instanceof VerificationException &&
        error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE)
      ) {
        return NextResponse.json(genericVerificationError, {status: 503})
      }
      return NextResponse.json(genericVerificationError, {status: 500})
    }

    if (!deps.accountTokenMatches(transaction.appAccountToken, user.id)) {
      return NextResponse.json({error: '交易账号与当前账号不匹配。'}, {status: 403})
    }

    let productAllowed: boolean
    try {
      productAllowed = deps.productAllowed(transaction.productId)
    } catch {
      return NextResponse.json(genericVerificationError, {status: 503})
    }
    if (!productAllowed) {
      return NextResponse.json({error: '此 Apple 商品未获支持。'}, {status: 400})
    }

    try {
      const result = await deps.updateMembership(
        {...transaction, appAccountToken: user.id},
        'SUBSCRIBED',
      ) as {updated?: unknown} | null
      if (!result || result.updated !== true) {
        return NextResponse.json(genericVerificationError, {status: 503})
      }
      return NextResponse.json(result)
    } catch (error) {
      const status = error instanceof AppleEntitlementWritesDisabledError ? 503 : 500
      return NextResponse.json(genericVerificationError, {status})
    }
  }
}

export const productionDependencies: HandlerDependencies = {
  authenticate: getAuthenticatedSupabase,
  verifyTransaction: verifyAppleTransaction,
  accountTokenMatches: accountTokenBelongsToUser,
  productAllowed: (productId) => isAllowedAppleProduct(
    productId,
    process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS ?? '',
  ),
  updateMembership: updateMembershipFromAppleTransaction,
}
