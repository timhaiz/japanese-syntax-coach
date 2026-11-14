import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const routeSource = await readFile(
  new URL('../app/api/tts/generate/route.ts', import.meta.url),
  'utf8',
)
const bodySource = await readFile(new URL('../lib/tts/request-body.mjs', import.meta.url), 'utf8')
const limitsSource = await readFile(new URL('../lib/tts/limits.mjs', import.meta.url), 'utf8')
const snapshotSource = await readFile(new URL('../lib/tts/snapshot.mjs', import.meta.url), 'utf8')
const identitySource = await readFile(
  new URL('../lib/tts/request-identity.mjs', import.meta.url),
  'utf8',
)
const key = '550e8400-e29b-41d4-a716-446655440000'
const validTextbook = {
  schemaVersion: 1,
  textbook: {
    id: 'book-1',
    title: 'Book',
    lessons: [
      {
        id: 1,
        title: 'Lesson',
        goal: 'Goal',
        grammar: [
          { pattern: 'p', meaning: 'm', example: 'hello', connection: 'c', explanation: 'e' },
        ],
      },
    ],
    questions: [{ id: 'q1', lessonId: 1, type: '选择', prompt: 'p', answer: 'a', hint: 'h' }],
  },
}

async function invoke({
  body,
  headers = {},
  user = { id: 'user-1' },
  member = true,
  repository,
  authFailure = false,
  repoFailure = false,
  repositoryUnavailable = false,
  engineUnavailable = false,
  engineVersion = 'offline-engine',
} = {}) {
  const calls = { create: [], get: [], auth: 0 }
  const supabase = {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data: member
              ? { membership_status: 'active', membership_ends_at: '2999-01-01T00:00:00Z' }
              : null,
          }),
        }),
      }),
    }),
  }
  const repo = repository ?? {
    async createJob(input) {
      calls.create.push(input)
      if (repoFailure) throw new Error('private backend detail')
      return {
        kind: 'created',
        job: {
          id: 'job-1',
          textbookId: input.textbookId,
          status: 'queued',
          total: input.snapshot.sentences.length,
          completed: 0,
        },
      }
    },
    async getJob(userId, jobId) {
      calls.get.push([userId, jobId])
      if (repoFailure) throw new Error('private backend detail')
      return null
    },
  }
  const context = vm.createContext({
    Request,
    Response,
    Headers,
    TextDecoder,
    Uint8Array,
    Buffer,
    BigInt,
    Object,
    Array,
    Set,
    JSON,
    Number,
    Error,
    process: { env: engineUnavailable ? {} : { VOICEVOX_ENGINE_VERSION: engineVersion } },
    URL,
    console,
  })
  const modules = {
    '@/lib/tts/request-body.mjs': new vm.SourceTextModule(bodySource, { context }),
    '@/lib/tts/limits.mjs': new vm.SourceTextModule(limitsSource, { context }),
    '@/lib/tts/snapshot.mjs': new vm.SourceTextModule(snapshotSource, { context }),
    '@/lib/tts/request-identity.mjs': new vm.SourceTextModule(identitySource, { context }),
  }
  const route = new vm.SourceTextModule(stripTypeScriptTypes(routeSource), { context })
  await route.link(async (specifier) => {
    if (specifier === 'node:crypto') {
      const { createHash } = await import('node:crypto')
      return new vm.SyntheticModule(
        ['createHash'],
        function () {
          this.setExport('createHash', createHash)
        },
        { context },
      )
    }
    if (modules[specifier]) return modules[specifier]
    if (specifier === '@/lib/tts/membership')
      return new vm.SyntheticModule(
        ['isVoiceGenerationMember'],
        function () {
          this.setExport('isVoiceGenerationMember', (_user, profile) => Boolean(profile))
        },
        { context },
      )
    if (specifier === '@/lib/auth/request-supabase')
      return new vm.SyntheticModule(
        ['getAuthenticatedSupabase'],
        function () {
          this.setExport('getAuthenticatedSupabase', async () => {
            calls.auth++
            return authFailure
              ? { response: Response.json({ error: 'unauthenticated' }, { status: 401 }) }
              : { supabase, user }
          })
        },
        { context },
      )
    if (specifier === '@/lib/textbook-import')
      return new vm.SyntheticModule(
        ['validateTextbookPackage'],
        function () {
          this.setExport('validateTextbookPackage', (value) =>
            value?.schemaVersion === 1
              ? { success: true, data: value, errors: [] }
              : { success: false, data: null, errors: ['invalid schema'] },
          )
        },
        { context },
      )
    if (specifier === '@/lib/tts/server')
      return new vm.SyntheticModule(
        ['getTtsRepository'],
        function () {
          this.setExport('getTtsRepository', () => (repositoryUnavailable ? null : repo))
        },
        { context },
      )
    if (specifier === 'next/server')
      return new vm.SyntheticModule(
        ['NextResponse'],
        function () {
          this.setExport('NextResponse', {
            json: (value, options) => Response.json(value, options),
          })
        },
        { context },
      )
    throw new Error(`Unexpected import: ${specifier}`)
  })
  await route.evaluate()
  const request = new Request('https://example.invalid/api/tts/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? JSON.stringify({ textbook: validTextbook }) : body,
  })
  const response = await route.namespace.POST(request)
  return { response, calls, route: route.namespace }
}

test('requires a canonical idempotency key before repository side effects', async () => {
  for (const headers of [{}, { 'Idempotency-Key': 'invalid' }]) {
    const { response, calls } = await invoke({ headers })
    assert.equal(response.status, 428)
    assert.equal((await response.json()).code, 'IDEMPOTENCY_KEY_REQUIRED')
    assert.equal(calls.create.length, 0)
  }
})

test('creates using a repository only after validation, with client-only digest', async () => {
  const { response, calls } = await invoke({ headers: { 'Idempotency-Key': key } })
  assert.equal(response.status, 202, await response.clone().text())
  assert.equal(Object.hasOwn(await response.json(), 'snapshot'), false)
  assert.equal(calls.create.length, 1)
  assert.deepEqual(Array.from(calls.create[0].snapshot.sentences), ['hello'])
  assert.equal(calls.create[0].idempotencyKey, key)
  assert.equal(typeof calls.create[0].requestDigest, 'string')
  assert.equal(Object.hasOwn(calls.create[0], 'engineVersion'), false)
})

test('maps same-key replay, key conflict, and another active job without extra work', async () => {
  for (const [kind, status, code] of [
    ['replayed', 202, undefined],
    ['key_conflict', 409, 'IDEMPOTENCY_KEY_REUSED'],
    ['active_job', 409, 'ACTIVE_TTS_JOB_EXISTS'],
  ]) {
    const repository = {
      createJob: async () => ({ kind, job: { id: 'job-existing' } }),
      getJob: async () => null,
    }
    const { response, calls } = await invoke({ headers: { 'Idempotency-Key': key }, repository })
    assert.equal(response.status, status)
    const payload = await response.json()
    assert.equal(Object.hasOwn(payload, 'snapshot'), false)
    assert.equal(payload.code, code)
    assert.equal(calls.create.length, 0)
  }
})

test('rejects malformed JSON, schema, and snapshot limits without createJob', async () => {
  const oversized = structuredClone(validTextbook)
  oversized.textbook.lessons[0].grammar[0].example = 'x'.repeat(4097)
  for (const body of [
    '{',
    JSON.stringify({ textbook: { schemaVersion: 99 } }),
    JSON.stringify({ textbook: oversized }),
  ]) {
    const { response, calls } = await invoke({ body, headers: { 'Idempotency-Key': key } })
    assert.ok([400, 413].includes(response.status))
    assert.equal(calls.create.length, 0)
  }
})

test('fails closed without a production repository or pinned engine version', async () => {
  const unavailableRepository = await invoke({
    headers: { 'Idempotency-Key': key },
    repositoryUnavailable: true,
  })
  assert.equal(unavailableRepository.response.status, 503)
  assert.equal(unavailableRepository.calls.create.length, 0)

  const configurationUnavailable = await invoke({
    headers: { 'Idempotency-Key': key },
    engineUnavailable: true,
    repository: {
      createJob: async (input) => {
        assert.equal(input.snapshot, null)
        return { kind: 'configuration_unavailable' }
      },
      getJob: async () => null,
    },
  })
  assert.equal(configurationUnavailable.response.status, 503)
  assert.equal(configurationUnavailable.calls.create.length, 0)
  assert.equal((await configurationUnavailable.response.text()).includes('offline-engine'), false)
})

test('replays an existing idempotency key when current engine configuration is unavailable', async () => {
  const repository = {
    createJob: async (input) => {
      assert.equal(input.snapshot, null)
      return {
        kind: 'replayed',
        job: { id: 'job-existing', textbookId: 'book-1', status: 'queued', total: 1, completed: 0 },
      }
    },
    getJob: async () => null,
  }
  const { response } = await invoke({
    headers: { 'Idempotency-Key': key },
    engineUnavailable: true,
    repository,
  })
  assert.equal(response.status, 202)
  assert.equal((await response.json()).job.id, 'job-existing')
})

test('replays an existing key when the current full snapshot would exceed the byte limit', async () => {
  const engineVersion = 'v'.repeat(4 * 1024 * 1024 - 100)
  const digestBody = JSON.stringify({
    schemaVersion: 1,
    speaker: 3,
    engineVersion,
    sentences: ['hello'],
  })
  const persistedSnapshot = JSON.stringify({
    schemaVersion: 1,
    speaker: 3,
    engineVersion,
    sentences: ['hello'],
    sha256: '0'.repeat(64),
    byteLength: Buffer.byteLength(digestBody, 'utf8'),
  })
  assert.ok(Buffer.byteLength(digestBody, 'utf8') <= 4 * 1024 * 1024)
  assert.ok(Buffer.byteLength(persistedSnapshot, 'utf8') > 4 * 1024 * 1024)

  const { response } = await invoke({
    headers: { 'Idempotency-Key': key },
    repository: {
      createJob: async (input) => {
        assert.equal(input.snapshot, null)
        return {
          kind: 'replayed',
          job: {
            id: 'job-existing',
            textbookId: 'book-1',
            status: 'queued',
            total: 1,
            completed: 0,
          },
        }
      },
      getJob: async () => null,
    },
    engineVersion,
  })
  assert.equal(response.status, 202)
  assert.equal((await response.json()).job.id, 'job-existing')
})

test('does not create a new job when the current full snapshot exceeds the byte limit', async () => {
  const { response } = await invoke({
    headers: { 'Idempotency-Key': key },
    repository: {
      createJob: async (input) => {
        assert.equal(input.snapshot, null)
        return { kind: 'configuration_unavailable' }
      },
      getJob: async () => null,
    },
    engineVersion: 'v'.repeat(4 * 1024 * 1024 - 100),
  })
  assert.equal(response.status, 503)
})

test('maps repository failures to opaque retryable 503', async () => {
  const { response } = await invoke({ headers: { 'Idempotency-Key': key }, repoFailure: true })
  const text = await response.text()
  assert.equal(response.status, 503)
  assert.equal(text.includes('private backend detail'), false)
})

test('GET authenticates before user-scoped lookup and masks absent/foreign jobs', async () => {
  const unauthenticated = await invoke({ authFailure: true })
  const denied = await unauthenticated.route.GET(
    new Request('https://example.invalid/api/tts/generate?jobId=job-1'),
  )
  assert.equal(denied.status, 401)
  assert.equal(unauthenticated.calls.get.length, 0)
  const found = await invoke()
  const response = await found.route.GET(
    new Request('https://example.invalid/api/tts/generate?jobId=missing'),
  )
  assert.equal(response.status, 404)
  assert.deepEqual(found.calls.get, [['user-1', 'missing']])
})
