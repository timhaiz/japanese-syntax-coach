const DAY_MS = 24 * 60 * 60 * 1000
const ACTIVE = new Set(['queued', 'running', 'retry_wait', 'publishing'])
const TERMINAL = new Set(['succeeded', 'failed'])

function validNow(now) {
  const value = now instanceof Date ? now.getTime() : now
  if (!Number.isFinite(value)) throw new TypeError('now must be a finite timestamp')
  return value
}

function validLimit(options) {
  const limit = options?.limit ?? 100
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
    throw new RangeError('limit must be an integer between 1 and 1000')
  }
  return limit
}

function timestamp(value) {
  if (value instanceof Date) return value.getTime()
  if (typeof value === 'string') return Date.parse(value)
  return value
}

function eligibleAt(value, now) {
  const time = timestamp(value)
  return Number.isFinite(time) && time <= now
}

function bounded(items, limit, id) {
  return items.slice(0, limit).map(id)
}

export function selectSnapshotCandidates(jobs, now, options = {}) {
  const currentTime = validNow(now)
  const limit = validLimit(options)
  return bounded(
    jobs.filter(
      (job) =>
        TERMINAL.has(job.status) &&
        eligibleAt(job.terminalAt, currentTime - 30 * DAY_MS) &&
        eligibleAt(job.snapshotRetainUntil, currentTime),
    ),
    limit,
    (job) => job.id,
  )
}

export function selectJobCandidates(jobs, now, options = {}) {
  const currentTime = validNow(now)
  const limit = validLimit(options)
  return bounded(
    jobs.filter(
      (job) =>
        TERMINAL.has(job.status) &&
        !ACTIVE.has(job.status) &&
        eligibleAt(job.terminalAt, currentTime - 180 * DAY_MS) &&
        eligibleAt(job.diagnosticsRetainUntil, currentTime) &&
        eligibleAt(job.idempotencyRetainUntil, currentTime),
    ),
    limit,
    (job) => job.id,
  )
}

export function selectAudioCandidates(objects, now, options = {}) {
  const currentTime = validNow(now)
  const limit = validLimit(options)
  return bounded(
    objects.filter(
      (object) =>
        typeof object.key === 'string' &&
        object.key.length > 0 &&
        eligibleAt(object.unreferencedAt, currentTime - 30 * DAY_MS) &&
        object.currentManifestReferences === false &&
        Number.isFinite(object.writeGraceMs) &&
        object.writeGraceMs >= 0 &&
        eligibleAt(timestamp(object.objectCreatedAt) + object.writeGraceMs, currentTime),
    ),
    limit,
    (object) => object.key,
  )
}
