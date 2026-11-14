const validVersion = (value) => Number.isSafeInteger(value) && value >= 0
const validExpectedVersion = (value) => validVersion(value) && value < Number.MAX_SAFE_INTEGER
const validID = (value) => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value)
export const matchesMistakeScope = (scope, userId, textbookId, generation) =>
  scope?.userId === userId && scope?.textbookId === textbookId && scope?.generation === generation
const keyFor = (userId, textbookId) => `syntax-coach-mistake-queue:${encodeURIComponent(userId)}:${encodeURIComponent(textbookId)}`
const desiredMistakeState = (item) => typeof item.expectedIsMistake === 'boolean' ? item.expectedIsMistake : !item.correct
const isQueueItem = (item, userId, textbookId) => item && typeof item === 'object' && !Array.isArray(item) &&
  item.userId === userId && item.textbookId === textbookId && validID(item.questionId) &&
  validID(item.clientRequestId) && typeof item.answer === 'string' && typeof item.correct === 'boolean' &&
  (item.expectedMistakeVersion == null || validVersion(item.expectedMistakeVersion)) &&
  (item.expectedIsMistake === undefined || typeof item.expectedIsMistake === 'boolean') &&
  (item.status === undefined || typeof item.status === 'string')
const isAcknowledged = (response, item) => {
  const body = response?.body
  const state = body?.mistakeState
  const hasRecord = body?.record !== null && typeof body?.record === 'object'
  return response?.status === 200 && body?.localOnly !== true &&
    (hasRecord || body?.duplicate === true) && body?.mistakeStateAvailable === true &&
    state?.questionId === item.questionId && typeof state.isMistake === 'boolean' &&
    state.version === item.expectedMistakeVersion + 1 &&
    state.isMistake === desiredMistakeState(item)
}

export function createMistakeQueue(storage = globalThis.localStorage) {
  const read = (userId, textbookId) => {
    const raw = storage.getItem(keyFor(userId, textbookId))
    if (raw == null) return []
    const value = JSON.parse(raw)
    if (!Array.isArray(value) || !value.every((item) => isQueueItem(item, userId, textbookId))) {
      throw new Error('Mistake queue storage is corrupt; queue left unchanged')
    }
    return value
  }
  const write = (userId, textbookId, items) => storage.setItem(keyFor(userId, textbookId), JSON.stringify(items))

  return {
    list: (userId, textbookId) => read(userId, textbookId),
    async enqueue(input) {
      const {userId, textbookId, questionId} = input
      if (!userId || !textbookId || !validID(questionId)) throw new Error('Queue scope and question are required')
      const items = read(userId, textbookId)
      const pending = items.filter((item) => item.questionId === questionId)
      const latest = pending.at(-1)
      const version = input.expectedMistakeVersion ?? input.currentMistakeVersion
      const expectedMistakeVersion = latest
        ? validExpectedVersion(latest.expectedMistakeVersion + 1) ? latest.expectedMistakeVersion + 1 : null
        : input.requireVersioned === true && !validVersion(version) ? null : version ?? 0
      const {requireVersioned: _requireVersioned, ...payload} = input
      const item = {
        ...payload,
        clientRequestId: input.clientRequestId || globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        expectedMistakeVersion,
        blockedByPendingOperation: Boolean(latest) || !validExpectedVersion(expectedMistakeVersion),
        status: latest || !validExpectedVersion(expectedMistakeVersion) ? 'blocked' : 'pending',
        attempts: 0,
      }
      if (!isQueueItem(item, userId, textbookId)) throw new Error('Invalid queued answer operation')
      items.push(item)
      write(userId, textbookId, items)
      return item
    },
    async flush(send, userId, textbookId) {
      const snapshot = read(userId, textbookId)
      const results = []
      for (const item of snapshot) {
        if (item.blockedByPendingOperation || !validExpectedVersion(item.expectedMistakeVersion)) continue
        let response
        try { response = await send(item) } catch { response = {status: 503} }
        const acknowledged = isAcknowledged(response, item)
        const status = response?.status
        results.push({clientRequestId: item.clientRequestId, status, persisted: acknowledged})

        // Merge this response into the latest durable queue, preserving concurrent enqueues.
        const current = read(userId, textbookId)
        const index = current.findIndex((candidate) => candidate.clientRequestId === item.clientRequestId)
        if (index < 0) continue
        if (acknowledged) {
          current.splice(index, 1)
          const following = current.find((candidate) => candidate.questionId === item.questionId && candidate.blockedByPendingOperation)
          if (following && following.expectedMistakeVersion === item.expectedMistakeVersion + 1) {
            following.blockedByPendingOperation = false
            following.status = 'pending'
          }
        } else {
          current[index] = {...current[index], attempts: (current[index].attempts || 0) + 1, status: status === 409 ? 'conflict' : 'failed'}
        }
        write(userId, textbookId, current)
      }
      return results
    },
  }
}
