import { createHash } from 'node:crypto'
import { NextResponse } from 'next/server'
import { getAuthenticatedSupabase } from '@/lib/auth/request-supabase'
import { isVoiceGenerationMember } from '@/lib/tts/membership'
import { getTtsRepository } from '@/lib/tts/server'
import { TTS_INPUT_LIMITS } from '@/lib/tts/limits.mjs'
import { readBoundedJsonRequest } from '@/lib/tts/request-body.mjs'
import { buildTtsSnapshot } from '@/lib/tts/snapshot.mjs'
import { digestTtsRequest, parseIdempotencyKey } from '@/lib/tts/request-identity.mjs'
import type { TtsCreateInput, TtsExecutionSnapshot } from '@/lib/tts/contracts'
import { validateTextbookPackage } from '@/lib/textbook-import'

export const runtime = 'nodejs'

const unavailable = () =>
  NextResponse.json(
    { error: '语音服务暂时不可用，请稍后重试。' },
    { status: 503, headers: { 'Retry-After': '5' } },
  )

export async function POST(request: Request) {
  const authenticated = await getAuthenticatedSupabase(request)
  if ('response' in authenticated)
    return NextResponse.json({ error: '请先登录后使用教材语音生成功能。' }, { status: 401 })
  const { supabase, user } = authenticated

  const { data: profile } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()
  if (!isVoiceGenerationMember(user, profile)) {
    return NextResponse.json({ error: '教材语音生成功能仅对会员开放。' }, { status: 403 })
  }

  const key = parseIdempotencyKey(request.headers.get('Idempotency-Key'))
  if (!key.ok) {
    return NextResponse.json(
      { error: '需要有效的 Idempotency-Key。', code: 'IDEMPOTENCY_KEY_REQUIRED' },
      { status: 428 },
    )
  }

  const bodyResult = await readBoundedJsonRequest(request, TTS_INPUT_LIMITS.maxRequestBytes)
  if (!bodyResult.ok) {
    const status = bodyResult.kind === 'too_large' ? 413 : 400
    return NextResponse.json(
      { error: status === 413 ? '请求内容超过允许的大小。' : '请求不是有效的 JSON。' },
      { status },
    )
  }
  const body = bodyResult.value as { textbook?: unknown; generationParameters?: unknown } | null
  const result = validateTextbookPackage(
    body && typeof body === 'object' ? body.textbook : undefined,
  )
  if (!result.success) return NextResponse.json({ error: result.errors.join(' ') }, { status: 400 })

  let prepared: ReturnType<typeof buildTtsSnapshot>
  try {
    prepared = buildTtsSnapshot({
      textbook: result.data.textbook,
      speaker: Number(process.env.VOICEVOX_SPEAKER || 3),
      limits: TTS_INPUT_LIMITS,
    })
  } catch (error) {
    const resourceLimit =
      error instanceof Error && 'kind' in error && error.kind === 'resource_limit'
    return NextResponse.json(
      { error: resourceLimit ? '教材语音输入超过允许的资源限制。' : '教材语音输入无效。' },
      { status: resourceLimit ? 413 : 400 },
    )
  }

  const repository = getTtsRepository()
  if (!repository) return unavailable()

  const engineVersion = process.env.VOICEVOX_ENGINE_VERSION?.trim()
  let snapshot: TtsExecutionSnapshot | null = null
  if (engineVersion) {
    const snapshotBody = JSON.stringify({
      schemaVersion: 1,
      speaker: prepared.speaker,
      engineVersion,
      sentences: prepared.sentences,
    })
    const byteLength = Buffer.byteLength(snapshotBody, 'utf8')
    if (byteLength <= TTS_INPUT_LIMITS.maxSnapshotBytes) {
      const candidate: TtsExecutionSnapshot = {
        schemaVersion: 1,
        speaker: prepared.speaker,
        engineVersion,
        sentences: prepared.sentences,
        sha256: createHash('sha256').update(snapshotBody).digest('hex'),
        byteLength,
      }
      if (
        Buffer.byteLength(JSON.stringify(candidate), 'utf8') <= TTS_INPUT_LIMITS.maxSnapshotBytes
      ) {
        snapshot = candidate
      }
    }
  }
  const input: TtsCreateInput = {
    userId: user.id,
    textbookId: result.data.textbook.id,
    idempotencyKey: key.value,
    requestDigest: digestTtsRequest({
      textbookId: result.data.textbook.id,
      schemaVersion: result.data.schemaVersion,
      sentences: prepared.sentences,
      generationParameters:
        body && typeof body === 'object' ? (body.generationParameters ?? null) : null,
    }),
    snapshot,
  }

  try {
    const outcome = await repository.createJob(input)
    if (outcome.kind === 'key_conflict') {
      return NextResponse.json(
        { error: '此 Idempotency-Key 已用于不同的请求。', code: 'IDEMPOTENCY_KEY_REUSED' },
        { status: 409 },
      )
    }
    if (outcome.kind === 'active_job') {
      return NextResponse.json(
        { error: '已有进行中的教材语音任务。', code: 'ACTIVE_TTS_JOB_EXISTS' },
        { status: 409 },
      )
    }
    if (outcome.kind === 'configuration_unavailable') return unavailable()
    return NextResponse.json({ job: outcome.job }, { status: 202 })
  } catch {
    return unavailable()
  }
}

export async function GET(request: Request) {
  const authenticated = await getAuthenticatedSupabase(request)
  if ('response' in authenticated) return authenticated.response
  const { user } = authenticated
  const jobId = new URL(request.url).searchParams.get('jobId') || ''
  const repository = getTtsRepository()
  if (!repository) return unavailable()
  try {
    const job = await repository.getJob(user.id, jobId)
    if (!job) return NextResponse.json({ error: '任务不存在或服务器已重启。' }, { status: 404 })
    return NextResponse.json({ job })
  } catch {
    return unavailable()
  }
}
