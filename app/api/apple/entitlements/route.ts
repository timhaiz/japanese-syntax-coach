import {createPOST} from '@/lib/apple/entitlements-handler'
import {getAuthenticatedSupabase} from '@/lib/auth/request-supabase'
import {accountTokenBelongsToUser} from '@/lib/apple/account-token'
import {updateMembershipFromAppleTransaction, verifyAppleTransaction} from '@/lib/apple/server'

export const runtime = 'nodejs'
export const POST = createPOST({
  authenticate: (request) => getAuthenticatedSupabase(request),
  verifyTransaction: verifyAppleTransaction,
  accountTokenMatches: accountTokenBelongsToUser,
  updateMembership: updateMembershipFromAppleTransaction,
})
