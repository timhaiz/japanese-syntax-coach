import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const server = await readFile(new URL('../lib/apple/server.ts', import.meta.url), 'utf8')
const migration = await readFile(new URL('../supabase/migrations/202611030001_apple_transaction_ownership.sql', import.meta.url), 'utf8')
const candidate = await readFile(new URL('../supabase/candidates/202611030001_apple_transaction_ownership.sql', import.meta.url), 'utf8')

test('candidate ownership RPC is not connected to the active server or migration paths', () => {
  assert.match(server, /client\.rpc\('apply_apple_entitlement'/)
  assert.doesNotMatch(server, /client\.rpc\('apply_apple_transaction'/)
  assert.doesNotMatch(server, /from\('profiles'\)\.upsert/)
  assert.match(candidate, /public\.apply_apple_transaction/)
  assert.doesNotMatch(migration, /apply_apple_transaction/)
})

test('candidate ownership source documents unique ownership and conflict handling', () => {
  assert.match(candidate, /original_transaction_id text primary key/)
  assert.match(candidate, /security definer/)
  assert.match(candidate, /insert into public\.apple_transaction_ownership/)
  assert.match(candidate, /on conflict \(original_transaction_id\) do nothing/)
  assert.match(candidate, /raise exception 'Apple ownership conflict'/)
  assert.match(candidate, /update public\.profiles/)
})

test('migration contains only its unconditional abort; candidate revocation logic is archived separately', () => {
  assert.match(migration, /raise exception 'Apple ownership migration is intentionally disabled'/)
  assert.doesNotMatch(migration, /^\s*(?:create table|alter table|create or replace function|revoke|grant)\b/im)
  assert.match(candidate, /revoked/)
  assert.match(candidate, /p_is_active and not v_owner\.revoked/)
})
