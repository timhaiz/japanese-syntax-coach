import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const path = new URL('../supabase/candidates/202611050001_tts_durable_tasks.sql', import.meta.url)
const sql = await readFile(path, 'utf8')
const rpcNames = [
  'tts_create_job',
  'tts_get_job_for_user',
  'tts_claim_chunk',
  'tts_renew_chunk_lease',
  'tts_complete_chunk',
  'tts_claim_publisher',
  'tts_renew_publisher_lease',
  'tts_claim_outbox',
  'tts_mark_outbox_sent',
  'tts_publish_manifest',
]

function functionDefinition(name) {
  return (
    sql.match(
      new RegExp(
        `create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\b[\\s\\S]*?as\\s+\\$function\\$[\\s\\S]*?\\$function\\$`,
        'i',
      ),
    )?.[0] ?? ''
  )
}

test('every RPC fixes search_path and validates arguments', () => {
  for (const name of rpcNames) {
    const definition = functionDefinition(name)
    assert.ok(definition, `${name} must be defined`)
    assert.match(
      definition,
      /set\s+search_path\s*=\s*pg_catalog\s*,\s*public/i,
      `${name} must fix search_path`,
    )
    assert.match(
      definition,
      /if\s+[^;]*(?:is\s+null|btrim|length\(|<\s*0|<=\s*0)[^;]*then/i,
      `${name} must explicitly validate arguments`,
    )
    assert.match(
      sql,
      new RegExp(
        `revoke\\s+all\\s+on\\s+function\\s+public\\.${name}\\s*\\([^;]*?\\)\\s+from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated`,
        'i',
      ),
    )
    assert.match(
      sql,
      new RegExp(
        `grant\\s+execute\\s+on\\s+function\\s+public\\.${name}\\s*\\([^;]*?\\)\\s+to\\s+service_role`,
        'i',
      ),
    )
  }
})

test('create and replay return persisted public job fields', () => {
  const createSql = functionDefinition('tts_create_job')
  assert.match(
    createSql,
    /'category',\s*'replayed'[\s\S]*?'job_id',\s*v_job\.id[\s\S]*?'textbook_id',\s*v_job\.textbook_id[\s\S]*?'status',\s*v_job\.status[\s\S]*?'total',\s*v_job\.total[\s\S]*?'completed',\s*v_job\.completed/i,
  )
  assert.match(
    createSql,
    /'category',\s*'created'[\s\S]*?'job_id',\s*v_job\.id[\s\S]*?'textbook_id',\s*v_job\.textbook_id[\s\S]*?'status',\s*v_job\.status[\s\S]*?'total',\s*v_job\.total[\s\S]*?'completed',\s*v_job\.completed/i,
  )
})

test('user-scoped read RPC filters both identifiers and returns null for no row', () => {
  const readSql = functionDefinition('tts_get_job_for_user')
  assert.match(readSql, /p_user_id\s+uuid,\s*p_job_id\s+uuid/i)
  assert.match(readSql, /where\s+j\.user_id\s*=\s*p_user_id\s+and\s+j\.id\s*=\s*p_job_id/i)
  assert.match(readSql, /if\s+not\s+found\s+then\s+return\s+null/i)
  assert.match(
    readSql,
    /'job_id'[\s\S]*?'textbook_id'[\s\S]*?'status'[\s\S]*?'total'[\s\S]*?'completed'/i,
  )
})

test('browser roles have no direct TTS table writes and no browser-facing write policy', () => {
  assert.match(
    sql,
    /alter\s+table\s+public\.tts_textbook_guards\s+enable\s+row\s+level\s+security/i,
  )
  assert.match(
    sql,
    /revoke\s+all\s+on\s+table\s+public\.tts_textbook_guards[\s\S]*?public\.tts_manifest_heads\s+from\s+public,\s*anon,\s*authenticated/i,
  )
  assert.doesNotMatch(
    sql,
    /create\s+policy[\s\S]*?to\s+(?:public|anon|authenticated)[\s\S]*?for\s+(?:insert|update|delete|all)/i,
  )
  assert.doesNotMatch(sql, /on\s+delete\s+cascade/i)
})

test('jobs store a paired publisher lease and a monotonic epoch', () => {
  const jobs = sql.match(/create table public\.tts_jobs\s*\([\s\S]*?\n\);/i)?.[0] ?? ''
  assert.match(jobs, /publisher_lease_owner\s+text/i)
  assert.match(
    jobs,
    /publisher_fencing_epoch\s+bigint\s+not\s+null\s+default\s+0\s+check\s*\(publisher_fencing_epoch\s*>=\s*0\)/i,
  )
  assert.match(jobs, /publisher_lease_expires_at\s+timestamptz/i)
  assert.match(
    jobs,
    /check\s*\(\s*\(publisher_lease_owner\s+is\s+null\)\s*=\s*\(publisher_lease_expires_at\s+is\s+null\)\s*\)/i,
  )
})

function model() {
  return { jobs: [], counters: new Map(), chunks: new Map(), head: new Map(), nextId: 1 }
}

function create(state, input) {
  const idem = state.jobs.find((job) => job.user === input.user && job.key === input.key)
  if (idem)
    return idem.digest === input.digest
      ? { category: 'replayed', job: idem }
      : { category: 'key_conflict' }

  if (!input.available) return { category: 'unavailable' }
  if (state.jobs.some((job) => job.user === input.user && job.book === input.book && job.active)) {
    return { category: 'active_job' }
  }
  const counterKey = `${input.user}:${input.book}`
  const generation = (state.counters.get(counterKey) ?? 0) + 1
  state.counters.set(counterKey, generation)
  const job = {
    id: state.nextId++,
    user: input.user,
    book: input.book,
    key: input.key,
    digest: input.digest,
    snapshot: input.snapshot,
    generation,
    active: true,
  }
  state.jobs.push(job)
  state.chunks.set(job.id, { epoch: 1, owner: 'worker', expires: 10, status: 'running' })
  return { category: 'created', job }
}

test('publisher claim and renewal enforce complete work and live lease fencing', () => {
  const claimSql = functionDefinition('tts_claim_publisher')
  assert.match(claimSql, /v_job\.status\s+not\s+in\s*\('queued',\s*'running',\s*'publishing'\)/i)
  assert.match(claimSql, /v_chunk_count\s*<>\s*v_job\.total/i)
  assert.match(claimSql, /status\s*<>\s*'succeeded'/i)
  assert.match(
    claimSql,
    /publisher_lease_owner\s+is\s+not\s+null[\s\S]*?publisher_lease_expires_at\s*>\s*v_now/i,
  )
  assert.match(claimSql, /publisher_fencing_epoch\s*=\s*publisher_fencing_epoch\s*\+\s*1/i)
  assert.match(claimSql, /'category',\s*'publisher_busy'/i)

  const renewSql = functionDefinition('tts_renew_publisher_lease')
  assert.match(renewSql, /status\s*=\s*'publishing'/i)
  assert.match(renewSql, /publisher_lease_owner\s*=\s*p_owner/i)
  assert.match(renewSql, /publisher_fencing_epoch\s*=\s*p_epoch/i)
  assert.match(renewSql, /publisher_lease_expires_at\s*>\s*clock_timestamp\s*\(\s*\)/i)
  assert.match(renewSql, /'category',\s*'stale_publisher'/i)
})

test('transaction model replays same key and snapshot, rejects a different digest before availability', () => {
  const state = model()
  const request = {
    user: 'u1',
    book: 'b1',
    key: 'k1',
    digest: 'd1',
    snapshot: 'frozen-v1',
    available: true,
  }
  const first = create(state, request)
  const replay = create(state, { ...request, snapshot: 'changed', available: false })
  const conflict = create(state, { ...request, digest: 'd2', available: false })
  assert.equal(first.category, 'created')
  assert.equal(replay.category, 'replayed')
  assert.equal(replay.job.id, first.job.id)
  assert.equal(replay.job.snapshot, 'frozen-v1')
  assert.equal(conflict.category, 'key_conflict')
  assert.equal(state.jobs.length, 1)
})

test('same user/key serializes across textbooks and resolves replay or digest conflict', () => {
  const state = model()
  const first = create(state, {
    user: 'u1',
    book: 'b1',
    key: 'shared',
    digest: 'd1',
    snapshot: 'frozen',
    available: true,
  })
  const crossBookReplay = create(state, {
    user: 'u1',
    book: 'b2',
    key: 'shared',
    digest: 'd1',
    snapshot: 'new',
    available: true,
  })
  const crossBookConflict = create(state, {
    user: 'u1',
    book: 'b3',
    key: 'shared',
    digest: 'd2',
    snapshot: 'new',
    available: false,
  })
  assert.equal(first.category, 'created')
  assert.equal(crossBookReplay.category, 'replayed')
  assert.equal(crossBookReplay.job.id, first.job.id)
  assert.equal(crossBookConflict.category, 'key_conflict')
  assert.equal(state.jobs.length, 1)

  const createSql = functionDefinition('tts_create_job')
  assert.match(
    createSql,
    /pg_advisory_xact_lock\s*\(\s*hashtextextended\s*\(\s*p_user_id::text\s*\|\|\s*':'\s*\|\|\s*p_idempotency_key/i,
  )
  assert.ok(
    createSql.indexOf('pg_advisory_xact_lock') <
      createSql.indexOf('insert into public.tts_textbook_guards'),
  )
})

test('manifest descriptors exactly and safely match every successful chunk', () => {
  const chunks = [
    { chunk_index: 0, object_key: 'a', sha256: 'a'.repeat(64), byte_length: 1 },
    { chunk_index: 1, object_key: 'b', sha256: 'b'.repeat(64), byte_length: 2 },
  ]
  const valid = (descriptors) => {
    if (!Array.isArray(descriptors) || descriptors.length !== chunks.length) return false
    const indices = new Set()
    for (const item of descriptors) {
      if (
        !item ||
        typeof item !== 'object' ||
        Array.isArray(item) ||
        Object.keys(item).length !== 4 ||
        !Number.isInteger(item.chunk_index) ||
        item.chunk_index < 0 ||
        typeof item.object_key !== 'string' ||
        item.object_key.trim() === '' ||
        typeof item.sha256 !== 'string' ||
        !/^[0-9a-f]{64}$/i.test(item.sha256) ||
        !Number.isSafeInteger(item.byte_length) ||
        item.byte_length < 0 ||
        indices.has(item.chunk_index)
      )
        return false
      indices.add(item.chunk_index)
      if (!chunks.some((chunk) => Object.keys(chunk).every((key) => chunk[key] === item[key])))
        return false
    }
    return indices.size === chunks.length && chunks.every((chunk) => indices.has(chunk.chunk_index))
  }
  assert.equal(valid(chunks), true)
  assert.equal(valid([chunks[0], chunks[0]]), false)
  assert.equal(valid([chunks[0]]), false)
  assert.equal(valid([...chunks, { ...chunks[0], chunk_index: 2 }]), false)
  assert.equal(valid([{ ...chunks[0], chunk_index: '0' }, chunks[1]]), false)
  assert.equal(valid([{ ...chunks[0], byte_length: '1' }, chunks[1]]), false)
  assert.equal(valid([{ ...chunks[0], unexpected: true }, chunks[1]]), false)

  const publishSql = functionDefinition('tts_publish_manifest')
  assert.match(publishSql, /jsonb_typeof\s*\(\s*d\s*\)\s+is\s+distinct\s+from\s+'object'/i)
  assert.match(publishSql, /jsonb_object_length\s*\(\s*d\s*\)\s*<>\s*4/i)
  assert.match(publishSql, /count\s*\(\s*distinct\s+\(?\s*d\s*->>\s*'chunk_index'/i)
  assert.match(
    publishSql,
    /not\s+exists\s*\(\s*select\s+1\s+from\s+jsonb_array_elements\(p_descriptors\)/i,
  )
})

test('publication requires the current unexpired publisher lease as well as revision CAS', () => {
  const publishSql = functionDefinition('tts_publish_manifest')
  assert.match(publishSql, /p_publisher_owner\s+text/i)
  assert.match(publishSql, /p_publisher_epoch\s+bigint/i)
  assert.match(publishSql, /status\s*<>?\s*'publishing'/i)
  assert.match(publishSql, /publisher_lease_owner\s+is\s+distinct\s+from\s+p_publisher_owner/i)
  assert.match(publishSql, /publisher_fencing_epoch\s*<>\s*p_publisher_epoch/i)
  assert.match(publishSql, /publisher_lease_expires_at\s*<=\s*clock_timestamp\s*\(\s*\)/i)
  assert.match(publishSql, /v_current\s*<>\s*p_expected_revision/i)
  assert.match(publishSql, /'category',\s*'stale_publisher'/i)
  assert.ok(
    publishSql.indexOf("'category', 'stale_publisher'") <
      publishSql.indexOf('insert into public.tts_manifest_heads'),
  )
})

test('publisher lease model fences owner, epoch, expiry, and revision without mutating on rejection', () => {
  const lease = {
    owner: 'publisher-a',
    epoch: 7,
    expiresAt: 100,
    revision: 3,
    head: { job: 'previous', revision: 3 },
  }
  const publish = ({ owner, epoch, now, expectedRevision }) => {
    if (lease.owner !== owner || lease.epoch !== epoch || lease.expiresAt <= now)
      return 'stale_publisher'
    if (lease.revision !== expectedRevision) return 'cas_conflict'
    lease.head = { job: 'current', revision: lease.revision + 1 }
    lease.owner = null
    lease.expiresAt = null
    return 'published'
  }
  const originalHead = { ...lease.head }
  assert.equal(
    publish({ owner: 'publisher-b', epoch: 7, now: 50, expectedRevision: 3 }),
    'stale_publisher',
  )
  assert.equal(
    publish({ owner: 'publisher-a', epoch: 6, now: 50, expectedRevision: 3 }),
    'stale_publisher',
  )
  assert.equal(
    publish({ owner: 'publisher-a', epoch: 7, now: 100, expectedRevision: 3 }),
    'stale_publisher',
  )
  assert.equal(
    publish({ owner: 'publisher-a', epoch: 7, now: 50, expectedRevision: 2 }),
    'cas_conflict',
  )
  assert.deepEqual(lease.head, originalHead)
  assert.equal(
    publish({ owner: 'publisher-a', epoch: 7, now: 50, expectedRevision: 3 }),
    'published',
  )
  assert.deepEqual(lease.head, { job: 'current', revision: 4 })
  assert.equal(lease.owner, null)
  assert.equal(lease.epoch, 7)
})

test('transaction model serializes active creates and allocates the next generation after terminal completion', () => {
  const state = model()
  const input = { user: 'u1', book: 'b1', digest: 'd', snapshot: 's', available: true }
  const first = create(state, { ...input, key: 'k1' })
  const concurrent = create(state, { ...input, key: 'k2' })
  assert.equal(first.category, 'created')
  assert.equal(concurrent.category, 'active_job')
  first.job.active = false
  const next = create(state, { ...input, key: 'k3' })
  assert.equal(next.category, 'created')
  assert.equal(next.job.generation, first.job.generation + 1)
})

test('transaction model rejects stale chunk epochs and manifest head CAS conflicts without state changes', () => {
  const state = model()
  const created = create(state, {
    user: 'u1',
    book: 'b1',
    key: 'k1',
    digest: 'd1',
    snapshot: 's',
    available: true,
  })
  const chunk = state.chunks.get(created.job.id)
  const oldEpochResult =
    chunk.epoch === 0 ? ((chunk.status = 'succeeded'), 'accepted') : 'stale_epoch'
  assert.equal(oldEpochResult, 'stale_epoch')
  assert.equal(chunk.status, 'running')

  const manifestKey = 'u1:b1'
  state.head.set(manifestKey, { revision: 4, job: 'prior' })
  const expectedRevision = 3
  const before = state.head.get(manifestKey)
  const casResult =
    before.revision === expectedRevision
      ? (state.head.set(manifestKey, { revision: 5, job: created.job.id }), 'published')
      : 'cas_conflict'
  assert.equal(casResult, 'cas_conflict')
  assert.deepEqual(state.head.get(manifestKey), before)
})
