import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'
import { nextReviewByVerdict, type ReviewVerdict } from '@/lib/review'

const BUILTIN_TEXTBOOK_ID = 'builtin-japanese-syntax'
const textbookIdPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

type Body = {
  textbookId?: string
  questionId?: string
  lessonId?: number
  questionLimit?: number
  answer?: string
  correct?: boolean
  verdict?: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect'
  errorTags?: string[]
  knowledgeTags?: string[]
  mode?: 'new' | 'review' | 'mistakes' | 'lesson' | 'lesson_replay'
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as Body
  const textbookId = body.textbookId ?? BUILTIN_TEXTBOOK_ID
  if (
    !textbookIdPattern.test(textbookId) ||
    !body.questionId ||
    !Number.isInteger(body.lessonId) ||
    typeof body.answer !== 'string' ||
    typeof body.correct !== 'boolean' ||
    !['new', 'review', 'mistakes', 'lesson', 'lesson_replay'].includes(body.mode ?? '')
  ) {
    return NextResponse.json({ error: 'Invalid answer record' }, { status: 400 })
  }

  const supabase = await getSupabaseServer()
  if (!supabase) return NextResponse.json({ error: 'Supabase is not configured' }, { status: 503 })
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const errorTags = (body.errorTags ?? []).filter((tag): tag is string => typeof tag === 'string')
  const knowledgeTags = (body.knowledgeTags ?? []).filter((tag): tag is string => typeof tag === 'string')
  const verdict: ReviewVerdict =
    body.verdict ?? (body.correct ? 'correct' : 'incorrect')
  const result = await supabase.rpc('record_textbook_learning_attempt', {
    p_textbook_id: textbookId,
    p_question_id: body.questionId,
    p_lesson_id: body.lessonId,
    p_answer: body.answer,
    p_correct: body.correct,
    p_error_tags: errorTags,
    p_knowledge_tags: knowledgeTags,
    p_mode: body.mode,
    p_verdict: verdict,
    p_lesson_question_limit:
      Number.isInteger(body.questionLimit) && (body.questionLimit ?? 0) > 0
        ? body.questionLimit
        : 20,
  })

  if (result.error) {
    if (textbookId !== BUILTIN_TEXTBOOK_ID) {
      return NextResponse.json(
        { error: 'Textbook-scoped cloud sync requires the latest database migration.' },
        { status: 503 },
      )
    }

    // Older deployments still use the original RPC for the built-in textbook.
    let legacy = await supabase.rpc('record_learning_attempt', {
      p_question_id: body.questionId,
      p_lesson_id: body.lessonId,
      p_answer: body.answer,
      p_correct: body.correct,
      p_error_tags: errorTags,
      p_mode: body.mode,
      p_verdict: verdict,
    })
    if (legacy.error && /function|p_verdict|record_learning_attempt/i.test(legacy.error.message || '')) {
      legacy = await supabase.rpc('record_learning_attempt', {
        p_question_id: body.questionId,
        p_lesson_id: body.lessonId,
        p_answer: body.answer,
        p_correct: body.correct,
        p_error_tags: errorTags,
        p_mode: body.mode,
      })
    }
    if (legacy.error) {
      return NextResponse.json({ error: 'Unable to save answer record' }, { status: 500 })
    }

    await supabase.rpc('record_knowledge_point_attempt', {
      p_question_correct: body.correct,
      p_error_tags: errorTags,
      p_knowledge_tags: knowledgeTags,
    })
    const repetitions = Number((legacy.data as { repetitions?: number } | null)?.repetitions) || 0
    const schedule = nextReviewByVerdict(repetitions, verdict)
    await supabase
      .from('question_review_state')
      .update({
        repetitions: schedule.reps,
        interval_days: schedule.intervalDays,
        next_review_at: schedule.dueAt,
        updated_at: new Date().toISOString(),
      })
      .eq('question_id', body.questionId)
      .eq('user_id', user.id)
    return NextResponse.json({ record: legacy.data, textbookScopeAvailable: false })
  }

  return NextResponse.json({ record: result.data, textbookScopeAvailable: true })
}
