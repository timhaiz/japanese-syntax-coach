// Review-only adapter: the caller must independently authenticate the user,
// verify the Apple signature and prove appAccountToken matches that user.
// This function establishes none of those facts and grants no entitlement.
// The corresponding SQL candidate is disabled and must not be deployed yet.
export async function claimAppleLedgerOwner(client, environment, originalTransactionId, userId) {
  if (!client || typeof client.rpc !== 'function') throw Error('invalid service client')
  if (!['Sandbox', 'Production'].includes(environment) ||
      typeof originalTransactionId !== 'string' || !originalTransactionId || /[\s\p{Cc}]/u.test(originalTransactionId) ||
      typeof userId !== 'string' || !userId) throw Error('invalid ownership identity')

  const response = await client.rpc('apple_ledger_claim_owner', {
    p_environment: environment,
    p_original_transaction_id: originalTransactionId,
    p_user_id: userId,
  })
  if (!response || typeof response !== 'object' || Array.isArray(response) ||
      !Object.hasOwn(response, 'data') || !Object.hasOwn(response, 'error')) throw Error('invalid RPC response')
  if (response.error) throw response.error
  if (response.error !== null || !['inserted', 'duplicate', 'conflict'].includes(response.data)) {
    throw Error('invalid RPC response')
  }
  return response.data
}
