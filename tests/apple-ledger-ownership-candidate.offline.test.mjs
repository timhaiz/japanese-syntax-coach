import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const sql = () => readFileSync(new URL('../supabase/candidates/202611030006_apple_ledger_ownership.sql', import.meta.url), 'utf8')
const uncomment = (s) => s.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, '')

test('review-only candidate starts with an unconditional transaction guard', () => {
  const source = uncomment(sql()).trim()
  assert.match(sql(), /NOT READY FOR DEPLOYMENT/i)
  assert.match(source, /^begin\s*;\s*do\s+\$\$\s*begin\s+raise\s+exception\s+'[^']+'\s*;\s*end\s*;\s*\$\$\s*;/i)
  assert.match(source, /commit\s*;\s*$/i)
  assert.doesNotMatch(source.replace(/commit\s*;\s*$/i, ''), /^\s*(?:commit|rollback|savepoint|release|end\s+transaction)\b/im)
})

test('atomic chain claim distinguishes insertion, same owner, and conflict without overwrites', () => {
  const source = uncomment(sql())
  assert.match(source, /insert into public\.apple_ledger_owners\s*\(\s*environment,\s*original_transaction_id,\s*user_id\s*\)\s*values\s*\(\s*p_environment,\s*p_original_transaction_id,\s*p_user_id\s*\)\s*on conflict\s*\(environment,\s*original_transaction_id\)\s*do nothing/i)
  assert.match(source, /if found then\s*return 'inserted';\s*end if;/i)
  assert.match(source, /select\s+user_id\s+into\s+v_owner[\s\S]*?from\s+public\.apple_ledger_owners[\s\S]*?environment\s*=\s*p_environment[\s\S]*?original_transaction_id\s*=\s*p_original_transaction_id[\s\S]*?for update/i)
  assert.match(source, /if not found then\s*raise exception/i)
  assert.match(source, /if v_owner = p_user_id then\s*return 'duplicate';\s*else\s*return 'conflict';\s*end if;/i)
  assert.doesNotMatch(source, /\b(?:update\s+public\.|delete\s+from\s+public\.|do\s+update)\b/i)
})

test('inputs and privileges fail closed; independent caller proof is required', () => {
  const source = sql()
  assert.match(source, /p_environment is null[\s\S]*p_environment not in \('Sandbox', 'Production'\)[\s\S]*p_original_transaction_id is null[\s\S]*p_user_id is null[\s\S]*raise exception/i)
  assert.match(source, /p_original_transaction_id !~|p_original_transaction_id\s*~/i)
  assert.doesNotMatch(uncomment(source), /\bexception\s+when\b/i)
  assert.match(source, /security definer[\s\S]*set search_path\s*=\s*pg_catalog/i)
  assert.match(source, /revoke all on function public\.apple_ledger_claim_owner\(text, text, uuid\) from public, anon, authenticated/i)
  assert.match(source, /grant execute on function public\.apple_ledger_claim_owner\(text, text, uuid\) to service_role/i)
  assert.match(source, /independently verify[\s\S]*signature[\s\S]*authenticate[\s\S]*appAccountToken/i)
  assert.match(source, /not authorization/i)
})
