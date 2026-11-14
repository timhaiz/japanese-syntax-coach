/**
 * Apple returns `appAccountToken` as an opaque string and StoreKit only accepts a
 * UUID, so the client cannot control how the value is serialized. Supabase user
 * ids are lower case, while the same UUID can be rendered in either case.
 *
 * Both sides identify the same account, so the comparison has to ignore case.
 * A case-sensitive comparison would reject a genuine purchase of the signed-in
 * account with a 403 account mismatch and strand the transaction forever.
 *
 * A missing or invalid token carries no usable ownership claim and must never
 * be assigned to the signed-in account.
 */
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function accountTokenBelongsToUser(token: string | null | undefined, userId: string): boolean {
  const normalizedToken = typeof token === 'string' ? token.trim().toLowerCase() : ''
  return uuidPattern.test(normalizedToken) && normalizedToken === userId.trim().toLowerCase()
}
