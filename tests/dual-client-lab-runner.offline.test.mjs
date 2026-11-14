import test from 'node:test'
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, writeFileSync} from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

test('dual-client runner refuses pre-existing isolated containers without mutating them', () => {
  const fixture = mkdtempSync(path.join(root, 'build/dual-lab-fixture-'))
  writeFileSync(path.join(fixture, 'docker'), `#!/bin/bash\ncase " $* " in\n  *" ps -a -q "*) echo occupied-container; exit 0;;\n  *) echo MUTATION_ATTEMPT >&2; exit 91;;\nesac\n`, {mode: 0o755})
  writeFileSync(path.join(fixture, 'lsof'), '#!/bin/bash\nexit 1\n', {mode: 0o755})
  const result = spawnSync(process.execPath, ['scripts/ios/dual-client-lab.mjs', '--backend'], {
    cwd: root, encoding: 'utf8', env: {...process.env, PATH: `${fixture}:${process.env.PATH}`},
  })
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /refusing to reuse pre-existing isolated lab containers/)
  assert.doesNotMatch(result.stderr, /MUTATION_ATTEMPT/)
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /@example\.invalid|LOCAL_DUAL_PASSWORD|eyJ[A-Za-z0-9_-]+\./)
})

test('dual-client runner refuses a pre-existing isolated volume without starting or removing it', () => {
  const fixture = mkdtempSync(path.join(root, 'build/dual-lab-fixture-'))
  writeFileSync(path.join(fixture, 'docker'), `#!/bin/bash\ncase " $* " in\n  *" ps -a -q "*) exit 0;;\n  *" volume ls "*) echo occupied-volume; exit 0;;\n  *) echo MUTATION_ATTEMPT >&2; exit 91;;\nesac\n`, {mode: 0o755})
  const result = spawnSync(process.execPath, ['scripts/ios/dual-client-lab.mjs', '--backend'], {
    cwd: root, encoding: 'utf8', env: {...process.env, PATH: `${fixture}:${process.env.PATH}`},
  })
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /refusing to reuse pre-existing isolated lab volumes/)
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /MUTATION_ATTEMPT|@example\.invalid|eyJ[A-Za-z0-9_-]+\./)
})

test('dual-client runner accepts one supported mode only', () => {
  const result = spawnSync(process.execPath, ['scripts/ios/dual-client-lab.mjs', '--web', '--ios'], {cwd:root, encoding:'utf8'})
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /choose exactly one/)
})
