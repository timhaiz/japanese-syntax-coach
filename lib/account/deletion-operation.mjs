// Standalone state core; not wired to an API or a deletion implementation.
// Store contract: get(id) returns a snapshot or null; compareAndSwap(id,
// expectedVersion|null, record) atomically and durably replaces only that version.
// Operation IDs are globally unique keys, not keys scoped to the caller. The
// adapter must preserve acknowledged writes and never reuse versions (no ABA).
// An exception, including a lost write acknowledgement, is always indeterminate.
// Callers must authenticate identities and authorize evidence independently.
export function createDeletionOperations(store, steps) {
  if (!store || typeof store.get !== 'function' || typeof store.compareAndSwap !== 'function') throw Error('invalid store')
  if (!Array.isArray(steps) || !steps.length) throw Error('invalid steps')
  steps = [...steps]
  if (steps.some(s => typeof s !== 'string' || !s) || new Set(steps).size !== steps.length) throw Error('invalid steps')
  const validKey = ({ identity, operationId } = {}) => {
    if (typeof identity !== 'string' || !identity || typeof operationId !== 'string' || !operationId) throw Error('invalid identity or operation ID')
  }
  const status = r => r.pending ? 'unknown' : r.index === steps.length ? 'completed' : 'ready'
  const load = async key => {
    validKey(key)
    const r = await store.get(key.operationId)
    if (r === null) return null
    if (!r || r.operationId !== key.operationId || typeof r.identity !== 'string' || !r.identity || !Number.isSafeInteger(r.version) || r.version < 0 || !Number.isInteger(r.index) || r.index < 0 || r.index > steps.length || !(r.pending === null || (r.index < steps.length && r.pending === steps[r.index])) || !Array.isArray(r.steps) || JSON.stringify(r.steps) !== JSON.stringify(steps)) throw Error('invalid record')
    if (r.identity !== key.identity) throw Error('identity mismatch')
    return r
  }
  const view = r => ({ status: status(r), version: r.version })
  const save = async (key, old, next) => {
    if (!Number.isSafeInteger(next.version)) throw Error('version exhausted')
    const result = await store.compareAndSwap(key.operationId, old?.version ?? null, next)
    if (result === false) throw Error('concurrent modification')
    if (result !== true) throw Error('invalid CAS response')
  }
  return {
    async create(key) {
      const r = await load(key)
      if (r) return view(r)
      const next = { operationId: key.operationId, identity: key.identity, steps: [...steps], index: 0, pending: null, version: 0 }
      await save(key, null, next)
      return view(next)
    },
    async get(key) {
      const r = await load(key)
      return r ? view(r) : null
    },
    async begin(key, step) {
      const r = await load(key)
      if (!r || r.index === steps.length || steps[r.index] !== step) throw Error('invalid step')
      if (r.pending) return { status: 'unknown', acquired: false, version: r.version }
      // A new pending attempt must leave one safe version for its resolution.
      if (r.version >= Number.MAX_SAFE_INTEGER - 1) throw Error('version exhausted')
      await save(key, r, { ...r, pending: step, version: r.version + 1 })
      return { status: 'unknown', acquired: true, version: r.version + 1 }
    },
    async resolve(key, step, evidence, pendingVersion) {
      if (evidence !== 'completed' && evidence !== 'not-applied') throw Error('invalid evidence')
      const r = await load(key)
      if (!r) throw Error('invalid step')
      // Evidence is specific to an attempt; stale evidence cannot resolve a retry.
      if (r.pending !== step || steps[r.index] !== step || r.version !== pendingVersion) throw Error('invalid step or attempt')
      const next = { ...r, pending: null, index: r.index + (evidence === 'completed' ? 1 : 0), version: r.version + 1 }
      await save(key, r, next)
      return view(next)
    },
  }
}
