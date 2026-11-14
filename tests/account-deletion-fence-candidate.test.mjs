import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const sql = () => readFileSync(new URL('../supabase/candidates/202611030004_account_deletion_write_fence.sql', import.meta.url), 'utf8')
const body = (name) => sql().split(`create function public.${name}(`)[1]?.split('$$;')[0] ?? ''

test('candidate aborts its transaction unconditionally before any DDL', () => {
  const source = sql().replace(/^\s*--.*$/gm, '').trim()
  // Require the entire guard body, not merely a RAISE hidden inside IF FALSE.
  assert.match(source, /^begin\s*;\s*do\s+\$\$\s*begin\s+raise\s+exception\s+'[^']+'\s*;\s*end\s*;\s*\$\$\s*;/i)
  assert.match(source, /commit\s*;\s*$/i)
  assert.doesNotMatch(source.replace(/commit\s*;\s*$/i, ''), /^\s*(?:commit|rollback|savepoint|release|end\s+transaction)\b/im)
})

test('candidate is review-only, durable, and does not expire outstanding writes', () => {
  const source = sql()
  assert.match(source, /do not apply/i)
  assert.match(source, /cannot stop.*external/i)
  assert.match(source, /create table public\.account_write_fence_identities/i)
  assert.match(source, /create table public\.account_write_fence_writes/i)
  assert.match(source, /primary key \(identity, write_id\)/i)
  assert.doesNotMatch(source, /expires_at|lease_expiry|delete from public\.account_write_fence_writes/i)
})

test('write admission and deletion serialize on the same identity row', () => {
  const write = body('account_write_fence_begin_write')
  const deletion = body('account_write_fence_begin_deletion')
  for (const part of [write, deletion]) {
    assert.match(part, /insert into public\.account_write_fence_identities/i)
    assert.match(part, /for update/i)
  }
  assert.match(write, /deletion_id is not null/i)
  assert.match(write, /insert into public\.account_write_fence_writes/i)
  assert.match(deletion, /epoch = epoch \+ 1/i)
  assert.match(deletion, /deletion_id is distinct from p_deletion_id/i)
  assert.match(deletion, /not exists[\s\S]*finished = false/i)
})

test('begin-write returns the epoch as decimal text for lossless JSON transport', () => {
  const write = body('account_write_fence_begin_write')
  assert.match(sql(), /create function public\.account_write_fence_begin_write\([^)]*\)\s*returns text/i)
  assert.match(write, /return v_row\.epoch::text\s*;/i)
  assert.doesNotMatch(sql(), /create function public\.account_write_fence_begin_write\([^)]*\)\s*returns bigint/i)
})

test('completion is bound to identity, unique write ID and original epoch', () => {
  const finish = body('account_write_fence_finish_write')
  assert.match(finish, /identity = p_identity/i)
  assert.match(finish, /write_id = p_write_id/i)
  assert.match(finish, /epoch = p_epoch/i)
  assert.match(finish, /finished = true/i)
  assert.match(finish, /for update/i)
})

test('tables and RPCs are inaccessible to ordinary roles', () => {
  const source = sql()
  assert.match(source, /revoke all on table public\.account_write_fence_identities, public\.account_write_fence_writes from public, anon, authenticated/i)
  for (const signature of ['account_write_fence_begin_write(text, text)', 'account_write_fence_begin_deletion(text, text)', 'account_write_fence_finish_write(text, text, bigint)']) {
    assert.ok(source.includes(`revoke all on function public.${signature} from public, anon, authenticated;`))
    assert.ok(source.includes(`grant execute on function public.${signature} to service_role;`))
  }
})
