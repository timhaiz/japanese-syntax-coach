import type { TtsCreateInput, TtsCreateResult, TtsPublicJob, TtsRepository } from './contracts.ts'

type StoredJob = {
  userId: string
  idempotencyKey: string
  requestDigest: string
  job: TtsPublicJob
}

const activeStatuses = new Set<TtsPublicJob['status']>([
  'queued',
  'running',
  'retry_wait',
  'publishing',
])

// This adapter is intentionally named and exported for offline contract tests only.
export function createInMemoryTtsRepository(): TtsRepository {
  const jobs = new Map<string, StoredJob>()
  let nextId = 1

  return {
    async createJob(input: TtsCreateInput): Promise<TtsCreateResult> {
      const prior = [...jobs.values()].find(
        (entry) => entry.userId === input.userId && entry.idempotencyKey === input.idempotencyKey,
      )
      if (prior) {
        if (prior.requestDigest !== input.requestDigest) return { kind: 'key_conflict' }
        return { kind: 'replayed', job: { ...prior.job } }
      }

      const hasActiveJob = [...jobs.values()].some(
        (entry) =>
          entry.userId === input.userId &&
          entry.job.textbookId === input.textbookId &&
          activeStatuses.has(entry.job.status),
      )
      if (hasActiveJob) return { kind: 'active_job' }
      if (!input.snapshot) return { kind: 'configuration_unavailable' }

      const job: TtsPublicJob = {
        id: `job-${nextId++}`,
        textbookId: input.textbookId,
        status: 'queued',
        total: input.snapshot.sentences.length,
        completed: 0,
      }
      jobs.set(job.id, {
        userId: input.userId,
        idempotencyKey: input.idempotencyKey,
        requestDigest: input.requestDigest,
        job,
      })
      return { kind: 'created', job: { ...job } }
    },

    async getJob(userId: string, jobId: string): Promise<TtsPublicJob | null> {
      const entry = jobs.get(jobId)
      return entry?.userId === userId ? { ...entry.job } : null
    },
  }
}
