import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const path = new URL('../supabase/candidates/202611030003_apple_ledger_foundation.sql', import.meta.url)

function assertUnconditionalDisableGuard(sql) {
  const withoutComments = sql.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, '')
  assert.match(
    withoutComments,
    /^\s*begin\s*;\s*do\s+\$\$\s*begin\s+raise\s+exception\s+'Apple ledger foundation is intentionally disabled'\s*;\s*end\s*;\s*\$\$\s*;/i,
    'the transaction must begin with an unconditional disable guard',
  )
}

test('disable guard rejects conditional raises', () => {
  const conditionalGuard = `begin;\ndo $$\nbegin\n  if false then\n    raise exception 'Apple ledger foundation is intentionally disabled';\n  end if;\nend;\n$$;`
  assert.throws(() => assertUnconditionalDisableGuard(conditionalGuard), assert.AssertionError)
})

test('isolated candidate is unconditionally disabled and does not write profiles', async () => {
  const sql = await readFile(path, 'utf8')
  assert.match(sql, /^\s*--[^\n]*NOT READY FOR DEPLOYMENT/m)
  assertUnconditionalDisableGuard(sql)
  assert.doesNotMatch(sql, /(?:update|insert into|delete from)\s+public\.profiles/i)
})

test('ownership, notification identity and per-transaction facts have distinct keys', async () => {
  const sql = await readFile(path, 'utf8')
  assert.match(sql, /primary key \(environment, original_transaction_id\)/i)
  assert.match(sql, /primary key \(environment, notification_uuid\)/i)
  assert.match(sql, /primary key \(environment, transaction_id\)/i)
  assert.match(sql, /foreign key \(environment, original_transaction_id\)/i)
  assert.match(sql, /revoked_at timestamptz/i)
  assert.match(sql, /reconciliation_required boolean not null default true/i)
})

test('verified notifications retain bounded reprocessing identity without requiring an owner', async () => {
  const sql = await readFile(path, 'utf8')
  const notification = sql.match(/create table public\.apple_ledger_notifications\s*\(([\s\S]*?)\n\);/i)?.[1]
  assert.ok(notification)
  assert.match(notification, /notification_type text not null/i)
  assert.match(notification, /signed_at timestamptz not null/i)
  assert.match(notification, /identity_scope text not null/i)
  assert.match(notification, /original_transaction_id text/i)
  assert.match(notification, /transaction_id text/i)
  assert.match(notification, /identity_scope = 'transaction'[\s\S]*original_transaction_id is not null[\s\S]*transaction_id is not null/i)
  assert.match(notification, /identity_scope = 'other'[\s\S]*original_transaction_id is null[\s\S]*transaction_id is null/i)
  assert.match(notification, /retain_until timestamptz not null/i)
  assert.match(notification, /retain_until > received_at/i)
  assert.match(notification, /retain_until <= received_at \+ interval '90 days'/i)
  assert.doesNotMatch(notification, /references\s+public\.apple_ledger_owners/i)
  assert.doesNotMatch(notification, /\b(?:raw_payload|signed_payload|signed_transaction|signed_renewal_info)\b/i)
  assert.match(sql, /create index[\s\S]*on public\.apple_ledger_notifications\s*\(environment, original_transaction_id\)/i)
})

test('ledger identifiers reject whitespace and control characters without changing nullable columns', async () => {
  const sql = await readFile(path, 'utf8')
  const identifiers = [
    'original_transaction_id',
    'notification_uuid',
    'notification_type',
    'transaction_id',
    'product_id',
  ]

  for (const identifier of identifiers) {
    const declaration = sql.split(/\r?\n/).find((line) => line.includes(`${identifier} text`))
    assert.ok(declaration, `${identifier} declaration must exist`)
    assert.match(
      declaration,
      new RegExp(`${identifier} !~ '\\[\\[:space:\\]\\[:cntrl:\\]\\]'`, 'i'),
      `${identifier} must reject whitespace and control characters`,
    )
  }

  for (const identifier of ['original_transaction_id', 'transaction_id']) {
    const nullableDeclaration = sql.split(/\r?\n/).find((line) =>
      line.trimStart().startsWith(`${identifier} text check`),
    )
    assert.ok(nullableDeclaration, `${identifier} remains nullable`)
    assert.doesNotMatch(nullableDeclaration, /\bnot null\b/i)
    assert.match(nullableDeclaration, new RegExp(`${identifier} !~`, 'i'))
  }
})

test('ledger tables are private by default and have no executable client interface', async () => {
  const sql = await readFile(path, 'utf8')
  for (const table of ['apple_ledger_owners', 'apple_ledger_notifications', 'apple_ledger_transactions']) {
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, 'i'))
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated`, 'i'))
  }
  assert.doesNotMatch(sql, /grant\s+(?:execute|insert|update|delete|all)\b/i)
  assert.doesNotMatch(sql, /create\s+(?:or replace\s+)?function/i)
})
