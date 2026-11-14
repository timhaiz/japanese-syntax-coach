import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const path = new URL('../supabase/candidates/202611030001_apple_transaction_ownership.sql', import.meta.url)

function assertTransactionGuard(sql) {
  const withoutComments = sql.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, '')
  assert.match(withoutComments, /^\s*begin\s*;\s*do\s+\$\$\s*begin\s+raise\s+exception\s+'Apple ownership migration is intentionally disabled'\s*;\s*end\s*;\s*\$\$\s*;/i)
  // Ignore PL/pgSQL bodies when checking top-level transaction statements.
  const topLevel = withoutComments.replace(/\$\$[\s\S]*?\$\$/g, "''")
  assert.match(topLevel, /\bcommit\s*;\s*$/i)
  const controls = topLevel.match(/(?:^|;)\s*(?:begin|start\s+transaction|commit|end|rollback|abort|savepoint|release|prepare\s+transaction)\b/gi) ?? []
  assert.deepEqual(controls.map((control) => control.replace(/^[;\s]+/, '').toLowerCase()), ['begin', 'commit'])
}

test('candidate guard is the first statement inside one explicit transaction', async () => {
  assertTransactionGuard(await readFile(path, 'utf8'))
})

test('transaction guard rejects conditional guards and intermediate transaction control', () => {
  const guard = "begin; do $$ begin raise exception 'Apple ownership migration is intentionally disabled'; end; $$;"
  assert.throws(() => assertTransactionGuard(`${guard} commit; begin; commit;`), assert.AssertionError)
  assert.throws(() => assertTransactionGuard(`${guard.replace('raise exception', 'if false then raise exception').replace('end; $$', 'end if; end; $$')} commit;`), assert.AssertionError)
})
