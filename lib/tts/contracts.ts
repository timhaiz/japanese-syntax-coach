export type TtsCreateInput = {
  userId: string
  textbookId: string
  idempotencyKey: string
  requestDigest: string
  snapshot: TtsExecutionSnapshot | null
}

export type TtsExecutionSnapshot = {
  schemaVersion: 1
  speaker: number
  engineVersion: string
  sentences: string[]
  sha256: string
  byteLength: number
}

export type TtsPublicJob = {
  id: string
  textbookId: string
  status: 'queued' | 'running' | 'retry_wait' | 'publishing' | 'succeeded' | 'failed'
  total: number
  completed: number
  errorCode?: string
}

export type TtsCreateResult =
  | { kind: 'created'; job: TtsPublicJob }
  | { kind: 'replayed'; job: TtsPublicJob }
  | { kind: 'key_conflict' }
  | { kind: 'active_job' }
  | { kind: 'configuration_unavailable' }

export interface TtsRepository {
  createJob(input: TtsCreateInput): Promise<TtsCreateResult>
  getJob(userId: string, jobId: string): Promise<TtsPublicJob | null>
}
