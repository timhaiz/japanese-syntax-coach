import 'server-only'
import type { TtsCreateInput, TtsCreateResult, TtsPublicJob, TtsRepository } from './contracts.ts'

type RpcClient = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown | null }>
}

type WorkerResult = { category: string; [key: string]: unknown }
type ChunkLeaseInput = { jobId: string; chunkIndex: number; owner: string; leaseSeconds: number }
type FencedChunkInput = ChunkLeaseInput & { epoch: number }
type ChunkCompletionInput = FencedChunkInput & {
  objectKey: string
  sha256: string
  byteLength: number
}
type PublisherLeaseInput = { jobId: string; owner: string; leaseSeconds: number }
type FencedPublisherInput = PublisherLeaseInput & { epoch: number }
type OutboxClaimInput = { owner: string; limit: number; leaseSeconds: number }
type OutboxSentInput = { id: string; dispatchGeneration: number; owner: string; epoch: number }
type ManifestPublicationInput = {
  jobId: string
  userId: string
  textbookId: string
  expectedRevision: number
  publisherOwner: string
  publisherEpoch: number
  manifestKey: string
  sha256: string
  byteLength: number
  descriptors: Array<{
    chunk_index: number
    object_key: string
    sha256: string
    byte_length: number
  }>
}

const unavailable = () => new Error('TTS repository unavailable')
const isRecord = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value)
const hexBytea = (value: string) => `\\x${value}`

function parseJob(value: unknown): TtsPublicJob {
  if (
    !isRecord(value) ||
    typeof value.job_id !== 'string' ||
    typeof value.textbook_id !== 'string' ||
    !['queued', 'running', 'retry_wait', 'publishing', 'succeeded', 'failed'].includes(
      String(value.status),
    ) ||
    !Number.isInteger(value.total) ||
    !Number.isInteger(value.completed) ||
    !(value.error_code === null || typeof value.error_code === 'string')
  )
    throw unavailable()
  return {
    id: value.job_id,
    textbookId: value.textbook_id,
    status: value.status as TtsPublicJob['status'],
    total: value.total as number,
    completed: value.completed as number,
    ...(typeof value.error_code === 'string' ? { errorCode: value.error_code } : {}),
  }
}

export function createSupabaseTtsRepository(client: RpcClient): TtsRepository & {
  claimChunk(input: ChunkLeaseInput): Promise<WorkerResult>
  renewChunkLease(input: FencedChunkInput): Promise<WorkerResult>
  completeChunk(input: ChunkCompletionInput): Promise<WorkerResult>
  claimPublisher(input: PublisherLeaseInput): Promise<WorkerResult>
  renewPublisherLease(input: FencedPublisherInput): Promise<WorkerResult>
  claimOutbox(input: OutboxClaimInput): Promise<WorkerResult>
  markOutboxSent(input: OutboxSentInput): Promise<WorkerResult>
  publishManifest(input: ManifestPublicationInput): Promise<WorkerResult>
} {
  if (!client || typeof client.rpc !== 'function') throw new Error('Invalid TTS RPC client')

  const rpc = async (name: string, args: Record<string, unknown>): Promise<unknown> => {
    try {
      const response = await client.rpc(name, args)
      if (!isRecord(response) || response.error !== null) throw unavailable()
      return response.data
    } catch {
      throw unavailable()
    }
  }

  const workerRpc = async (name: string, args: Record<string, unknown>): Promise<WorkerResult> => {
    const data = await rpc(name, args)
    if (!isRecord(data) || typeof data.category !== 'string') throw unavailable()
    return data as WorkerResult
  }

  return {
    async createJob(input: TtsCreateInput): Promise<TtsCreateResult> {
      const snapshot = input.snapshot
      const data = await rpc('tts_create_job', {
        p_user_id: input.userId,
        p_textbook_id: input.textbookId,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: hexBytea(input.requestDigest),
        p_schema_version: snapshot?.schemaVersion ?? 1,
        p_speaker: snapshot?.speaker ?? 0,
        p_engine_version: snapshot?.engineVersion ?? 'unavailable',
        p_sentences: snapshot?.sentences ?? [],
        p_snapshot_sha256: hexBytea(snapshot?.sha256 ?? '0'.repeat(64)),
        p_snapshot_byte_length: snapshot?.byteLength ?? 0,
        p_total: snapshot?.sentences.length ?? 0,
        p_configuration_available: snapshot !== null,
      })
      if (!isRecord(data) || typeof data.category !== 'string') throw unavailable()
      if (data.category === 'key_conflict') return { kind: 'key_conflict' }
      if (data.category === 'active_job') return { kind: 'active_job' }
      if (data.category === 'unavailable') return { kind: 'configuration_unavailable' }
      if (data.category !== 'created' && data.category !== 'replayed') throw unavailable()
      const job = parseJob(data)
      return { kind: data.category, job }
    },

    async getJob(userId: string, jobId: string): Promise<TtsPublicJob | null> {
      const data = await rpc('tts_get_job_for_user', { p_user_id: userId, p_job_id: jobId })
      if (data === null) return null
      return parseJob(data)
    },

    claimChunk: ({ jobId, chunkIndex, owner, leaseSeconds }) =>
      workerRpc('tts_claim_chunk', {
        p_job_id: jobId,
        p_chunk_index: chunkIndex,
        p_owner: owner,
        p_lease_seconds: leaseSeconds,
      }),
    renewChunkLease: ({ jobId, chunkIndex, owner, epoch, leaseSeconds }) =>
      workerRpc('tts_renew_chunk_lease', {
        p_job_id: jobId,
        p_chunk_index: chunkIndex,
        p_owner: owner,
        p_epoch: epoch,
        p_lease_seconds: leaseSeconds,
      }),
    completeChunk: ({ jobId, chunkIndex, owner, epoch, objectKey, sha256, byteLength }) =>
      workerRpc('tts_complete_chunk', {
        p_job_id: jobId,
        p_chunk_index: chunkIndex,
        p_owner: owner,
        p_epoch: epoch,
        p_object_key: objectKey,
        p_object_sha256: hexBytea(sha256),
        p_object_byte_length: byteLength,
      }),
    claimPublisher: ({ jobId, owner, leaseSeconds }) =>
      workerRpc('tts_claim_publisher', {
        p_job_id: jobId,
        p_owner: owner,
        p_lease_seconds: leaseSeconds,
      }),
    renewPublisherLease: ({ jobId, owner, epoch, leaseSeconds }) =>
      workerRpc('tts_renew_publisher_lease', {
        p_job_id: jobId,
        p_owner: owner,
        p_epoch: epoch,
        p_lease_seconds: leaseSeconds,
      }),
    claimOutbox: ({ owner, limit, leaseSeconds }) =>
      workerRpc('tts_claim_outbox', {
        p_owner: owner,
        p_limit: limit,
        p_lease_seconds: leaseSeconds,
      }),
    markOutboxSent: ({ id, dispatchGeneration, owner, epoch }) =>
      workerRpc('tts_mark_outbox_sent', {
        p_id: id,
        p_dispatch_generation: dispatchGeneration,
        p_owner: owner,
        p_epoch: epoch,
      }),
    publishManifest: ({
      jobId,
      userId,
      textbookId,
      expectedRevision,
      publisherOwner,
      publisherEpoch,
      manifestKey,
      sha256,
      byteLength,
      descriptors,
    }) =>
      workerRpc('tts_publish_manifest', {
        p_job_id: jobId,
        p_user_id: userId,
        p_textbook_id: textbookId,
        p_expected_revision: expectedRevision,
        p_publisher_owner: publisherOwner,
        p_publisher_epoch: publisherEpoch,
        p_manifest_key: manifestKey,
        p_manifest_sha256: hexBytea(sha256),
        p_manifest_byte_length: byteLength,
        p_descriptors: descriptors,
      }),
  }
}
