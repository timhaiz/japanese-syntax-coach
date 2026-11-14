// Review-only policy primitive; not wired to entitlement writes. A match does
// not establish signature validity, transaction ownership, or membership.
export function isAllowedAppleProduct(productId, configuredIds) {
  if (typeof configuredIds !== 'string' || !configuredIds) throw Error('invalid product configuration')
  const ids = configuredIds.split(',')
  if (ids.some(id => !id || /[\s\p{Cc}]/u.test(id)) || new Set(ids).size !== ids.length) {
    throw Error('invalid product configuration')
  }
  return typeof productId === 'string' && ids.includes(productId)
}
