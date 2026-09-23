'use client'
import { useEffect, useRef, useState, useMemo, useCallback } from 'react'
import { courses } from '@/lib/courses'
import { getSupabaseBrowser } from '@/lib/supabase'
import { useStreamingAnalysis } from '@/lib/hooks/useStreamingAnalysis'
import { useAuthSync } from '@/lib/hooks/useAuthSync'
import { useStudyState } from '@/lib/hooks/useStudyState'
import { useLocalProgressLoader } from '@/lib/hooks/useLocalProgressLoader'
import { usePracticeState } from '@/lib/hooks/usePracticeState'
import { useGradingState } from '@/lib/hooks/useGradingState'
import { useLessonProgress } from '@/lib/hooks/useLessonProgress'
import { useAnswerSubmission } from '@/lib/hooks/useAnswerSubmission'
import {
  isAnswerAccepted,
  normalizeAnswer,
  questionsForLesson,
  questionForId,
  type Question,
} from '@/lib/question-bank'
import { createMixedReviewSet, prioritizeReviewSet } from '@/lib/review-set'
import { BottomNav } from '@/components/BottomNav'
import { AppHeader } from '@/components/AppHeader'
import { HomeHero } from '@/components/HomeHero'
import { GrammarCarousel } from '@/components/GrammarCarousel'
import { ProgressSummary } from '@/components/ProgressSummary'
import { CurrentLessonCard } from '@/components/CurrentLessonCard'
import { LessonGrid } from '@/components/LessonGrid'
import { ProfileOverview } from '@/components/ProfileOverview'
import { AnswerOptions, type WordToken } from '@/components/AnswerOptions'
import { PracticeFeedback, type AnswerAnalysis } from '@/components/PracticeFeedback'
import { withKana } from '@/lib/kana'
import {
  LESSON_QUESTION_LIMIT,
  clampLessonAnswered,
  clampLessonCorrect,
  normalizeMistakes,
  mistakesForLesson,
  coreQuestionsForLesson,
  contiguousCompletedLessons,
  completedFromLessonProgress,
} from '@/lib/utils/lesson-utils'
import { explainAnswerDifference, errorTagsForAnswer, knowledgeTagsForQuestion } from '@/lib/utils/answer-utils'
import { createWordTokens, tokenOrder } from '@/lib/utils/token-utils'

const courseLessons = courses.map((c) => ({ ...c, progress: 0, locked: false }))
export default function Home() {
  const [tab, setTab] = useState('home')
  const [active, setActive] = useState(0)

  // 使用 useAuthSync 管理认证和同步
  const {
    authState,
    currentUserId,
    cloudApplied,
    syncProgress,
    retrySyncNow,
  } = useAuthSync((progress) => {
    setLessonDone(progress.lessonDone)
    setLessonCorrect(progress.lessonCorrect)
    setCompletedLessons(progress.completedLessons)
    setMistakes(progress.mistakes)
  })

  const { userId, userEmail, registeredAt, cloudLoaded, syncState } = authState
  const loadedStudyUserId = useRef('')

  // 使用新的 hooks 管理状态
  const {
    practiceState,
    setPracticeMode,
    setFullLessonMode,
    setReplayMode,
    incrementSessionProgress,
    setSessionProgress,
    setFullLessonProgress,
    setActiveLesson,
    startPractice,
    startReplay,
    resetPractice,
  } = usePracticeState()

  const {
    gradingState,
    setGrading,
    setAiVerdict,
    setExplanation,
    setSource,
    setGraded,
    resetGrading,
  } = useGradingState()

  const { submitAnswer } = useAnswerSubmission()

  // 学习进度相关状态
  const [completedLessons, setCompletedLessons] = useState<number[]>([])
  const [lessonDone, setLessonDone] = useState<Record<number, number>>({})
  const [lessonCorrect, setLessonCorrect] = useState<Record<number, number>>({})
  const [mistakes, setMistakes] = useState<Question[]>([])

  // 使用进度计算 hook
  const progressData = useLessonProgress(
    courses,
    lessonDone,
    lessonCorrect,
    completedLessons,
    mistakes
  )

  const [mixedQuestions, setMixedQuestions] = useState<Question[]>([])
  const [dueQuestionIds, setDueQuestionIds] = useState<string[]>([])
  const [knowledgePointMastery, setKnowledgePointMastery] = useState<Record<string, number>>({})
  const [learningMetrics, setLearningMetrics] = useState<{correctStreak:number;errorRate:number;forgettingRate?:number;topErrorTags:{tag:string;count:number}[]}>({correctStreak:0,errorRate:0,topErrorTags:[]})

  const { analysis, loading: analysisLoading, preview: analysisPreview, startAnalysis, resetAnalysis } = useStreamingAnalysis()
  const [studyStateLoaded, setStudyStateLoaded] = useState(false)
  const [studyStateError, setStudyStateError] = useState('')
  const [studyStateRetry, setStudyStateRetry] = useState(0)
  const [lessonSummary, setLessonSummary] = useState<{
    lessonId: number
    accuracy: number
    mistakeTypes: string[]
    nextLessonId?: number
  } | null>(null)
  const [retryQuestions, setRetryQuestions] = useState<Question[]>([])
  const submittedQuestion = useRef<Question | null>(null)
  const lessonReplayRef = useRef<{ lesson: number; count: number } | null>(null)
  const replayMistakesRef = useRef<Question[]>([])
  const replayCorrectRef = useRef(0)
  const [selectedChoice, setSelectedChoice] = useState('')
  const [availableTokens, setAvailableTokens] = useState<WordToken[]>([])
  const [selectedTokens, setSelectedTokens] = useState<WordToken[]>([])

  // 使用 useLocalProgressLoader 加载本地进度
  const {
    lessonDone: localLessonDone,
    lessonCorrect: localLessonCorrect,
    completedLessons: localCompletedLessons,
    mistakes: localMistakes,
    completedLoaded,
    lessonLoaded,
    mistakesLoaded,
  } = useLocalProgressLoader(cloudLoaded, cloudApplied.current, Boolean(currentUserId.current))

  // 同步本地加载的数据到状态
  useEffect(() => {
    if (!cloudApplied.current && completedLoaded) {
      setCompletedLessons(localCompletedLessons)
    }
  }, [completedLoaded, localCompletedLessons])

  useEffect(() => {
    if (!cloudApplied.current && lessonLoaded) {
      setLessonDone(localLessonDone)
      setLessonCorrect(localLessonCorrect)
    }
  }, [lessonLoaded, localLessonDone, localLessonCorrect])

  useEffect(() => {
    if (!cloudApplied.current && mistakesLoaded) {
      setMistakes(localMistakes)
    }
  }, [mistakesLoaded, localMistakes])

  // 云端进度同步
  useEffect(() => {
    if (!cloudLoaded || !studyStateLoaded || !userId) return
    syncProgress({
      lessonDone,
      lessonCorrect,
      completedLessons,
      mistakes,
    })
  }, [cloudLoaded, studyStateLoaded, userId, lessonDone, lessonCorrect, completedLessons, mistakes, syncProgress])

  useEffect(() => {
      if (!userId) return
    let cancelled = false
    setStudyStateLoaded(false)
    setStudyStateError('')
    void (async () => {
      try {
        const response = await fetch('/api/study-state')
        if (!response.ok) {
          if (!cancelled) setStudyStateError('云端学习记录暂时无法读取，将继续使用当前设备数据。')
          return
        }
        const state = await response.json()
        if (cancelled) return
        setDueQuestionIds(Array.isArray(state.dueQuestionIds) ? state.dueQuestionIds : [])
        setKnowledgePointMastery(Object.fromEntries((state.knowledgePoints || []).map((item: { knowledge_point: string; mastery: number }) => [item.knowledge_point, Number(item.mastery) || 0])))
        if (state.metrics) setLearningMetrics(state.metrics)
        const persistedLessons = Object.fromEntries(
          (state.lessons || []).map((lesson: { lesson_id: number; answered_count: number }) => [
            lesson.lesson_id - 1,
            clampLessonAnswered(lesson.answered_count),
          ]),
        )
        const persistedCorrect = Object.fromEntries(
          (state.lessons || [])
            .filter(
              (lesson: { correct_count?: number }) => typeof lesson.correct_count === 'number',
            )
                .map((lesson: { lesson_id: number; correct_count: number }) => [
                  lesson.lesson_id - 1,
                  clampLessonCorrect(lesson.correct_count),
                ]),
        )
        if (Object.keys(persistedLessons).length) {
          setLessonDone(persistedLessons)
          if (Object.keys(persistedCorrect).length) setLessonCorrect(persistedCorrect)
          setCompletedLessons(
            completedFromLessonProgress(
              persistedLessons,
              (state.lessons || [])
                .filter((lesson: { completed_at: string | null }) => lesson.completed_at)
                .map((lesson: { lesson_id: number }) => lesson.lesson_id - 1),
              persistedCorrect,
            ),
          )
        }
      } catch {
        if (!cancelled) setStudyStateError('云端学习记录暂时无法读取，将继续使用当前设备数据。')
        console.warn('Unable to load durable study state; using local fallback')
      } finally {
        if (!cancelled) {
          loadedStudyUserId.current = userId
          setStudyStateLoaded(true)
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [userId, studyStateRetry])

  // 当 localLessonDone 加载完成后，同步到主状态
  useEffect(() => {
    if (lessonLoaded && localLessonDone) {
      setLessonDone(localLessonDone)
    }
  }, [lessonLoaded, localLessonDone])

  // 当 localLessonCorrect 加载完成后，同步到主状态
  useEffect(() => {
    if (lessonLoaded && localLessonCorrect) {
      setLessonCorrect(localLessonCorrect)
    }
  }, [lessonLoaded, localLessonCorrect])

  // 当 localCompletedLessons 加载完成后，同步到主状态
  useEffect(() => {
    if (completedLoaded && localCompletedLessons) {
      setCompletedLessons(localCompletedLessons)
    }
  }, [completedLoaded, localCompletedLessons])

  // 当 localMistakes 加载完成后，同步到主状态
  useEffect(() => {
    if (mistakesLoaded && localMistakes) {
      setMistakes(localMistakes)
    }
  }, [mistakesLoaded, localMistakes])
  useEffect(() => {
    if (mistakesLoaded) localStorage.setItem('syntax-coach-mistakes', JSON.stringify(mistakes))
  }, [mistakes, mistakesLoaded])
  useEffect(() => {
    if (!lessonLoaded) return
    try {
      const saved = JSON.parse(localStorage.getItem('syntax-coach-lesson-progress') || '{}')
      const merged = {
        ...saved,
        ...Object.fromEntries(
          Object.entries(lessonDone).map(([index, count]) => [
            index,
            clampLessonAnswered(Math.max(Number(saved?.[index]) || 0, Number(count) || 0)),
          ]),
        ),
      }
      localStorage.setItem('syntax-coach-lesson-progress', JSON.stringify(merged))
    } catch {
      localStorage.setItem('syntax-coach-lesson-progress', JSON.stringify(lessonDone))
    }
  }, [lessonDone, lessonLoaded])
  useEffect(() => {
    if (lessonLoaded)
      localStorage.setItem('syntax-coach-lesson-correct', JSON.stringify(lessonCorrect))
  }, [lessonCorrect, lessonLoaded])
  useEffect(() => {
    if (completedLoaded)
      localStorage.setItem('syntax-coach-completed-lessons', JSON.stringify(completedLessons))
  }, [completedLessons, completedLoaded])
  useEffect(() => {
    const answered = clampLessonAnswered(lessonDone[active])
    const correct = clampLessonCorrect(lessonCorrect[active])
    if (answered >= LESSON_QUESTION_LIMIT && correct >= Math.ceil(LESSON_QUESTION_LIMIT * 0.9))
      setCompletedLessons((value) => (value.includes(active) ? value : [...value, active]))
  }, [active, lessonDone, lessonCorrect])
  useEffect(() => {
    if (!gradingState.isGraded) setAiVerdict(null)
  }, [gradingState.isGraded])
  const activeLessonDone = clampLessonAnswered(lessonDone[active])
  const activeLessonCorrect = clampLessonCorrect(lessonCorrect[active])
  const activeLessonAccuracy = activeLessonDone
    ? Math.min(
        100,
        Math.round(
          (Math.min(activeLessonCorrect, LESSON_QUESTION_LIMIT) /
            Math.min(activeLessonDone, LESSON_QUESTION_LIMIT)) *
            100,
        ),
      )
    : 0
  const effectiveCompletedLessons = completedFromLessonProgress(
    lessonDone,
    completedLessons,
    lessonCorrect,
  )
  const lessonUnlockMessage = effectiveCompletedLessons.includes(active)
    ? '本课已达标，下一课已解锁。'
    : activeLessonDone >= LESSON_QUESTION_LIMIT &&
        activeLessonCorrect < Math.ceil(LESSON_QUESTION_LIMIT * 0.9)
      ? `20 题已全部完成，但正确率为 ${activeLessonAccuracy}%；请重练错题，累计至少答对 18 题后解锁下一课。`
      : `需完成 ${LESSON_QUESTION_LIMIT} 题且至少答对 18 题（90%）才能解锁下一课。`
  const displayedLessons = courseLessons.map((lesson, index) => {
    const total = LESSON_QUESTION_LIMIT
    return {
      ...lesson,
      progress: Math.min(100, Math.round((clampLessonAnswered(lessonDone[index]) / total) * 100)),
      locked: index > 0 && !effectiveCompletedLessons.includes(index - 1),
    }
  })
  const lessons = displayedLessons
  const selectedLesson = displayedLessons[Math.min(active, displayedLessons.length - 1)]
  const firstIncompleteLesson = displayedLessons.findIndex(
    (lesson) => !effectiveCompletedLessons.includes(lesson.id - 1),
  )
  const nextLessonIndex =
    firstIncompleteLesson >= 0 ? firstIncompleteLesson : displayedLessons.length - 1
  const progress = practiceState.isFullLesson ? practiceState.fullLessonProgress : practiceState.sessionProgress

  const sessionLimit = useMemo(() =>
    practiceState.mode === 'mistakes'
      ? mistakes.length
      : practiceState.mode === 'mixed'
        ? mixedQuestions.length
        : practiceState.isReplay
          ? retryQuestions.length
          : LESSON_QUESTION_LIMIT
  , [practiceState.mode, practiceState.isReplay, mistakes.length, mixedQuestions.length, retryQuestions.length])

  const lessonQuestions = useMemo(() => coreQuestionsForLesson(selectedLesson.id), [selectedLesson.id])

  const sourceQuestions = useMemo(() =>
    practiceState.mode === 'mistakes'
      ? mistakes
      : practiceState.mode === 'mixed'
        ? mixedQuestions
        : practiceState.isReplay
          ? retryQuestions
          : lessonQuestions
  , [practiceState.mode, practiceState.isReplay, mistakes, mixedQuestions, retryQuestions, lessonQuestions])

  const bankQuestion = sourceQuestions.length
    ? sourceQuestions[progress % sourceQuestions.length]
    : undefined
  const ex = bankQuestion ?? {
    id: `L${String(active + 1).padStart(2, '0')}-Q${String(progress + 1).padStart(3, '0')}`,
    lessonId: active + 1,
    type: '翻译' as const,
    prompt: '本课题目正在准备中。',
    answer: '',
    hint: '请返回课程页后重试。',
  }
  const presentedQuestion = gradingState.isGraded && submittedQuestion.current ? submittedQuestion.current : ex
  const tokenQuestion = presentedQuestion.type === '翻译' || presentedQuestion.type === '问答'
  const tokenAnswer = selectedTokens.map((token) => token.text).join('')
  const selectedTokenIds = new Set(selectedTokens.map((token) => token.id))
  const candidateTokens = [...availableTokens, ...selectedTokens].sort(
    (a, b) => tokenOrder(a.id) - tokenOrder(b.id),
  )
  useEffect(() => {
    if (!bankQuestion || gradingState.isGraded) return
    if (bankQuestion.type === '翻译' || bankQuestion.type === '问答') {
      setAvailableTokens(createWordTokens(bankQuestion))
      setSelectedTokens([])
    } else {
      setAvailableTokens([])
      setSelectedTokens([])
    }
  }, [bankQuestion?.id, practiceState.mode, gradingState.isGraded, tab])

  const selectedChoiceText = useMemo(() =>
    presentedQuestion.options
      ?.find((option) => option.startsWith(`${selectedChoice}：`))
      ?.slice(2)
      .trim() || ''
  , [presentedQuestion.options, selectedChoice])

  const expectedAnswerText = useMemo(() =>
    presentedQuestion.options
      ?.find((option) => option.startsWith(`${presentedQuestion.answer}：`))
      ?.slice(2)
      .trim() || presentedQuestion.answer
  , [presentedQuestion.options, presentedQuestion.answer])

  const practiceInstruction = useMemo(() =>
    presentedQuestion.type === '翻译'
      ? '把下面的中文说成日语'
      : presentedQuestion.type === '选择'
        ? '选择正确的日语句子'
        : presentedQuestion.type === '助词'
          ? '选择正确的助词'
          : '根据提示回答问题'
  , [presentedQuestion.type])

  const responseText = tokenQuestion ? tokenAnswer : selectedChoiceText

  const localAnswerMatches = useMemo(() =>
    presentedQuestion.options
      ? isAnswerAccepted(presentedQuestion, selectedChoiceText) ||
        isAnswerAccepted(presentedQuestion, selectedChoice)
      : isAnswerAccepted(presentedQuestion, responseText)
  , [presentedQuestion, selectedChoiceText, selectedChoice, responseText])

  const answerMatches = gradingState.aiVerdict
    ? gradingState.aiVerdict === 'correct' || gradingState.aiVerdict === 'mostly_correct'
    : localAnswerMatches

  const localVerdict = useMemo(() => localAnswerMatches
    ? 'correct'
    : (() => {
        const expected = normalizeAnswer(expectedAnswerText)
        const actual = normalizeAnswer(responseText)
        const shared = expected.length && actual.length
          ? [...expected].filter((char, index) => char === actual[index]).length / Math.max(expected.length, actual.length)
          : 0
        return shared >= 0.55 ? 'needs_fix' : 'incorrect'
      })()
  , [localAnswerMatches, expectedAnswerText, responseText])
  const grade = useCallback(async () => {
    const question = ex
    const submittedAnswer =
      question.type === '翻译' || question.type === '问答'
        ? tokenAnswer
        : selectedChoiceText

    submittedQuestion.current = question
    resetAnalysis()

    const context = {
      question,
      answer: submittedAnswer,
      practiceMode: practiceState.mode,
      replayMode: practiceState.isReplay,
      currentLesson: active,
      userId,
    }

    const currentProgress = {
      lessonDone,
      lessonCorrect,
      completedLessons,
      mistakes,
      dueQuestionIds,
    }

    const { gradeResult, progressUpdates } = await submitAnswer(context, currentProgress)

    setExplanation(gradeResult.explanation)
    setSource(gradeResult.source)
    setAiVerdict(gradeResult.aiVerdict ?? null)
    setGraded(true)

    if (progressUpdates.lessonDone) setLessonDone(progressUpdates.lessonDone)
    if (progressUpdates.lessonCorrect) setLessonCorrect(progressUpdates.lessonCorrect)
    if (progressUpdates.completedLessons) setCompletedLessons(progressUpdates.completedLessons)
    if (progressUpdates.mistakes) setMistakes(progressUpdates.mistakes)
    if (progressUpdates.dueQuestionIds && practiceState.mode !== 'mixed') {
      setDueQuestionIds(progressUpdates.dueQuestionIds)
    }
    // 使用函数式更新兜底，避免答题回调捕获旧的到期题队列，导致
    // 完成复习后首页仍保留刚刚答过的最后一题。
    if (practiceState.mode === 'mixed') {
      setDueQuestionIds((value) => value.filter((id) => id !== question.id))
    }

    if (practiceState.isReplay) {
      if (gradeResult.correct) {
        replayMistakesRef.current = replayMistakesRef.current.filter(
          (item) => item.id !== question.id,
        )
        replayCorrectRef.current = Math.min(LESSON_QUESTION_LIMIT, replayCorrectRef.current + 1)
      } else if (!replayMistakesRef.current.some((item) => item.id === question.id)) {
        replayMistakesRef.current = [...replayMistakesRef.current, question]
      }
    }
  }, [ex, tokenAnswer, selectedChoiceText, submittedQuestion, resetAnalysis, practiceState.mode, practiceState.isReplay, active, userId, lessonDone, lessonCorrect, completedLessons, mistakes, dueQuestionIds, submitAnswer, setExplanation, setSource, setAiVerdict, setGraded, setLessonDone, setLessonCorrect, setCompletedLessons, setMistakes, setDueQuestionIds, replayMistakesRef, replayCorrectRef])
  const displayCorrect = gradingState.aiVerdict
    ? gradingState.aiVerdict === 'correct' || gradingState.aiVerdict === 'mostly_correct'
    : answerMatches
  const verdictLabel =
    gradingState.aiVerdict === 'mostly_correct'
      ? '基本正确'
      : gradingState.aiVerdict === 'needs_fix'
        ? '需要修改'
        : gradingState.aiVerdict === 'incorrect'
          ? '句型或词语还需要调整'
          : displayCorrect
            ? '很好，句型正确'
            : '句型或词语还需要调整'
  const resetTokens = useCallback(() => {
    setAvailableTokens([])
    setSelectedTokens([])
  }, [])

  // 统一的练习初始化逻辑
  const initializePractice = useCallback((options: {
    mode: 'lesson' | 'mistakes' | 'mixed'
    isFullLesson: boolean
    questions?: Question[]
  }) => {
    submittedQuestion.current = null
    replayMistakesRef.current = []
    setSelectedChoice('')
    if (options.questions) {
      setMixedQuestions(options.questions)
    }
    setPracticeMode(options.mode)
    setFullLessonMode(options.isFullLesson)
    setSessionProgress(0)
    setAiVerdict(null)
    setGraded(false)
    setTab('practice')
  }, [setPracticeMode, setFullLessonMode, setSessionProgress])

  const startLessonPractice = useCallback((lessonIndex = active) => {
    setSelectedChoice('')
    setMixedQuestions([])
    let existingAnswered = clampLessonAnswered(lessonDone[lessonIndex])
    if (existingAnswered === 0 && typeof window !== 'undefined' && !cloudApplied.current) {
      try {
        const saved = JSON.parse(localStorage.getItem('syntax-coach-lesson-progress') || '{}')
        const cached = Number(saved?.[lessonIndex])
        if (Number.isFinite(cached))
          existingAnswered = Math.max(0, Math.min(LESSON_QUESTION_LIMIT, cached))
      } catch {}
    }
    lessonReplayRef.current =
      existingAnswered >= LESSON_QUESTION_LIMIT
        ? { lesson: lessonIndex, count: existingAnswered }
        : null
    replayCorrectRef.current =
      existingAnswered >= LESSON_QUESTION_LIMIT
        ? clampLessonCorrect(lessonCorrect[lessonIndex])
        : 0
    const lessonMistakes = mistakesForLesson(mistakes, lessonIndex + 1)
    setRetryQuestions(lessonMistakes)
    replayMistakesRef.current = lessonMistakes
    if (existingAnswered > 0 && existingAnswered !== (lessonDone[lessonIndex] ?? 0))
      setLessonDone((value) => ({ ...value, [lessonIndex]: existingAnswered }))
    setReplayMode(existingAnswered >= LESSON_QUESTION_LIMIT && lessonMistakes.length > 0)
    setFullLessonProgress(
      existingAnswered >= LESSON_QUESTION_LIMIT
        ? 0
        : Math.min(existingAnswered, LESSON_QUESTION_LIMIT - 1),
    )
    if (existingAnswered === 0) setLessonCorrect((value) => ({ ...value, [lessonIndex]: 0 }))
    setActive(lessonIndex)

    // 使用统一初始化
    initializePractice({ mode: 'lesson', isFullLesson: true })
  }, [active, lessonDone, lessonCorrect, mistakes, setReplayMode, setFullLessonProgress, initializePractice])

  const startMistakePractice = useCallback(() => {
    if (mistakes.length) {
      initializePractice({ mode: 'mistakes', isFullLesson: false })
    }
  }, [mistakes.length, initializePractice])

  const startMixedPractice = useCallback(() => {
    const questions = prioritizeReviewSet(createMixedReviewSet(effectiveCompletedLessons, 20), knowledgePointMastery, dueQuestionIds)
    if (questions.length) {
      initializePractice({ mode: 'mixed', isFullLesson: false, questions })
    }
  }, [effectiveCompletedLessons, knowledgePointMastery, dueQuestionIds, initializePractice])

  const startDueReview = useCallback(() => {
    const questions = prioritizeReviewSet(
      dueQuestionIds.map((id) => questionForId(id)).filter((item): item is Question => Boolean(item)),
      knowledgePointMastery,
      dueQuestionIds,
    ).slice(0, 20)
    if (!questions.length) return
    initializePractice({ mode: 'mixed', isFullLesson: false, questions })
  }, [dueQuestionIds, knowledgePointMastery, initializePractice])

  const nextQuestion = useCallback(() => {
    const complete = progress >= sessionLimit - 1
    const finalCorrect = clampLessonCorrect(
      practiceState.isReplay ? replayCorrectRef.current : clampLessonCorrect(lessonCorrect[active]) + (answerMatches ? 1 : 0),
    )
    if (practiceState.mode === 'lesson') {
      setFullLessonProgress((value) => value + 1)
      const replayCount =
        lessonReplayRef.current?.lesson === active ? lessonReplayRef.current.count : null
      const alreadyCompleted =
        clampLessonAnswered(lessonDone[active]) >= LESSON_QUESTION_LIMIT ||
        (replayCount !== null && replayCount >= LESSON_QUESTION_LIMIT)
      if (!practiceState.isReplay) {
        if (!alreadyCompleted) {
          setLessonDone((value) => ({
            ...value,
            [active]: Math.min(LESSON_QUESTION_LIMIT, (value[active] ?? 0) + 1),
          }))
          setLessonCorrect((value) => ({ ...value, [active]: finalCorrect }))
          if (complete && finalCorrect / sessionLimit >= 0.9)
            setCompletedLessons((value) => (value.includes(active) ? value : [...value, active]))
        }
      } else if (replayCount !== null) {
        replayCorrectRef.current = finalCorrect
        setLessonDone((value) => ({ ...value, [active]: replayCount }))
        setLessonCorrect((value) => ({ ...value, [active]: finalCorrect }))
        if (complete && finalCorrect >= Math.ceil(LESSON_QUESTION_LIMIT * 0.9))
          setCompletedLessons((value) => (value.includes(active) ? value : [...value, active]))
      }
    }
    setSessionProgress((value) => value + 1)
    const currentQuestion = submittedQuestion.current
    submittedQuestion.current = null
    setSelectedChoice('')
    setGraded(false)
    if (complete && practiceState.mode === 'lesson') {
      const remainingMistakes = practiceState.isReplay
        ? replayMistakesRef.current
        : mistakes
            .filter((item) => item.id.startsWith(`L${String(active + 1).padStart(2, '0')}-`))
            .filter((item) => !answerMatches || item.id !== currentQuestion?.id)
      const summaryMistakes =
        practiceState.isReplay || !currentQuestion || answerMatches
          ? remainingMistakes
          : [...remainingMistakes, currentQuestion]
      const types = summaryMistakes.map((item) => item.type)
      const lessonQualified = finalCorrect >= Math.ceil(LESSON_QUESTION_LIMIT * 0.9)
      setLessonSummary({
        lessonId: active + 1,
        accuracy: Math.round((finalCorrect / LESSON_QUESTION_LIMIT) * 100),
        mistakeTypes: Array.from(new Set(types)),
        nextLessonId:
          lessonQualified && active < courses.length - 1 ? active + 2 : undefined,
      })
      setTab('home')
    } else if (complete) {
      setTab('home')
    }
  }, [progress, sessionLimit, practiceState.isReplay, practiceState.mode, replayCorrectRef, lessonCorrect, active, answerMatches, lessonDone, lessonReplayRef, submittedQuestion, mistakes, courses, setFullLessonProgress, setLessonDone, setLessonCorrect, setCompletedLessons, setSessionProgress, setSelectedChoice, setGraded, replayMistakesRef, setLessonSummary, setTab])
  const currentLesson = displayedLessons[nextLessonIndex] ?? displayedLessons[0]
  const overallProgress = Math.round(
    displayedLessons.reduce((sum, lesson) => sum + lesson.progress, 0) / displayedLessons.length,
  )
  const learnerName = userEmail ? userEmail.split('@')[0] : '学习者'
  const registrationDate = registeredAt
    ? new Intl.DateTimeFormat('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).format(new Date(registeredAt))
    : '—'
  const totalAnswered = Object.values(lessonDone).reduce(
    (sum, count) => sum + clampLessonAnswered(count),
    0,
  )
  const allLessonsCompleted = effectiveCompletedLessons.length === displayedLessons.length
  const currentLessonMistakeCount = mistakesForLesson(mistakes, currentLesson.id).length
  if (!cloudLoaded || (userId && !studyStateLoaded)) {
    return (
      <main className="shell loading-shell" aria-busy="true" aria-live="polite">
        <div className="loading-card">
          <span className="loading-mark">文</span>
          <p>正在加载学习记录…</p>
          <small>马上恢复你的课程进度和错题。</small>
        </div>
      </main>
    )
  }
  return (
    <main className="shell">
      <AppHeader
        lessonId={currentLesson.id}
        learnerName={learnerName}
        onProfile={() => setTab('me')}
      />
      {studyStateError && userId && (
        <div className="state-note warning" role="alert">
          <span>{studyStateError}</span>
          <button type="button" onClick={() => setStudyStateRetry((value) => value + 1)}>
            重试
          </button>
        </div>
      )}
      {tab === 'home' && (
        <>
          {lessonSummary && (
            <section className="lesson-summary">
              <p className="eyebrow">本课完成</p>
              <h2>第 {lessonSummary.lessonId} 课练习完成</h2>
              <p>
                正确率 <b>{lessonSummary.accuracy}%</b>
              </p>
              <p>
                {lessonSummary.mistakeTypes.length
                  ? `需要巩固：${lessonSummary.mistakeTypes.join('、')}`
                  : '本课没有新增错题，保持得很好。'}
              </p>
              {lessonSummary.nextLessonId && (
                <button
                  className="primary"
                  onClick={() => {
                    setLessonSummary(null)
                    setActive(lessonSummary.nextLessonId! - 1)
                    setTab('lesson')
                  }}
                >
                  进入第 {lessonSummary.nextLessonId} 课 <span>→</span>
                </button>
              )}
            </section>
          )}
          <HomeHero
            learnerName={learnerName}
            lessonId={currentLesson.id}
            progress={currentLesson.progress}
            onStart={() => {
              setActive(nextLessonIndex)
              setTab('lesson')
            }}
            actionLabel={
              allLessonsCompleted && currentLessonMistakeCount === 0
                ? '全部课程已完成'
                : undefined
            }
            actionDisabled={allLessonsCompleted && currentLessonMistakeCount === 0}
          />
          {effectiveCompletedLessons.some((index) => (index + 1) % 5 === 0) && (
            <button className="primary wide" onClick={startMixedPractice}>
              开始综合混练（已完成课程） <span>→</span>
            </button>
          )}
          {dueQuestionIds.length > 0 && (
            <button className="outline wide" onClick={startDueReview}>
              开始今日到期复习（{Math.min(dueQuestionIds.length, 20)} 题） <span>→</span>
            </button>
          )}
          <ProgressSummary
            lessonProgress={currentLesson.progress}
            lessonId={currentLesson.id}
            overallProgress={overallProgress}
          />
          <section className="section-head">
            <div>
              <p className="eyebrow">本课路径</p>
              <h2>{currentLesson.progress > 0 ? '接着练这一课' : '先学句型，再开始练习'}</h2>
            </div>
            <button className="link" onClick={() => setTab('lessons')}>
              课程地图 →
            </button>
          </section>
          <CurrentLessonCard
            lesson={currentLesson}
            onOpen={() => {
              setActive(nextLessonIndex)
              setTab('lesson')
            }}
          />
        </>
      )}
      {tab === 'lessons' && (
        <>
          <div className="page-title">
            <p className="eyebrow">课程地图</p>
            <h1>标准日本语·上册</h1>
            <p className="muted">24 课 · 从句型骨架开始，逐步建立语感</p>
          </div>
          <LessonGrid
            lessons={lessons}
            onSelect={(index) => {
              setActive(index)
              setTab('lesson')
            }}
          />
        </>
      )}
      {tab === 'lesson' && (
        <>
          <button className="back" onClick={() => setTab('home')}>
            ← 返回
          </button>
          <div className="page-title">
            <div className="tag">第 {selectedLesson.id} 课 · 核心句型</div>
            <h1>{selectedLesson.title}</h1>
            <p className="muted">{selectedLesson.goal}</p>
          </div>
          <div className="lesson-status">
            <b>
              已作答 {activeLessonDone} / {LESSON_QUESTION_LIMIT} · 正确 {activeLessonCorrect} 题（
              {activeLessonAccuracy}%）
            </b>
            <small>{lessonUnlockMessage}</small>
          </div>
          <GrammarCarousel
            key={selectedLesson.id}
            lessonId={selectedLesson.id}
            grammar={selectedLesson.grammar}
            onStartPractice={() => startLessonPractice(active)}
            practiceDisabled={
              activeLessonDone >= LESSON_QUESTION_LIMIT &&
              mistakesForLesson(mistakes, selectedLesson.id).length === 0
            }
            practiceLabel={
              activeLessonDone >= LESSON_QUESTION_LIMIT &&
              mistakesForLesson(mistakes, selectedLesson.id).length > 0
                ? `重练本课错题（${mistakesForLesson(mistakes, selectedLesson.id).length} 题）`
                : activeLessonDone >= LESSON_QUESTION_LIMIT
                  ? '本课已完成，无错题需要重练'
                  : `开始整课练习（${LESSON_QUESTION_LIMIT} 题）`
            }
          />
          {active < displayedLessons.length - 1 && (
            <div className="next-preview">
              <b>下一课预告：第 {selectedLesson.id + 1} 课</b>
              <p>{displayedLessons[active + 1].goal}</p>
              <small>完成本课全部题目且正确率达到 90% 后解锁</small>
            </div>
          )}
        </>
      )}
      {tab === 'practice' && (
        <>
          <div className="practice-top">
            <button className="back" onClick={() => setTab('home')}>
              × 退出
            </button>
            <span>
              {practiceState.mode === 'mistakes' ? '错题练习' : `第 ${selectedLesson.id} 课 · 练习`}
            </span>
            <b>
              {Math.min(progress + 1, sessionLimit)} / {sessionLimit}
            </b>
          </div>
          <div className="quiz">
            <div className="quiz-meta">
              <span className="tag">{presentedQuestion.type}</span>
              <span>句型骨架</span>
            </div>
            <h2>{practiceInstruction}</h2>
            <div className="prompt">{withKana(presentedQuestion.prompt)}</div>
            <AnswerOptions
              question={presentedQuestion}
              graded={gradingState.isGraded}
              selectedChoice={selectedChoice}
              selectedTokens={selectedTokens}
              candidateTokens={candidateTokens}
              onChoice={setSelectedChoice}
              onRemoveToken={(token) => {
                setSelectedTokens((value) => value.filter((item) => item.id !== token.id))
                setAvailableTokens((value) => [...value, token])
              }}
              onAddToken={(token) => {
                setAvailableTokens((value) => value.filter((item) => item.id !== token.id))
                setSelectedTokens((value) => [...value, token])
              }}
            />{' '}
            {gradingState.isGraded && (
              <PracticeFeedback
                feedbackData={{
                  answerMatches,
                  verdictLabel,
                  responseText,
                  expectedAnswerText,
                  gradeSource: gradingState.source,
                  gradeExplanation: gradingState.explanation,
                  question: presentedQuestion,
                }}
                analysisState={{
                  analysis,
                  analysisLoading,
                  analysisPreview,
                  onAnalyze: () =>
                    startAnalysis({
                      prompt: presentedQuestion.prompt,
                      answer: responseText,
                      standardAnswer: presentedQuestion.answer,
                      hint: presentedQuestion.hint,
                    }),
                }}
              />
            )}
            <button
              className="primary wide"
              onClick={() => (gradingState.isGraded ? nextQuestion() : grade())}
              disabled={
                !gradingState.isGraded &&
                (presentedQuestion.options ? !selectedChoice : !selectedTokens.length)
              }
            >
              {gradingState.isGraded ? (progress >= sessionLimit - 1 ? '完成训练' : '下一题') : '提交答案'}{' '}
              <span>→</span>
            </button>
          </div>
        </>
      )}
      {tab === 'mistakes' && (
        <>
          <div className="page-title">
            <p className="eyebrow">复习重点</p>
            <h1>错题本</h1>
            <p className="muted">把容易忘的地方，再练一次。</p>
          </div>
          {!mistakesLoaded && <div className="empty-note loading-note">正在加载错题…</div>}
          {mistakesLoaded && mistakes.length > 0 && (
            <button className="primary wide" onClick={startMistakePractice}>
              开始错题练习（{mistakes.length} 题）
            </button>
          )}
          {mistakes.map((item) => (
            <div className="mistake-card" key={item.id}>
              <div className="mistake-icon">文</div>
              <div>
                <b>{withKana(item.prompt)}</b>
                <p>
                  第 {item.lessonId} 课 · {item.type}
                </p>
                <small>
                  参考答案：
                  {item.options
                    ?.find((option) => option.startsWith(`${item.answer}：`))
                    ?.slice(2)
                    .trim() || withKana(item.answer)}
                </small>
              </div>
              <span>→</span>
            </div>
          ))}
          {mistakesLoaded && mistakes.length === 0 && (
            <div className="empty-note">
              目前没有错题
              <br />
              完成练习后，错题会自动收录。
            </div>
          )}
        </>
      )}
      {tab === 'me' && (
        <>
          <div className="page-title">
            <p className="eyebrow">个人中心</p>
            <h1>我的</h1>
            <p className="muted">学习记录会在登录后同步到云端。</p>
          </div>
          <ProfileOverview
            email={userEmail}
            registrationDate={registrationDate}
            lessonId={currentLesson.id}
            progress={overallProgress}
            totalAnswered={totalAnswered}
            completedCount={completedLessons.length}
            metrics={learningMetrics}
            syncLabel={
              userEmail
                ? syncState === 'failed'
                  ? '需要重试'
                  : syncState === 'syncing'
                    ? '同步中'
                    : syncState === 'synced'
                      ? '已同步'
                      : '仅本机'
                : '登录后同步'
            }
            onLogin={() => (location.href = '/login')}
          />
          {userEmail && (
            <div className={'sync-note ' + syncState}>
              {syncState === 'syncing'
                ? '正在同步学习记录…'
                : syncState === 'failed'
                  ? '同步失败，请检查网络后重试。'
                  : syncState === 'synced'
                    ? '学习记录已同步到云端。'
                    : '仅保存在当前设备。'}
              {syncState === 'failed' && (
                <button onClick={() => retrySyncNow()}>重试</button>
              )}
            </div>
          )}
        </>
      )}
      <BottomNav activeTab={tab} onNavigate={setTab} />
    </main>
  )
}
