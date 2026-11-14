// Inject a server-only service-role RPC client; this adapter does not create
// clients, read credentials, authenticate identities, or perform external writes.
export function createAccountWriteFenceStore(client) {
  if (!client || typeof client.rpc !== 'function') throw Error('invalid service client')

  const validateId = (value, label) => {
    if (typeof value !== 'string' || value.length < 1 || value.length > 512) throw Error(`invalid ${label}`)
  }

  const parseEpoch = value => {
    let epoch
    if (typeof value === 'bigint') epoch = value
    else if (typeof value === 'number' && Number.isSafeInteger(value)) epoch = BigInt(value)
    else if (typeof value === 'string' && /^(0|[1-9][0-9]{0,18})$/.test(value)) epoch = BigInt(value)
    else throw Error('invalid epoch')
    if (epoch < 0n || epoch > 9223372036854775807n) throw Error('invalid epoch')
    return epoch
  }

  const rpc = async (name, args) => {
    const response = await client.rpc(name, args)
    if (!response || typeof response !== 'object' || Array.isArray(response) ||
      !Object.hasOwn(response, 'data') || !Object.hasOwn(response, 'error')) {
      throw Error('invalid RPC response')
    }
    if (response.error) throw response.error
    if (response.error !== null) throw Error('invalid RPC response')
    return response.data
  }

  const parseBoolean = data => {
    if (typeof data !== 'boolean') throw Error('invalid fence response')
    return data
  }

  return {
    async beginWrite(identity, writeId) {
      validateId(identity, 'identity')
      validateId(writeId, 'write id')
      const data = await rpc('account_write_fence_begin_write', {
        p_identity: identity,
        p_write_id: writeId,
      })
      try {
        return parseEpoch(data)
      } catch {
        throw Error('invalid epoch response')
      }
    },

    async beginDeletion(identity, deletionId) {
      validateId(identity, 'identity')
      validateId(deletionId, 'deletion id')
      return parseBoolean(await rpc('account_write_fence_begin_deletion', {
        p_identity: identity,
        p_deletion_id: deletionId,
      }))
    },

    async finishWrite(identity, writeId, epoch) {
      validateId(identity, 'identity')
      validateId(writeId, 'write id')
      const parsedEpoch = parseEpoch(epoch)
      return parseBoolean(await rpc('account_write_fence_finish_write', {
        p_identity: identity,
        p_write_id: writeId,
        p_epoch: parsedEpoch.toString(),
      }))
    },
  }
}
