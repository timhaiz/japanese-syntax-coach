import { createClient } from '@supabase/supabase-js'
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'

const inactiveNotificationTypes = new Set(['EXPIRED', 'GRACE_PERIOD_EXPIRED', 'REVOKE', 'REFUND'])
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function getEnvironment() {
  return process.env.APPLE_ENVIRONMENT === 'SANDBOX' ? Environment.SANDBOX : Environment.PRODUCTION
}

function getVerifier() {
  const bundleId = process.env.APPLE_BUNDLE_ID
  const roots = (process.env.APPLE_ROOT_CA_BASE64 ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => Buffer.from(value, 'base64'))
  if (!bundleId || roots.length === 0) return null
  const appAppleId = process.env.APPLE_APP_APPLE_ID ? Number(process.env.APPLE_APP_APPLE_ID) : undefined
  return new SignedDataVerifier(roots, true, getEnvironment(), bundleId, appAppleId)
}

export async function verifyAppleTransaction(signedTransaction: string) {
  const verifier = getVerifier()
  if (!verifier) throw new Error('Apple transaction verification is not configured')
  return verifier.verifyAndDecodeTransaction(signedTransaction)
}

export async function verifyAppleNotification(signedPayload: string) {
  const verifier = getVerifier()
  if (!verifier) throw new Error('Apple notification verification is not configured')
  return verifier.verifyAndDecodeNotification(signedPayload)
}

export async function updateMembershipFromAppleTransaction(
  transaction: JWSTransactionDecodedPayload,
  notificationType?: string,
) {
  const userId = transaction.appAccountToken
  if (!userId || !uuidPattern.test(userId)) return { updated: false, reason: 'missing-app-account-token' }
  const originalTransactionId = transaction.originalTransactionId
  const transactionId = transaction.transactionId
  const productId = transaction.productId
  const purchaseDate = transaction.purchaseDate
  const signedDate = transaction.signedDate
  if (
    !originalTransactionId || !transactionId || !productId ||
    !Number.isFinite(purchaseDate) || !Number.isFinite(signedDate)
  ) return { updated: false, reason: 'invalid-transaction-data' }
  const allowedProducts = (process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS ?? '')
    .split(',').map((value) => value.trim()).filter(Boolean)
  if (allowedProducts.length > 0 && !allowedProducts.includes(productId)) {
    return { updated: false, reason: 'unknown-product' }
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !serviceRoleKey) throw new Error('Supabase service role is not configured')
  const admin = createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } })
  const expiresAt = transaction.expiresDate ? new Date(transaction.expiresDate).toISOString() : null
  const isInactive = inactiveNotificationTypes.has(notificationType ?? '') || Boolean(transaction.revocationDate)
  const isActive = !isInactive && Boolean(transaction.expiresDate && transaction.expiresDate > Date.now())
  if (!isActive && !isInactive) return { updated: false, reason: 'no-membership-state' }
  const { data, error } = await admin.rpc('apply_apple_entitlement', {
    p_user_id: userId,
    p_original_transaction_id: originalTransactionId,
    p_transaction_id: transactionId,
    p_product_id: productId,
    p_membership_status: isActive ? 'active' : 'expired',
    p_expires_at: expiresAt,
    p_purchase_date: new Date(purchaseDate).toISOString(),
    p_signed_date: new Date(signedDate).toISOString(),
  })
  if (error) throw error
  if (data && typeof data === 'object' && 'updated' in data && data.updated === true) {
    return { updated: true, status: isActive ? 'active' : 'expired', userId }
  }
  if (data && typeof data === 'object' && 'reason' in data) {
    return { updated: false, reason: String(data.reason) }
  }
  return { updated: false, reason: 'entitlement-not-updated' }
}
