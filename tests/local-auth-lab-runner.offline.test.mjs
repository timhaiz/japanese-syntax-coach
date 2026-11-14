import test from 'node:test'
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, writeFileSync} from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
test('auth lab refuses existing project resources without starting or cleaning them', () => {
  const fixture = mkdtempSync(path.join(root, 'build/auth-runner-fixture-'))
  writeFileSync(path.join(fixture, 'docker'), `#!/bin/bash\ncase " $* " in\n  *" ps -a -q "*) echo existing-auth-container; exit 0;;\n  *) echo MUTATION_ATTEMPT >&2; exit 90;;\nesac\n`, {mode: 0o755})
  writeFileSync(path.join(fixture, 'lsof'), '#!/bin/bash\nexit 1\n', {mode: 0o755})
  const result = spawnSync(process.execPath, ['scripts/ios/local-auth-lab.mjs'], {
    cwd: root, encoding: 'utf8', env: {...process.env, PATH: `${fixture}:${process.env.PATH}`},
  })
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /refusing to reuse existing Auth lab resources/)
  assert.doesNotMatch(result.stderr, /MUTATION_ATTEMPT/)
})
