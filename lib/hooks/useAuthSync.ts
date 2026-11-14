import { useCallback, useEffect, useRef, useState } from 'react'
import { getSupabaseBrowser } from '@/lib/supabase'
import type { Question } from '@/lib/question-bank'
import {
  clampLessonAnswered,
  clampLessonCorrect,
  completedFromLessonProgress,
  normalizeMistakes,
} from '@/lib/utils/lesson-utils'

export type SyncState = 'local' | 'syncing' | 'synced' | 'failed'

export type AuthState = {
  userId: string
  userEmail: string
  registeredAt: string
  cloudLoaded: boolean
  syncState: SyncState
}

export type LearningProgress = {
  lessonDone: Record<number, number>
  lessonCorrect: Record<number, number>
  completedLessons: number[]
  mistakes: Question[]
}

type UseAuthSyncReturn = {
  authState: AuthState
  authGeneration: number
  authGenerationRef: React.MutableRefObject<number>
  currentUserId: React.MutableRefObject<string>
  cloudApplied: React.MutableRefObject<boolean>
  syncProgress: (progress: LearningProgress) => void
  retrySyncNow: () => void
}

export type AuthSyncScope = { userId: string; generation: number }

export function isCurrentAuthSyncScope(expected: AuthSyncScope, current: AuthSyncScope) {
  return expected.userId === current.userId && expected.generation === current.generation
}

export function createAuthSyncScheduler(
  clock: Pick<typeof globalThis, 'setTimeout' | 'clearTimeout'> = globalThis,
) {
  let timer: ReturnType<typeof setTimeout> | null = null
  const cancel = () => {
    if (timer !== null) clock.clearTimeout(timer)
    timer = null
  }
  return {
    cancel,
    schedule(scope: AuthSyncScope, getCurrent: () => AuthSyncScope, run: () => void, delay = 500) {
      cancel()
      timer = clock.setTimeout(() => {
        timer = null
        if (isCurrentAuthSyncScope(scope, getCurrent())) run()
      }, delay)
    },
  }
}

export async function updateUserMetadataWithCapturedToken(
  supabaseUrl: string,
  anonKey: string,
  accessToken: string,
  metadata: Record<string, unknown>,
  request: typeof fetch = fetch,
) {
  const response = await request(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/user`, {
    method: 'PUT',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ data: metadata }),
  })
  const payload = await response.json()
  if (!response.ok) return { data: { user: null }, error: payload }
  return { data: { user: payload.user ?? payload }, error: null }
}

export async function updateProgressWithinAuthScope<T>(
  expected: AuthSyncScope,
  getCurrent: () => AuthSyncScope,
  loadSession: () => Promise<{
    data?: {
      session?: { user?: { id?: string }; access_token?: string } | null
    }
    error?: unknown
  }>,
  update: (accessToken: string) => Promise<T>,
): Promise<T | null> {
  if (!isCurrentAuthSyncScope(expected, getCurrent())) return null
  const sessionResult = await loadSession()
  const session = sessionResult.data?.session
  if (
    !isCurrentAuthSyncScope(expected, getCurrent()) ||
    sessionResult.error ||
    session?.user?.id !== expected.userId ||
    !session.access_token
  )
    return null
  const result = await update(session.access_token)
  return isCurrentAuthSyncScope(expected, getCurrent()) ? result : null
}

/**
 * 管理用户认证和学习进度同步
 */
export function useAuthSync(
  onProgressLoaded: (progress: LearningProgress) => void,
  textbookId = 'builtin-japanese-syntax',
  questionLimits: number[] = [],
  questions: Question[] = [],
): UseAuthSyncReturn {
  const [userId, setUserId] = useState('')
  const [userEmail, setUserEmail] = useState('')
  const [registeredAt, setRegisteredAt] = useState('')
  const [cloudLoaded, setCloudLoaded] = useState(false)
  const [syncState, setSyncState] = useState<SyncState>('local')
  const [syncRetry, setSyncRetry] = useState(0)
  const [authGeneration, setAuthGeneration] = useState(0)
  const authGenerationRef = useRef(0)
  const syncSchedulerRef = useRef(createAuthSyncScheduler())

  const clearSyncTimer = () => syncSchedulerRef.current.cancel()
  const advanceAuthGeneration = () => {
    clearSyncTimer()
    authGenerationRef.current += 1
    setAuthGeneration(authGenerationRef.current)
  }

  const currentUserId = useRef('')
  const cloudApplied = useRef(false)
  const onProgressLoadedRef = useRef(onProgressLoaded)
  const learningProgressRef = useRef<Record<string, unknown>>({})
  const currentTextbookId = useRef(textbookId)
  currentTextbookId.current = textbookId

  useEffect(() => {
    onProgressLoadedRef.current = onProgressLoaded
  }, [onProgressLoaded])

  // 初始化认证状态并监听变化
  useEffect(() => {
    const s = getSupabaseBrowser()
    if (!s) {
      setCloudLoaded(true)
      return
    }

    let mounted = true

    const applyUser = (
      user: NonNullable<Awaited<ReturnType<typeof s.auth.getUser>>['data']['user']>,
    ) => {
      if (!mounted) return
      advanceAuthGeneration()
      cloudApplied.current = true
      setSyncState('synced')
      currentUserId.current = user.id
      setUserId(user.id)
      setUserEmail(user.email || '')
      setRegisteredAt(user.created_at || '')

      const allProgress = user.user_metadata?.learning_progress
      learningProgressRef.current =
        allProgress && typeof allProgress === 'object' && !Array.isArray(allProgress)
          ? (allProgress as Record<string, unknown>)
          : {}
      const byTextbook = learningProgressRef.current.byTextbook
      const scopedProgress =
        byTextbook &&
        typeof byTextbook === 'object' &&
        !Array.isArray(byTextbook) &&
        (byTextbook as Record<string, unknown>)[textbookId]
      const progress =
        scopedProgress && typeof scopedProgress === 'object'
          ? (scopedProgress as Record<string, unknown>)
          : textbookId === 'builtin-japanese-syntax' &&
              learningProgressRef.current.lessonDone &&
              typeof learningProgressRef.current.lessonDone === 'object'
            ? learningProgressRef.current
            : null
      if (progress) {
        const questionsById = new Map(questions.map((question) => [question.id, question]))
        const cloudLessonDone =
          progress.lessonDone && typeof progress.lessonDone === 'object'
            ? Object.fromEntries(
                Object.entries(progress.lessonDone as Record<number, number>).map(
                  ([index, count]) => [
                    index,
                    clampLessonAnswered(count, questionLimits[Number(index)]),
                  ],
                ),
              )
            : {}

        const cloudLessonCorrect =
          progress.lessonCorrect && typeof progress.lessonCorrect === 'object'
            ? Object.fromEntries(
                Object.entries(progress.lessonCorrect as Record<number, number>).map(
                  ([index, count]) => [
                    index,
                    clampLessonCorrect(count, questionLimits[Number(index)]),
                  ],
                ),
              )
            : {}

        onProgressLoadedRef.current({
          lessonDone: cloudLessonDone,
          lessonCorrect: cloudLessonCorrect,
          completedLessons: completedFromLessonProgress(
            cloudLessonDone,
            progress.completedLessons,
            cloudLessonCorrect,
            questionLimits.length,
            questionLimits,
          ),
          mistakes: normalizeMistakes(progress.mistakes, (id) => questionsById.get(id)),
        })
      } else {
        onProgressLoadedRef.current({
          lessonDone: {},
          lessonCorrect: {},
          completedLessons: [],
          mistakes: [],
        })
      }
      setCloudLoaded(true)
    }

    const clearUser = (hadAuthenticatedUser: boolean) => {
      advanceAuthGeneration()
      cloudApplied.current = false
      currentUserId.current = ''
      if (hadAuthenticatedUser) {
        onProgressLoadedRef.current({
          lessonDone: {},
          lessonCorrect: {},
          completedLessons: [],
          mistakes: [],
        })
      }
      setUserId('')
      setUserEmail('')
      setRegisteredAt('')
      setSyncState('local')
      setCloudLoaded(true)
    }

    const initialAuthGeneration = authGenerationRef.current
    s.auth.getUser().then(({ data }) => {
      if (!mounted || authGenerationRef.current !== initialAuthGeneration) return
      if (data.user) {
        applyUser(data.user)
      } else {
        clearUser(Boolean(currentUserId.current))
      }
    })

    const { data } = s.auth.onAuthStateChange((event, session) => {
      const user = session?.user
      if (!user) {
        clearUser(Boolean(currentUserId.current))
        return
      }
      if (event === 'SIGNED_IN' && user.id === currentUserId.current) {
        // Re-authentication can retain the same user ID. Fence old work without
        // reapplying the SDK's potentially stale metadata over local progress.
        advanceAuthGeneration()
        setSyncState('local')
        return
      }
      if (
        (event === 'SIGNED_IN' || event === 'INITIAL_SESSION') &&
        user.id !== currentUserId.current
      ) {
        setCloudLoaded(false)
        applyUser(user)
      }
    })

    return () => {
      mounted = false
      data.subscription.unsubscribe()
    }
  }, [])

  // 同步学习进度到云端
  const syncProgress = useCallback(
    (progress: LearningProgress) => {
      if (!cloudLoaded || !userId) return

      const s = getSupabaseBrowser()
      if (!s) return

      clearSyncTimer()
      const expectedScope = { userId, generation: authGenerationRef.current }
      const syncedCompleted = completedFromLessonProgress(
        progress.lessonDone,
        progress.completedLessons,
        progress.lessonCorrect,
        questionLimits.length,
        questionLimits,
      )

      syncSchedulerRef.current.schedule(
        expectedScope,
        () => ({ userId: currentUserId.current, generation: authGenerationRef.current }),
        () => {
          if (
            !isCurrentAuthSyncScope(expectedScope, {
              userId: currentUserId.current,
              generation: authGenerationRef.current,
            })
          )
            return
          setSyncState('syncing')
          void (async () => {
            try {
              const result = await updateProgressWithinAuthScope(
                expectedScope,
                () => ({ userId: currentUserId.current, generation: authGenerationRef.current }),
                () => s.auth.getSession(),
                async (accessToken) => {
                  const scopedProgress = {
                    version: 3,
                    lessonDone: progress.lessonDone,
                    lessonCorrect: progress.lessonCorrect,
                    completedLessons: syncedCompleted,
                    mistakes: progress.mistakes,
                    updatedAt: new Date().toISOString(),
                  }
                  const previousLearningProgress = learningProgressRef.current
                  const existingByTextbook =
                    learningProgressRef.current.byTextbook &&
                    typeof learningProgressRef.current.byTextbook === 'object' &&
                    !Array.isArray(learningProgressRef.current.byTextbook)
                      ? (learningProgressRef.current.byTextbook as Record<string, unknown>)
                      : {}
                  const nextLearningProgress = {
                    ...learningProgressRef.current,
                    version: 3,
                    byTextbook: { ...existingByTextbook, [textbookId]: scopedProgress },
                    ...(textbookId === 'builtin-japanese-syntax' ? scopedProgress : {}),
                  }
                  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
                  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
                  if (!supabaseUrl || !anonKey) {
                    throw new Error('Supabase browser configuration is unavailable')
                  }
                  const response = await updateUserMetadataWithCapturedToken(
                    supabaseUrl,
                    anonKey,
                    accessToken,
                    { learning_progress: nextLearningProgress },
                  )
                  if (
                    !response.error &&
                    response.data.user?.id === expectedScope.userId &&
                    currentTextbookId.current === textbookId &&
                    learningProgressRef.current === previousLearningProgress &&
                    isCurrentAuthSyncScope(expectedScope, {
                      userId: currentUserId.current,
                      generation: authGenerationRef.current,
                    })
                  ) {
                    learningProgressRef.current = nextLearningProgress
                  }
                  return response
                },
              )
              if (
                !isCurrentAuthSyncScope(expectedScope, {
                  userId: currentUserId.current,
                  generation: authGenerationRef.current,
                })
              )
                return
              if (!result) {
                setSyncState('failed')
                return
              }
              if (result.error) {
                console.error('Failed to sync learning progress', result.error)
                setSyncState('failed')
                return
              }
              if (result.data.user?.id !== expectedScope.userId) {
                setSyncState('failed')
                return
              }
              setSyncState('synced')
            } catch (error) {
              if (
                !isCurrentAuthSyncScope(expectedScope, {
                  userId: currentUserId.current,
                  generation: authGenerationRef.current,
                })
              )
                return
              console.error('Failed to sync learning progress', error)
              setSyncState('failed')
            }
          })()
        },
      )
    },
    // A new auth generation cancels old work; changing this callback also makes
    // the page re-schedule its current progress under the new session scope.
    [cloudLoaded, userId, textbookId, questionLimits, authGeneration, syncRetry],
  )

  useEffect(
    () => () => {
      syncSchedulerRef.current.cancel()
    },
    [],
  )

  const retrySyncNow = () => {
    setSyncRetry((v) => v + 1)
  }

  return {
    authState: {
      userId,
      userEmail,
      registeredAt,
      cloudLoaded,
      syncState,
    },
    authGeneration,
    authGenerationRef,
    currentUserId,
    cloudApplied,
    syncProgress,
    retrySyncNow,
  }
}
