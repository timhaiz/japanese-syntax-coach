// Explicit rollout gate: never silently fall back from atomic writes to legacy RPCs.
const validID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/
const validVersion = (value) => Number.isSafeInteger(value) && value >= 0
const validRow = (row) => row && typeof row.questionId === 'string' && validID.test(row.questionId) && typeof row.isMistake === 'boolean' && validVersion(row.version) && row.version > 0
const unavailable = () => ({status: 503, body: {error: 'Atomic mistake persistence unavailable', code: 'mistake_state_unavailable'}})

export async function mistakeStateResponse(supabase, textbookId, enabled) {
  if (!enabled) return {mistakeStateAvailable: false}
  return {mistakeStateAvailable: true, mistakeStates: await readMistakeState(supabase, textbookId)}
}

export async function readMistakeState(supabase, textbookId) {
  let result
  try {
    result = await supabase.rpc('get_textbook_mistake_state_v1', {p_textbook_id: textbookId})
  } catch {
    throw new Error('Mistake state unavailable')
  }
  const {data, error} = result ?? {}
  if (error || !Array.isArray(data) || !data.every(validRow) || new Set(data.map((row) => row.questionId)).size !== data.length) {
    throw new Error('Mistake state unavailable')
  }
  return data
}

export async function recordAnswerWithMistakes(supabase, body) {
  if (!validVersion(body.expectedMistakeVersion) || typeof body.clientRequestId !== 'string' || !validID.test(body.clientRequestId)) {
    return {status: 428, body: {error: 'A versioned answer is required; existing pending answers are retained', code: 'mistake_version_required'}}
  }
  let result
  try {
    result = await supabase.rpc('record_textbook_answer_with_mistakes_v1', {
    p_operation_id: body.clientRequestId,
    p_textbook_id: body.textbookId,
    p_question_id: body.questionId,
    p_expected_version: body.expectedMistakeVersion,
    p_correct: body.correct,
    p_mode: body.mode,
    p_lesson_id: body.lessonId,
    p_answer: body.answer,
    p_error_tags: body.errorTags ?? [],
    p_knowledge_tags: body.knowledgeTags ?? [],
    p_verdict: body.verdict ?? (body.correct ? 'correct' : 'incorrect'),
    p_lesson_question_limit: Number.isInteger(body.questionLimit) && body.questionLimit > 0 ? body.questionLimit : 20,
    })
  } catch {
    return unavailable()
  }
  const {data, error} = result ?? {}
  if (error?.code === '40001') {
    return {status: 409, body: {error: 'Mistake state changed on another device; this answer was not written', code: 'mistake_version_conflict'}}
  }
  if (data && ((!body.correct && data.isMistake !== true) || (body.correct && ['mistakes', 'lesson_replay'].includes(body.mode) && data.isMistake !== false))) return unavailable()
  if (error || !data || typeof data.duplicate !== 'boolean' || !validRow(data) || data.questionId !== body.questionId || data.version !== body.expectedMistakeVersion + 1 || data.answer == null) return unavailable()
  return {status: 200, body: {
    duplicate: data.duplicate, record: data.answer, textbookScopeAvailable: true,
    mistakeStateAvailable: true,
    mistakeState: {questionId: data.questionId, isMistake: data.isMistake, version: data.version},
  }}
}
