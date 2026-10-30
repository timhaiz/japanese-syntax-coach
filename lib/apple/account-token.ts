/**
 * Apple returns `appAccountToken` as an opaque string and StoreKit only accepts a
 * UUID, so the client cannot control how the value is serialized. Supabase user
 * ids are lower case, while the same UUID can be rendered in either case.
 *
 * Both sides identify the same account, so the comparison has to ignore case.
 * A case-sensitive comparison would reject a genuine purchase of the signed-in
 * account with a 403 account mismatch and strand the transaction forever.
 *
 * A transaction without a token carries no ownership claim, so it stays
 * compatible with every account and the caller keeps its previous behaviour.
 */
export function accountTokenBelongsToUser(token: string | null | undefined, userId: string): boolean {
  const normalizedToken = token?.trim().toLowerCase()
  if (!normalizedToken) return true
  return normalizedToken === userId.trim().toLowerCase()
}
