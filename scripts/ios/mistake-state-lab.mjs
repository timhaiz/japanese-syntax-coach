import { execFile, execFileSync } from 'node:child_process'
import { promisify } from 'node:util'
const exec = promisify(execFile)
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const name = 'jsc-mistake-lab-20261106'
const image = 'postgres:16-alpine'
const run = (args) => execFileSync('docker', args, { stdio: 'inherit' })
const output = (args) => execFileSync('docker', args, { encoding: 'utf8' }).trim()

let created = false
try {
  try {
    output(['inspect', name])
    throw new Error(`refusing to reuse pre-existing container ${name}`)
  } catch (error) {
    if (error.message.includes('refusing to reuse')) throw error
  }
  run(['run', '-d', '--name', name, '-e', 'POSTGRES_PASSWORD=lab-only', '-e', 'POSTGRES_DB=lab', image])
  created = true
  let ready = false
  for (let i = 0; i < 40; i++) {
    try { run(['exec', name, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'lab']); ready = true; break } catch { await delay(500) }
  }
  if (!ready) throw new Error('isolated PostgreSQL container did not become ready')
  run(['cp', path.join(root, 'supabase/candidates/202611060001_atomic_mistake_state.sql'), `${name}:/tmp/mistake-state-candidate.sql`])
  run(['cp', path.join(root, 'tests/mistake-state.postgres.lab.sql'), `${name}:/tmp/mistake-state-lab.sql`])
  run(['exec', name, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'lab', '-f', '/tmp/mistake-state-lab.sql'])
  const concurrentCall = "set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001'; select public.record_textbook_answer_with_mistakes_v1('op-concurrent','builtin-japanese-syntax','q-concurrent',0,false,'new',1,'bad');"
  const psqlArgs = ['exec', name, 'psql', '-At', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'lab', '-c', concurrentCall]
  const both = await Promise.all([exec('docker', psqlArgs), exec('docker', psqlArgs)])
  if (both.some(({ stdout }) => !stdout.includes('"duplicate"'))) throw new Error('concurrent operation did not return a result')
  const duplicateCount = both.reduce((n, { stdout }) => n + (stdout.includes('"duplicate": true') ? 1 : 0), 0)
  if (duplicateCount !== 1) throw new Error(`expected one concurrent replay, got ${duplicateCount}`)
  const count = output(['exec', name, 'psql', '-At', '-U', 'postgres', '-d', 'lab', '-c', "select count(*) from public.answer_attempts where exercise_id='q-concurrent'"])
  if (count !== '1') throw new Error(`concurrent replay recorded ${count} answers`)

  const casCall = (op) => `set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001'; select public.record_textbook_answer_with_mistakes_v1('${op}','builtin-japanese-syntax','q-cas-race',0,false,'new',1,'bad');`
  const casArgs = (op) => ['exec', name, 'psql', '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-U', 'postgres', '-d', 'lab', '-c', casCall(op)]
  const cas = await Promise.allSettled([exec('docker', casArgs('op-cas-a')), exec('docker', casArgs('op-cas-b'))])
  const winners = cas.filter((result) => result.status === 'fulfilled')
  const losers = cas.filter((result) => result.status === 'rejected')
  if (winners.length !== 1 || losers.length !== 1) throw new Error(`expected one CAS winner and one loser; got ${winners.length}/${losers.length}`)
  const loserError = String(losers[0].reason.stderr ?? losers[0].reason.message)
  if (!loserError.includes('40001')) throw new Error(`CAS loser did not return SQLSTATE 40001: ${loserError}`)
  const casAudit = output(['exec', name, 'psql', '-At', '-F', ',', '-U', 'postgres', '-d', 'lab', '-c', "select (select count(*) from public.answer_attempts where exercise_id='q-cas-race'),(select count(*) from public.mistake_state_operations where operation_id in ('op-cas-a','op-cas-b')),(select version from public.mistake_state where question_id='q-cas-race')"])
  if (casAudit !== '1,1,1') throw new Error(`CAS loser left database state behind: ${casAudit}`)
  console.log(`PASS: isolated PostgreSQL lab, concurrent replay and competing CAS completed in ${name}`)
} finally {
  if (created) {
    try { run(['rm', '-f', name]) } catch (error) { console.error(`Cleanup failed for owned container ${name}: ${error.message}`) }
  }
}
