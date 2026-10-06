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
  const allowedProducts = (process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS ?? '')
    .split(',').map((value) => value.trim()).filter(Boolean)
  if (allowedProducts.length > 0 && (!transaction.productId || !allowedProducts.includes(transaction.productId))) {
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
  const { error } = await admin.from('profiles').upsert({
    id: userId,
    membership_status: isActive ? 'active' : 'expired',
    membership_ends_at: expiresAt,
    apple_original_transaction_id: transaction.originalTransactionId ?? null,
    apple_product_id: transaction.productId ?? null,
  }, { onConflict: 'id' })
  if (error) throw error
  return { updated: true, status: isActive ? 'active' : 'expired', userId }
}
