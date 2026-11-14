import { test, expect } from '@playwright/test'
import {
  createAuthSyncScheduler,
  updateProgressWithinAuthScope,
  updateUserMetadataWithCapturedToken,
} from '../../lib/hooks/useAuthSync'

type TimerCallback = () => void

function fakeClock() {
  let nextId = 0
  const callbacks = new Map<number, TimerCallback>()
  const cancelled = new Set<number>()
  return {
    callbacks,
    cancelled,
    setTimeout: ((callback: TimerCallback) => {
      const id = ++nextId
      callbacks.set(id, callback)
      return id
    }) as unknown as typeof globalThis.setTimeout,
    clearTimeout: ((id: number) => {
      cancelled.add(id)
    }) as unknown as typeof globalThis.clearTimeout,
  }
}

test('auth change cancels the pending debounce and stale timer callbacks cannot write', () => {
  const clock = fakeClock()
  const scheduler = createAuthSyncScheduler(clock)
  let current = { userId: 'user-a', generation: 3 }
  let writes = 0
  scheduler.schedule(
    { userId: 'user-a', generation: 3 },
    () => current,
    () => {
      writes += 1
    },
  )
  const timerCallback = [...clock.callbacks.values()][0]
  current = { userId: '', generation: 4 }
  scheduler.cancel()
  timerCallback()
  expect(clock.cancelled.size).toBe(1)
  expect(writes).toBe(0)
})

test('scope is rechecked after getSession refresh before updateUser can run', async () => {
  const expected = { userId: 'user-a', generation: 7 }
  let current = expected
  let releaseSession!: (value: { data: { session: { user: { id: string } } }; error: null }) => void
  let writes = 0
  const pending = updateProgressWithinAuthScope(
    expected,
    () => current,
    () =>
      new Promise((resolve) => {
        releaseSession = resolve
      }),
    async () => {
      writes += 1
      return { data: { user: { id: 'user-a' } }, error: null }
    },
  )
  current = { userId: 'user-a', generation: 8 }
  releaseSession({ data: { session: { user: { id: 'user-a' } } }, error: null })
  expect(await pending).toBeNull()
  expect(writes).toBe(0)
})

test('session identity mismatch after refresh prevents updating the new account', async () => {
  const expected = { userId: 'user-a', generation: 2 }
  let writes = 0
  const result = await updateProgressWithinAuthScope(
    expected,
    () => expected,
    async () => ({ data: { session: { user: { id: 'user-b' } } }, error: null }),
    async () => {
      writes += 1
      return true
    },
  )
  expect(result).toBeNull()
  expect(writes).toBe(0)
})

test('an Auth API request waiting internally remains bound to its captured session token', async () => {
  let currentSession = { accessToken: 'token-a' }
  let releaseInternalWait!: () => void
  let signalInternalWait!: () => void
  const internalWaitStarted = new Promise<void>((resolve) => {
    signalInternalWait = resolve
  })
  let requestUrl = ''
  let requestAuthorization = ''
  let requestApiKey = ''
  let requestBody = ''
  const pending = updateUserMetadataWithCapturedToken(
    'https://auth.example.test',
    'public-anon-key',
    currentSession.accessToken,
    { learning_progress: { version: 3 } },
    async (url, init) => {
      requestUrl = String(url)
      const headers = new Headers(init?.headers)
      requestAuthorization = headers.get('Authorization') || ''
      requestApiKey = headers.get('apikey') || ''
      requestBody = String(init?.body || '')
      await new Promise<void>((resolve) => {
        releaseInternalWait = resolve
        signalInternalWait()
      })
      return new Response(JSON.stringify({ id: 'user-a' }), { status: 200 })
    },
  )
  await internalWaitStarted
  currentSession = { accessToken: 'token-b' }
  releaseInternalWait()
  await pending
  expect(requestUrl).toBe('https://auth.example.test/auth/v1/user')
  expect(requestApiKey).toBe('public-anon-key')
  expect(requestAuthorization).toBe('Bearer token-a')
  expect(JSON.parse(requestBody)).toEqual({ data: { learning_progress: { version: 3 } } })
})

test('current refreshed session permits the matching user update', async () => {
  const expected = { userId: 'user-a', generation: 2 }
  const result = await updateProgressWithinAuthScope(
    expected,
    () => expected,
    async () => ({
      data: { session: { user: { id: 'user-a' }, access_token: 'token-a' } },
      error: null,
    }),
    async (token) => ({ ok: token === 'token-a' }),
  )
  expect(result).toEqual({ ok: true })
})
