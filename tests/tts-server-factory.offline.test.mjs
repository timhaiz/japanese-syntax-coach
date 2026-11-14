import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const serverSource = await readFile(new URL('../lib/tts/server.ts', import.meta.url), 'utf8')

async function loadFactory(env) {
  const context = vm.createContext({ process: { env }, Promise })
  const calls = []
  const client = { rpc() {} }
  const modules = {
    'server-only': new vm.SyntheticModule([], function () {}, { context }),
    'node:fs/promises': new vm.SyntheticModule(
      ['readFile', 'rm'],
      function () {
        this.setExport('readFile', async () => '')
        this.setExport('rm', async () => {})
      },
      { context },
    ),
    'node:path': new vm.SyntheticModule(
      ['default'],
      function () {
        this.setExport('default', {
          resolve: (...parts) => parts.join('/'),
          join: (...parts) => parts.join('/'),
        })
      },
      { context },
    ),
    '@supabase/supabase-js': new vm.SyntheticModule(
      ['createClient'],
      function () {
        this.setExport('createClient', (...args) => {
          calls.push({ kind: 'client', args })
          return client
        })
      },
      { context },
    ),
    './supabase-repository': new vm.SyntheticModule(
      ['createSupabaseTtsRepository'],
      function () {
        this.setExport('createSupabaseTtsRepository', (receivedClient) => {
          calls.push({ kind: 'repository', client: receivedClient })
          return { client: receivedClient }
        })
      },
      { context },
    ),
  }
  const server = new vm.SourceTextModule(stripTypeScriptTypes(serverSource), { context })
  await server.link(async (specifier) => {
    if (modules[specifier]) return modules[specifier]
    throw new Error(`Unexpected import: ${specifier}`)
  })
  await server.evaluate()
  return { factory: server.namespace.getTtsRepository, calls, client }
}

test('fails closed when server-side Supabase credentials are missing', async () => {
  for (const env of [
    {},
    { NEXT_PUBLIC_SUPABASE_URL: 'https://project.supabase.co' },
    { SUPABASE_SERVICE_ROLE_KEY: 'server-secret' },
  ]) {
    const { factory, calls } = await loadFactory(env)
    assert.equal(factory(), null)
    assert.deepEqual(calls, [])
  }
})

test('creates the TTS repository with a non-persistent service-role client', async () => {
  const { factory, calls, client } = await loadFactory({
    NEXT_PUBLIC_SUPABASE_URL: 'https://project.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'server-secret',
  })

  assert.deepEqual(factory(), { client })
  assert.equal(calls[0].kind, 'client')
  assert.equal(calls[0].args[0], 'https://project.supabase.co')
  assert.equal(calls[0].args[1], 'server-secret')
  assert.equal(
    JSON.stringify(calls[0].args[2]),
    JSON.stringify({ auth: { autoRefreshToken: false, persistSession: false } }),
  )
  assert.equal(calls[1].kind, 'repository')
  assert.equal(calls[1].client, client)
})
