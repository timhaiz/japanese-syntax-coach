import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const routeSource = await readFile(new URL('../app/api/membership/route.ts', import.meta.url), 'utf8')
const membershipSource = await readFile(new URL('../lib/tts/membership.ts', import.meta.url), 'utf8')

async function getResponse({ user = { id: 'user-1' }, profile = null, error = null } = {}) {
  const supabase = {
    auth: { getUser: async () => ({ data: { user } }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: profile, error }) }) }) }),
  }
  const context = vm.createContext({ Request, Response, process: { env: {} } })
  const membership = new vm.SourceTextModule(stripTypeScriptTypes(membershipSource), { context })
  const route = new vm.SourceTextModule(stripTypeScriptTypes(routeSource), { context })
  await route.link(async (specifier) => {
    if (specifier === '@/lib/tts/membership') return membership
    if (specifier === 'next/server') return new vm.SyntheticModule(['NextResponse'], function () {
      this.setExport('NextResponse', { json: (value, options) => Response.json(value, options) })
    }, { context })
    if (specifier === '@/lib/supabase-server') return new vm.SyntheticModule(['getSupabaseServer'], function () {
      this.setExport('getSupabaseServer', async () => supabase)
    }, { context })
    throw new Error(`Unexpected import: ${specifier}`)
  })
  await route.evaluate()
  return route.namespace.GET(new Request('https://example.invalid/api/membership'))
}

test('profile lookup failure does not report a free membership', async () => {
  const response = await getResponse({ error: { message: 'private database detail' } })
  assert.equal(response.status, 503)
  assert.equal((await response.text()).includes('private database detail'), false)
})

test('independent trusted entitlement remains usable when profile lookup fails', async () => {
  const response = await getResponse({ user: { id: 'user-1', app_metadata: { voice_generation: true } }, error: { message: 'database unavailable' } })
  assert.equal(response.status, 200)
  const body = await response.json()
  assert.equal(body.status, 'member')
  assert.equal(body.isMember, true)
  assert.equal(body.endsAt, null)
})

test('successful lookup still reports free or member from profile', async () => {
  const free = await getResponse()
  assert.equal((await free.json()).status, 'free')
  const member = await getResponse({ profile: { membership_status: 'active', membership_ends_at: '2999-01-01T00:00:00Z' } })
  assert.equal((await member.json()).status, 'member')
})
