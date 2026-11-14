import test from 'node:test'
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
test('lab refuses an existing container without issuing cleanup for a container it did not create', () => {
  const result = spawnSync(process.execPath, ['scripts/ios/mistake-state-lab.mjs'], {
    cwd: root, encoding: 'utf8',
    env: {...process.env, PATH: `${path.join(root, 'tests/fixtures/mistake-lab-docker')}:${process.env.PATH}`},
  })
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /refusing to reuse pre-existing container/)
  assert.ok(!result.stdout.includes('["rm"'), `must not remove the existing container: ${result.stdout}`)
  assert.ok(!result.stdout.includes('["run"'), 'must not start another container')
})
