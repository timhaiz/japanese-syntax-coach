import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'
const routeSource = readFileSync(new URL('../app/api/account/delete/route.ts', import.meta.url), 'utf8')

function loadRoute(overrides = {}) {
  const calls = []
  const modules = {
    'next/server': {
      NextResponse: {
        json: (body, init = {}) => ({ body, status: init.status ?? 200 }),
      },
    },
    '@supabase/supabase-js': {
      createClient: (...args) => {
        calls.push({ name: 'createClient', args })
        return {
          auth: {
            admin: {
              deleteUser: async (userId) => {
                calls.push({ name: 'deleteUser', args: [userId] })
                return { error: overrides.deleteUserError ?? null }
              },
            },
          },
        }
      },
    },
    '@/lib/auth/request-supabase': {
      getAuthenticatedSupabase: async () => {
        calls.push({ name: 'getAuthenticatedSupabase' })
        if (overrides.unauthenticated) return { response: { status: 401 } }
        return {
          user: { id: overrides.userId ?? 'user-a' },
          supabase: {
            rpc: async (fn, params) => {
              calls.push({ name: 'rpc', args: [fn, params] })
              return { error: overrides.rpcError ?? null }
            },
          },
        }
      },
    },
    '@/lib/tts/server': {
      deleteUserTtsData: async (userId) => {
        calls.push({ name: 'deleteUserTtsData', args: [userId] })
        if (overrides.ttsError) throw overrides.ttsError
      },
    },
  }
  const exports = {}
  const javascript = stripTypeScriptTypes(routeSource)
    .replace(/^import \{ (\w+) \} from '([^']+)'$/gm, 'const { $1 } = require(\'$2\')')
    .replace(/^export const runtime =/m, 'const runtime =')
    .replace(/^export async function POST\(/m, 'exports.POST = async function POST(')
  vm.runInNewContext(javascript, {
    exports,
    require: (name) => {
      if (!Object.hasOwn(modules, name)) throw new Error(`Unexpected import: ${name}`)
      return modules[name]
    },
    process: { env: overrides.env ?? { NEXT_PUBLIC_SUPABASE_URL: 'https://example.supabase.co' } },
  }, { timeout: 1000 })
  return { POST: exports.POST, calls }
}

test('deletion requires explicit DELETE confirmation and authentication, then deletes via RPC or service role', async () => {
  const { POST: postMissingConfirm, calls: missingConfirmCalls } = loadRoute()
  const missingResponse = await postMissingConfirm(missingConfirmRequest({}))
  assert.equal(missingResponse.status, 400)
  assert.equal(missingResponse.body.error, '请确认删除账号后再试。')
  assert.deepEqual(missingConfirmCalls, [])

  const { POST: postUnauth } = loadRoute({ unauthenticated: true })
  const unauthResponse = await postUnauth(missingConfirmRequest({ confirmation: 'DELETE' }))
  assert.equal(unauthResponse.status, 401)

  const { POST: postRpc, calls: rpcCalls } = loadRoute()
  const rpcResponse = await postRpc(missingConfirmRequest({ confirmation: 'DELETE' }))
  assert.equal(rpcResponse.status, 200)
  assert.equal(rpcResponse.body.deleted, true)
  assert.deepEqual(rpcCalls.map((item) => item.name), [
    'getAuthenticatedSupabase',
    'deleteUserTtsData',
    'rpc',
  ])
})

function missingConfirmRequest(payload) {
  return {
    json: async () => payload,
  }
}

// These are future acceptance specifications, not claims about the disabled API.
test.todo('same authenticated identity and operation ID replay one durable result without repeating completed deletion steps')
test.todo('another identity cannot inspect, replay, or claim an operation ID belonging to a different identity')
test.todo('after each partial failure, retry resumes safely without falsely reporting completion or repeating destructive steps')
test.todo('after a lost response or unknown outcome, retry or status lookup reconciles the same operation without assuming failure or success')
