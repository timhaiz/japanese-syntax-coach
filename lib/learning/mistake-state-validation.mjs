export function validateMistakeStateSnapshot(state, canonicalQuestionIds) {
  if (!state || typeof state !== 'object' || Array.isArray(state)) return {kind: 'invalid'}
  if (state.mistakeStateAvailable === false || !Object.hasOwn(state, 'mistakeStateAvailable')) return {kind: 'legacy'}
  if (state.mistakeStateAvailable !== true || !Array.isArray(state.mistakeStates)) return {kind: 'invalid'}

  const canonical = canonicalQuestionIds instanceof Set ? canonicalQuestionIds : new Set(canonicalQuestionIds)
  const states = new Map()
  for (const row of state.mistakeStates) {
    if (!row || typeof row !== 'object' || Array.isArray(row) ||
      typeof row.questionId !== 'string' || !canonical.has(row.questionId) ||
      typeof row.isMistake !== 'boolean' || !Number.isSafeInteger(row.version) || row.version <= 0 ||
      states.has(row.questionId)) return {kind: 'invalid'}
    states.set(row.questionId, {isMistake: row.isMistake, version: row.version})
  }
  return {kind: 'atomic', states}
}

export function projectMistakeIds(snapshot, pendingOperations, canonicalQuestionIds) {
  const canonical = canonicalQuestionIds instanceof Set ? canonicalQuestionIds : new Set(canonicalQuestionIds)
  const result = new Set()
  for (const [questionId, state] of snapshot) {
    if (canonical.has(questionId) && state.isMistake) result.add(questionId)
  }
  for (const item of pendingOperations) {
    if (!item || !canonical.has(item.questionId)) continue
    let desired = item.expectedIsMistake
    if (typeof desired !== 'boolean') {
      if (item.correct === false) desired = true
      else if (item.correct === true && ['mistakes', 'lesson_replay'].includes(item.mode)) desired = false
      else continue
    }
    if (desired) result.add(item.questionId)
    else result.delete(item.questionId)
  }
  return result
}
