import type { JWSTransactionDecodedPayload } from '@apple/app-store-server-library'

/** Checks history against a trusted original ID supplied independently by the caller. */
export function isAppleTransactionHistoryOnChain(
  transactions: readonly (Pick<JWSTransactionDecodedPayload, 'originalTransactionId'> | null | undefined)[] | null | undefined,
  trustedOriginalTransactionId: string | null | undefined,
): boolean {
  if (typeof trustedOriginalTransactionId !== 'string' || !trustedOriginalTransactionId ||
      /[\s\p{Cc}]/u.test(trustedOriginalTransactionId) ||
      !Array.isArray(transactions) || transactions.length === 0) {
    return false
  }

  for (let index = 0; index < transactions.length; index++) {
    const transaction = transactions[index]
    if (transaction === null || transaction === undefined ||
        typeof transaction.originalTransactionId !== 'string' ||
        transaction.originalTransactionId !== trustedOriginalTransactionId) {
      return false
    }
  }

  return true
}
