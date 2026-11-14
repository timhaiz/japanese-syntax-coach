import { createClient } from '@supabase/supabase-js'
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'
import { isAllowedAppleProduct } from './product-policy.mjs'

const inactiveNotificationTypes = new Set(['EXPIRED', 'GRACE_PERIOD_EXPIRED', 'REVOKE', 'REFUND'])
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export class AppleVerifierConfigurationError extends Error {
  constructor() {
    super('Apple verification is not configured')
    this.name = 'AppleVerifierConfigurationError'
  }
}

export class AppleEntitlementWritesDisabledError extends Error {
  constructor() {
    super('Apple entitlement writes are disabled pending a validated event-ordering and membership-projection design')
    this.name = 'AppleEntitlementWritesDisabledError'
  }
}

function getEnvironment() {
  const environment = process.env.APPLE_ENVIRONMENT
  if (environment === undefined || environment === 'PRODUCTION') return Environment.PRODUCTION
  if (environment === 'SANDBOX') return Environment.SANDBOX
  throw new AppleVerifierConfigurationError()
}

function getVerifier() {
  const bundleId = process.env.APPLE_BUNDLE_ID
  const roots = (process.env.APPLE_ROOT_CA_BASE64 ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => Buffer.from(value, 'base64'))
  if (!bundleId?.trim() || bundleId !== bundleId.trim() || roots.length === 0) return null
  const environment = getEnvironment()
  const appAppleIdValue = process.env.APPLE_APP_APPLE_ID
  const appAppleId = appAppleIdValue === undefined ? undefined : Number(appAppleIdValue)
  if ((environment === Environment.PRODUCTION && appAppleId === undefined) ||
      (appAppleIdValue !== undefined && (!/^[0-9]+$/.test(appAppleIdValue) || !Number.isSafeInteger(appAppleId) || appAppleId! <= 0))) {
    throw new AppleVerifierConfigurationError()
  }
  try {
    return new SignedDataVerifier(roots, true, environment, bundleId, appAppleId)
  } catch {
    throw new AppleVerifierConfigurationError()
  }
}

export async function verifyAppleTransaction(signedTransaction: string) {
  const verifier = getVerifier()
  if (!verifier) throw new AppleVerifierConfigurationError()
  return verifier.verifyAndDecodeTransaction(signedTransaction)
}

export async function verifyAppleNotification(signedPayload: string) {
  const verifier = getVerifier()
  if (!verifier) throw new AppleVerifierConfigurationError()
  return verifier.verifyAndDecodeNotification(signedPayload)
}

export async function updateMembershipFromAppleTransaction(
  transaction: JWSTransactionDecodedPayload,
  notificationType?: string,
): Promise<{updated: boolean; status?: string; reason?: string; userId?: string}> {
  const userId = transaction.appAccountToken?.trim().toLowerCase()
  if (!userId || !uuidPattern.test(userId)) {
    return { updated: false, reason: 'missing-app-account-token' }
  }
  const originalTransactionId = transaction.originalTransactionId?.trim()
  const transactionId = transaction.transactionId?.trim()
  if (!originalTransactionId || !transactionId) {
    return { updated: false, reason: 'missing-transaction-identity' }
  }
  const productAllowed = isAllowedAppleProduct(
    transaction.productId,
    process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS ?? '',
  )
  if (!productAllowed) {
    return { updated: false, reason: 'unknown-product' }
  }
  const expiresAt = typeof transaction.expiresDate === 'number' && Number.isFinite(transaction.expiresDate)
    ? new Date(transaction.expiresDate).toISOString()
    : null
  const isInactive = inactiveNotificationTypes.has(notificationType ?? '') || Boolean(transaction.revocationDate)
  const isActive = !isInactive && Boolean(transaction.expiresDate && transaction.expiresDate > Date.now())
  if (!isActive && !isInactive) {
    return { updated: false, reason: 'no-membership-state' }
  }
  const purchaseDate = typeof transaction.purchaseDate === 'number' && Number.isFinite(transaction.purchaseDate)
    ? new Date(transaction.purchaseDate).toISOString()
    : new Date().toISOString()
  const signedDate = typeof transaction.signedDate === 'number' && Number.isFinite(transaction.signedDate)
    ? new Date(transaction.signedDate).toISOString()
    : purchaseDate

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()
  const supabaseKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)?.trim()
  if (!url || !supabaseKey) {
    throw new Error('Supabase client is not configured')
  }
  const client = createClient(url, supabaseKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const membershipStatus = isActive ? 'active' : 'expired'
  const { data, error } = await client.rpc('apply_apple_entitlement', {
    p_user_id: userId,
    p_original_transaction_id: originalTransactionId,
    p_transaction_id: transactionId,
    p_product_id: transaction.productId,
    p_membership_status: membershipStatus,
    p_expires_at: expiresAt,
    p_purchase_date: purchaseDate,
    p_signed_date: signedDate,
  })
  if (error) throw error
  const payload = (data ?? {}) as { updated?: boolean; status?: string; reason?: string }
  if (payload.updated !== true) {
    return { updated: false, reason: payload.reason ?? 'stale-or-conflicting-transaction' }
  }
  return {
    updated: true,
    status: payload.status ?? membershipStatus,
    userId,
  }
}
