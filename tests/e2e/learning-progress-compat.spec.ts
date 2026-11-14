import {test, expect} from '@playwright/test'
import {GET} from '../../app/api/study-state/route'
import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'

type LegacyProgress = {
  version: number
  lessonDone: Record<string, number>
  lessonCorrect: Record<string, number>
  completedLessons: number[]
  mistakes: Array<{id: string}>
  updatedAt: string
}

const legacy: LegacyProgress = {
  version: 3,
  lessonDone: {'0': 7},
  lessonCorrect: {'0': 5},
  completedLessons: [],
  mistakes: [{id: 'L01-Q002'}],
  updatedAt: '2026-10-29T08:00:00.000Z',
}

const request = () => new Request('http://localhost/api/study-state?textbookId=builtin-japanese-syntax', {
  headers: {authorization: 'Bearer test-token'},
})

const mockSupabase = async (userMetadata: Record<string, unknown>, calls: Array<{method: string; url: string}>) => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const originalAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const originalFetch = globalThis.fetch
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://supabase.mock.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key'
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    calls.push({method: init?.method ?? 'GET', url})
    if (url.includes('/auth/v1/user')) {
      return Response.json({id: 'user-1', user_metadata: userMetadata}, {status: 200})
    }
    if (url.includes('/rest/v1/')) return Response.json([], {status: 200})
    return Response.json({}, {status: 200})
  }
  return () => {
    globalThis.fetch = originalFetch
    if (originalUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl
    if (originalAnonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalAnonKey
  }
}

test.describe('study-state legacy learning progress compatibility', () => {
  test('only legacy metadata returns structured empty shape and separate normalized legacy snapshot', async () => {
    const calls: Array<{method: string; url: string}> = []
    const restore = await mockSupabase({learning_progress: legacy}, calls)
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body).toMatchObject({
        textbookId: 'builtin-japanese-syntax',
        dueQuestionIds: [],
        lessons: [],
        knowledgePoints: [],
        metrics: {
          totalAttempts: 0,
          incorrectAttempts: 0,
          errorRate: 0,
          forgettingRate: 0,
          correctStreak: 0,
          topErrorTags: [],
        },
        legacyProgressAvailable: true,
        legacyProgress: legacy,
      })
      expect(body.metrics).not.toHaveProperty('legacyProgress')
      expect(calls.some((call) => call.method !== 'GET' || call.url.includes('/auth/v1/user/'))).toBe(false)
    } finally {
      restore()
    }
  })

  test('structured rows and legacy metadata remain separate without summing or overwriting', async () => {
    const calls: Array<{method: string; url: string}> = []
    const restore = await mockSupabase({learning_progress: legacy}, calls)
    const originalFetch = globalThis.fetch
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
      calls.push({method: init?.method ?? 'GET', url})
      if (url.includes('/auth/v1/user')) {
        return Response.json({id: 'user-1', user_metadata: {learning_progress: legacy}}, {status: 200})
      }
      if (url.includes('/rest/v1/lesson_progress')) {
        return Response.json([{lesson_id: 1, answered_count: 3, correct_count: 2, completed_at: null}], {status: 200})
      }
      if (url.includes('/rest/v1/answer_attempts')) {
        return Response.json([{exercise_id: 'L01-Q001', verdict: 'incorrect', error_tags: [], created_at: '2026-10-29T09:00:00.000Z'}], {status: 200})
      }
      if (url.includes('/rest/v1/')) return Response.json([], {status: 200})
      return Response.json({}, {status: 200})
    }
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body.lessons).toEqual([{lesson_id: 1, answered_count: 3, correct_count: 2, completed_at: null}])
      expect(body.metrics.totalAttempts).toBe(1)
      expect(body.legacyProgress).toMatchObject({...legacy, mistakes: [{id: 'L01-Q002'}]})
      expect(body.legacyProgress.mistakes[0].prompt).toBe('我不是老师。')
      expect(body.legacyProgress.lessonDone['0']).toBe(7)
      expect(body.legacyProgress).not.toHaveProperty('totalAttempts')
      expect(calls.some((call) => call.method !== 'GET')).toBe(false)
    } finally {
      globalThis.fetch = originalFetch
      restore()
    }
  })

  test('historical version 2 remains supported and normalized', async () => {
    const calls: Array<{method: string; url: string}> = []
    const versionTwo = {...legacy, version: 2}
    const restore = await mockSupabase({learning_progress: versionTwo}, calls)
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body.legacyProgressAvailable).toBe(true)
      expect(body.legacyProgress.version).toBe(2)
      expect(body.legacyProgress.mistakes[0]).toMatchObject({id: 'L01-Q002', prompt: '我不是老师。'})
    } finally {
      restore()
    }
  })

  test('malformed supported version is preserved and marked unsupported', async () => {
    const calls: Array<{method: string; url: string}> = []
    const malformed = {...legacy, completedLessons: null}
    const restore = await mockSupabase({learning_progress: malformed}, calls)
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body.legacyProgressAvailable).toBe(true)
      expect(body.legacyProgress).toEqual({status: 'unsupported', version: 3, raw: malformed})
    } finally {
      restore()
    }
  })

  test('unsupported version is preserved and marked instead of normalized or hidden', async () => {
    const calls: Array<{method: string; url: string}> = []
    const unsupported = {...legacy, version: 999}
    const restore = await mockSupabase({learning_progress: unsupported}, calls)
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body.legacyProgressAvailable).toBe(true)
      expect(body.legacyProgress).toEqual({status: 'unsupported', version: 999, raw: unsupported})
      expect(calls.some((call) => call.method !== 'GET')).toBe(false)
    } finally {
      restore()
    }
  })

  test('structured query errors still return legacy compatibility fields', async () => {
    const calls: Array<{method: string; url: string}> = []
    const restore = await mockSupabase({learning_progress: legacy}, calls)
    const originalFetch = globalThis.fetch
    globalThis.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
      calls.push({method: init?.method ?? 'GET', url})
      if (url.includes('/auth/v1/user')) return Response.json({id: 'user-1', user_metadata: {learning_progress: legacy}})
      if (url.includes('/rest/v1/lesson_progress')) {
        return Response.json({message: 'structured query failed', code: 'XX000'}, {status: 500})
      }
      if (url.includes('/rest/v1/')) return Response.json([], {status: 200})
      return Response.json({}, {status: 200})
    }
    try {
      const response = await GET(request())
      expect(response.status).toBe(500)
      expect(await response.json()).toMatchObject({
        error: 'Unable to load study state',
        legacyProgressAvailable: true,
        legacyProgress: {version: 3, lessonDone: {'0': 7}},
      })
      expect(calls.some((call) => call.method !== 'GET')).toBe(false)
    } finally {
      globalThis.fetch = originalFetch
      restore()
    }
  })

  test('scope-migration 503 response source retains both legacy fields', () => {
    const source = readFileSync(resolve(process.cwd(), 'app/api/study-state/route.ts'), 'utf8')
    expect(source).toMatch(/return NextResponse\.json\(\s*\{\s*error: 'Textbook-scoped cloud sync requires the latest database migration\.',\s*\.\.\.legacyResponse\s*\},\s*\{\s*status: 503\s*\},\s*\)/)
  })

  test('without legacy metadata returns false and preserves the structured empty shape', async () => {
    const calls: Array<{method: string; url: string}> = []
    const restore = await mockSupabase({}, calls)
    try {
      const response = await GET(request())
      expect(response.status).toBe(200)
      const body = await response.json()
      expect(body).toMatchObject({
        dueQuestionIds: [],
        lessons: [],
        knowledgePoints: [],
        metrics: {
          totalAttempts: 0,
          incorrectAttempts: 0,
          errorRate: 0,
          forgettingRate: 0,
          correctStreak: 0,
          topErrorTags: [],
        },
        legacyProgressAvailable: false,
        legacyProgress: null,
      })
      expect(calls.some((call) => call.method !== 'GET')).toBe(false)
    } finally {
      restore()
    }
  })
})
