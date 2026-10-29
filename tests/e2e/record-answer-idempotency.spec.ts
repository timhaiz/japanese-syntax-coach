import {test, expect} from '@playwright/test'
import {POST} from '../../app/api/record-answer/route'
import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'

const migrationPath = 'supabase/migrations/202610291400_native_answer_idempotency.sql'

const answerRequest = (overrides: Record<string, unknown> = {}, authorization = 'Bearer test-token') =>
  new Request('http://localhost/api/record-answer', {
    method: 'POST',
    headers: {'content-type': 'application/json', authorization},
    body: JSON.stringify({
      textbookId: 'custom-textbook',
      questionId: 'q-1',
      lessonId: 1,
      answer: '答え',
      correct: true,
      mode: 'new',
      clientRequestId: 'request-1',
      ...overrides,
    }),
  })

test.describe.configure({mode: 'serial'})

test('idempotency: 答题记录 API 声明原生请求幂等契约', () => {
  const source = readFileSync(resolve(process.cwd(), 'app/api/record-answer/route.ts'), 'utf8')
  expect(source).toContain('clientRequestId')
  expect(source).toContain('duplicate')
  expect(source).toContain('record_textbook_learning_attempt_idempotent')
  expect(source).toContain('p_user_id: user.id')
  expect(source).toContain('status: 503')
  expect(source.indexOf('Invalid client request ID')).toBeLessThan(source.indexOf('const authenticated = await getAuthenticatedSupabase'))
})

test('idempotency: keyed unsupported textbook returns 503 without persistence or legacy RPC', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const originalAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const originalFetch = globalThis.fetch
  const requests: string[] = []
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.mock.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key'
  globalThis.fetch = async (input) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    requests.push(url)
    return Response.json({id: 'user-1'}, {status: 200})
  }

  try {
    const response = await POST(answerRequest())
    expect(response.status).toBe(503)
    await expect(response.json()).resolves.toMatchObject({error: expect.stringContaining('unavailable')})
    expect(requests).toHaveLength(1)
    expect(requests[0]).toContain('/auth/v1/user')
    expect(requests.some((url) => url.includes('/rest/v1/rpc/'))).toBe(false)
  } finally {
    globalThis.fetch = originalFetch
    if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl
    if (originalAnonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalAnonKey
  }
})

test('idempotency: missing Supabase config returns 503 before auth/network access', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const originalAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const originalFetch = globalThis.fetch
  let fetchCalls = 0
  delete process.env.NEXT_PUBLIC_SUPABASE_URL
  delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  globalThis.fetch = async () => {
    fetchCalls += 1
    return Response.json({id: 'user-1'})
  }

  try {
    const response = await POST(answerRequest())
    expect(response.status).toBe(503)
    expect(fetchCalls).toBe(0)
  } finally {
    globalThis.fetch = originalFetch
    if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl
    if (originalAnonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalAnonKey
  }
})

test('idempotency: no-key unsupported textbook keeps the legacy local-only response', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const originalAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const originalFetch = globalThis.fetch
  const requests: string[] = []
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.mock.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key'
  globalThis.fetch = async (input) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    requests.push(url)
    return Response.json({id: 'user-1'}, {status: 200})
  }

  try {
    const response = await POST(answerRequest({clientRequestId: undefined}))
    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toMatchObject({localOnly: true, textbookScopeAvailable: false})
    expect(requests).toHaveLength(1)
    expect(requests[0]).toContain('/auth/v1/user')
  } finally {
    globalThis.fetch = originalFetch
    if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl
    if (originalAnonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalAnonKey
  }
})

test('idempotency: invalid credentials remain 401 when persistence is configured', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const originalAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const originalFetch = globalThis.fetch
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.mock.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key'
  globalThis.fetch = async () => Response.json({message: 'invalid token'}, {status: 401})

  try {
    const response = await POST(answerRequest())
    expect(response.status).toBe(401)
  } finally {
    globalThis.fetch = originalFetch
    if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl
    if (originalAnonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalAnonKey
  }
})

test('idempotency: 答题幂等迁移使用用户范围唯一键和持久化响应', () => {
  const migration = readFileSync(resolve(process.cwd(), migrationPath), 'utf8')
  expect(migration).toContain('create table')
  expect(migration).toMatch(/primary key\s*\(user_id, client_request_id\)|unique\s*\(user_id, client_request_id\)/i)
  expect(migration).toMatch(/user_id[\s\S]*client_request_id/)
  expect(migration).toContain('record jsonb')
  expect(migration).toContain('auth.uid()')
  expect(migration).toContain('on conflict')
  expect(migration).toContain('for update')
  expect(migration).toContain('security definer')
  expect(migration).toContain('set search_path = pg_catalog, public')
  expect(migration).toContain('revoke all on table public.answer_request_idempotency from public, anon, authenticated')
  expect(migration).toContain('revoke all on function public.record_textbook_learning_attempt_idempotent(')
  expect(migration).toContain('grant execute on function public.record_textbook_learning_attempt_idempotent(')
  expect(migration).toContain('to authenticated')
  expect(migration).toContain('public.record_textbook_learning_attempt(')
  expect(migration).toContain('p_user_id <> auth.uid()')
})
