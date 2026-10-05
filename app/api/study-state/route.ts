import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'

const BUILTIN_TEXTBOOK_ID = 'builtin-japanese-syntax'
const validTextbookId = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

export async function GET(request: Request) {
  const textbookId = new URL(request.url).searchParams.get('textbookId') ?? BUILTIN_TEXTBOOK_ID
  if (!validTextbookId.test(textbookId)) {
    return NextResponse.json({ error: 'Invalid textbook ID' }, { status: 400 })
  }
  const supabase = await getSupabaseServer()
  if (!supabase) return NextResponse.json({ error: 'Supabase is not configured' }, { status: 503 })
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (textbookId !== BUILTIN_TEXTBOOK_ID) {
    return NextResponse.json({
      textbookId,
      textbookScopeAvailable: false,
      localOnly: true,
      dueQuestionIds: [],
      lessons: [],
      knowledgePoints: [],
      metrics: { totalAttempts: 0, incorrectAttempts: 0, errorRate: 0, forgettingRate: 0, correctStreak: 0, topErrorTags: [] },
    })
  }

  const load = async (scoped: boolean) => {
    const dueQuery = supabase
      .from('question_review_state')
      .select('question_id')
      .lte('next_review_at', new Date().toISOString())
      .order('next_review_at', { ascending: true })
      .limit(500)
    const completedQuery = supabase
      .from('lesson_progress')
      .select('lesson_id,answered_count,correct_count,completed_at')
      .order('lesson_id', { ascending: true })
    const masteryQuery = supabase
      .from('knowledge_point_mastery')
      .select('knowledge_point,attempts,correct_attempts,mastery,last_answered_at')
      .order('mastery', { ascending: true })
    const attemptsQuery = supabase
      .from('answer_attempts')
      .select('exercise_id,verdict,error_tags,created_at')
      .order('created_at', { ascending: false })
      .limit(500)

    return Promise.all([
      scoped ? dueQuery.eq('textbook_id', textbookId) : dueQuery,
      scoped ? completedQuery.eq('textbook_id', textbookId) : completedQuery,
      scoped ? masteryQuery.eq('textbook_id', textbookId) : masteryQuery,
      scoped ? attemptsQuery.eq('textbook_id', textbookId) : attemptsQuery,
    ])
  }

  let [due, completed, mastery, attempts] = await load(true)
  let textbookScopeAvailable = true
  const scopeColumnMissing = [due.error, completed.error, mastery.error, attempts.error].some(
    (error) =>
      error &&
      (/textbook_id|42703|schema cache/i.test(error.message) || error.code === '42703'),
  )
  if (scopeColumnMissing && textbookId === BUILTIN_TEXTBOOK_ID) {
    ;[due, completed, mastery, attempts] = await load(false)
    textbookScopeAvailable = false
  } else if (scopeColumnMissing) {
    return NextResponse.json(
      { error: 'Textbook-scoped cloud sync requires the latest database migration.' },
      { status: 503 },
    )
  }

  if (due.error || completed.error) {
    return NextResponse.json({ error: 'Unable to load study state' }, { status: 500 })
  }
  const lessons = (completed.data ?? []).map((lesson) => ({
    ...lesson,
    answered_count: Math.max(0, Number(lesson.answered_count) || 0),
    correct_count: Math.max(0, Number(lesson.correct_count) || 0),
  }))
  const rows = attempts.error ? [] : attempts.data ?? []
  let streak = 0
  for (const row of rows) {
    if (row.verdict === 'correct') streak++
    else break
  }
  const total = rows.length
  const incorrect = rows.filter((row) => row.verdict !== 'correct').length
  const tagCounts = new Map<string, number>()
  for (const row of rows) {
    for (const tag of row.error_tags ?? []) tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + 1)
  }
  const topErrorTags = [...tagCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([tag, count]) => ({ tag, count }))
  const seenCorrect = new Set<string>()
  let eligibleReviews = 0
  let forgotten = 0
  for (const row of [...rows].reverse()) {
    const questionId = (row as { exercise_id?: string }).exercise_id
    if (!questionId) continue
    if (seenCorrect.has(questionId)) {
      eligibleReviews++
      if (row.verdict !== 'correct') forgotten++
    }
    if (row.verdict === 'correct') seenCorrect.add(questionId)
  }
  const forgettingRate = eligibleReviews ? Math.round((forgotten / eligibleReviews) * 100) : 0

  return NextResponse.json({
    textbookId,
    textbookScopeAvailable,
    dueQuestionIds: (due.data ?? []).map((item) => item.question_id),
    lessons,
    knowledgePoints: mastery.error ? [] : mastery.data ?? [],
    metrics: {
      totalAttempts: total,
      incorrectAttempts: incorrect,
      errorRate: total ? Math.round((incorrect / total) * 100) : 0,
      forgettingRate,
      correctStreak: streak,
      topErrorTags,
    },
  })
}
