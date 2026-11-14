import {
  GetTransactionHistoryVersion,
  type AppStoreServerAPIClient,
  type JWSTransactionDecodedPayload,
  type SignedDataVerifier,
} from '@apple/app-store-server-library'

// Local resource safeguards, not Apple API limits.
const MAX_PAGES = 100
const MAX_TRANSACTIONS = 2_000
const MAX_SIGNED_TRANSACTION_BYTES = 16 * 1024
const MAX_REVISION_BYTES = 16 * 1024

export class AppleReconciliationReadError extends Error {
  constructor() {
    super('Apple transaction history could not be read completely')
    this.name = 'AppleReconciliationReadError'
  }
}

// Read-only building block. Signature verification does not establish that a
// returned transaction belongs to the intended transaction chain or user.
// Results are not an authorization basis: callers must independently establish
// chain and user ownership and resolve entitlement state before using them.
// transactionId is any identifier accepted by Apple's history endpoint, not
// necessarily an original transaction ID.
export async function readAppleTransactionHistory(
  transactionId: string,
  client: Pick<AppStoreServerAPIClient, 'getTransactionHistory'>,
  verifier: Pick<SignedDataVerifier, 'verifyAndDecodeTransaction'>,
  maxPages = MAX_PAGES,
): Promise<JWSTransactionDecodedPayload[]> {
  if (typeof transactionId !== 'string' || !transactionId.trim() ||
      !Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > MAX_PAGES) {
    throw new AppleReconciliationReadError()
  }

  const transactions: JWSTransactionDecodedPayload[] = []
  const revisions = new Set<string>()
  let revision: string | null = null
  try {
    for (let page = 0; page < maxPages; page++) {
      const response = await client.getTransactionHistory(transactionId, revision, {}, GetTransactionHistoryVersion.V2)
      if (!response || typeof response.hasMore !== 'boolean' || !Array.isArray(response.signedTransactions) ||
          response.signedTransactions.length > MAX_TRANSACTIONS - transactions.length) {
        throw new AppleReconciliationReadError()
      }
      for (const value of response.signedTransactions) {
        if (typeof value !== 'string' || !value || Buffer.byteLength(value, 'utf8') > MAX_SIGNED_TRANSACTION_BYTES) {
          throw new AppleReconciliationReadError()
        }
      }
      for (const signed of response.signedTransactions) {
        transactions.push(await verifier.verifyAndDecodeTransaction(signed))
      }
      if (!response.hasMore) return transactions
      if (typeof response.revision !== 'string' || !response.revision ||
          Buffer.byteLength(response.revision, 'utf8') > MAX_REVISION_BYTES || revisions.has(response.revision)) {
        throw new AppleReconciliationReadError()
      }
      revisions.add(response.revision)
      revision = response.revision
    }
  } catch {
    throw new AppleReconciliationReadError()
  }
  throw new AppleReconciliationReadError()
}
