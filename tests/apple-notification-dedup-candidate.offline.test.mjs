import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const sql = () => readFileSync(new URL('../supabase/candidates/202611030005_apple_notification_dedup.sql', import.meta.url), 'utf8')
const uncomment = (s) => s.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, '')

test('candidate is disabled unconditionally inside one explicit transaction', () => {
  const source = uncomment(sql()).trim()
  assert.match(sql(), /NOT READY FOR DEPLOYMENT/i)
  assert.match(source, /^begin\s*;\s*do\s+\$\$\s*begin\s+raise\s+exception\s+'[^']+'\s*;\s*end\s*;\s*\$\$\s*;/i)
  assert.match(source, /commit\s*;\s*$/i)
  assert.doesNotMatch(source.replace(/commit\s*;\s*$/i, ''), /^\s*(?:commit|rollback|savepoint|release|end\s+transaction)\b/im)
})

test('insertion uses the environment and UUID unique key without modifying existing rows', () => {
  const source = uncomment(sql())
  assert.match(source, /insert into public\.apple_ledger_notifications\s*\([\s\S]*?\)\s*values\s*\([\s\S]*?\)\s*on conflict\s*\(environment,\s*notification_uuid\)\s*do nothing/i)
  assert.match(source, /if found then\s*return 'inserted';\s*end if;/i)
  assert.match(source, /select\s+payload_sha256[\s\S]*?from\s+public\.apple_ledger_notifications[\s\S]*?environment\s*=\s*p_environment[\s\S]*?notification_uuid\s*=\s*p_notification_uuid[\s\S]*?for update/i)
  assert.match(source, /if not found then\s*raise exception/i)
  assert.match(source, /if v_digest = p_payload_sha256 then\s*return 'duplicate';\s*else\s*return 'conflict';\s*end if;/i)
  assert.doesNotMatch(source, /\b(?:update\s+public\.|delete\s+from\s+public\.|do\s+update)\b/i)
})

test('fail closed, private function and caller responsibilities are explicit', () => {
  const source = sql()
  assert.match(source, /p_payload_sha256 is null[\s\S]*octet_length\(p_payload_sha256\)\s*<>\s*32[\s\S]*raise exception/i)
  assert.doesNotMatch(uncomment(source), /\bexception\s+when\b/i)
  assert.match(source, /security definer[\s\S]*set search_path\s*=\s*pg_catalog/i)
  assert.match(source, /revoke all on function public\.apple_notification_dedup\(text, text, text, timestamptz, text, text, text, bytea, timestamptz\) from public, anon, authenticated/i)
  assert.match(source, /grant execute on function public\.apple_notification_dedup\(text, text, text, timestamptz, text, text, text, bytea, timestamptz\) to service_role/i)
  assert.match(source, /signature verification and authorization.*caller/i)
  assert.match(source, /duplicate.*does not mean[\s\S]*?processed/i)
})
