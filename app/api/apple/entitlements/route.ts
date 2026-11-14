import {createPOST} from '@/lib/apple/entitlements-handler'
import {getAuthenticatedSupabase} from '@/lib/auth/request-supabase'
import {accountTokenBelongsToUser} from '@/lib/apple/account-token'
import {updateMembershipFromAppleTransaction, verifyAppleTransaction} from '@/lib/apple/server'
import {isAllowedAppleProduct} from '@/lib/apple/product-policy.mjs'

export const runtime = 'nodejs'
export const POST = createPOST({
  authenticate: (request) => getAuthenticatedSupabase(request),
  verifyTransaction: verifyAppleTransaction,
  accountTokenMatches: accountTokenBelongsToUser,
  productAllowed: (productId) => isAllowedAppleProduct(
    productId,
    process.env.APPLE_SUBSCRIPTION_PRODUCT_IDS ?? '',
  ),
  updateMembership: updateMembershipFromAppleTransaction,
})
