// Supabase service-role RPC adapter for the durable operation state core.
// The caller must supply a server-only service-role client; this module never
// creates clients, reads credentials, authenticates users, or deletes data.
export function createDeletionOperationStore(client) {
  if (!client || typeof client.rpc !== 'function') throw Error('invalid service client')

  const unwrap = response => {
    if (!response || typeof response !== 'object' || Array.isArray(response) ||
        !Object.hasOwn(response, 'data') || !Object.hasOwn(response, 'error')) throw Error('invalid RPC response')
    if (response.error) throw response.error
    if (response.error !== null) throw Error('invalid RPC response')
    return response.data
  }

  return {
    // Server-only primitive: identity must come from independently verified and
    // authorized authentication, never directly from a request parameter.
    // Do not expose this lookup until its caller enforces that boundary.
    async findOperationIdByIdentity(identity) {
      if (typeof identity !== 'string' || !identity) throw Error('invalid identity')
      const id = unwrap(await client.rpc('account_deletion_operation_find_by_identity', { p_identity: identity }))
      if (id === null) return null
      if (typeof id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id)) throw Error('invalid operation response')
      return id
    },

    async get(operationId) {
      const row = unwrap(await client.rpc('account_deletion_operation_get', { p_operation_id: operationId }))
      if (row === null) return null
      if (!row || typeof row !== 'object' || Array.isArray(row) || row.operationId !== operationId) throw Error('invalid operation response')
      return row
    },

    async compareAndSwap(operationId, expectedVersion, record) {
      const data = unwrap(await client.rpc('account_deletion_operation_cas', {
        p_operation_id: operationId,
        p_expected_version: expectedVersion,
        p_record: record,
      }))
      if (typeof data !== 'boolean') throw Error('invalid CAS response')
      return data
    },
  }
}
