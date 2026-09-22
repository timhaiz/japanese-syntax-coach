import { useEffect, useRef, useState } from 'react'
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
  currentUserId: React.MutableRefObject<string>
  cloudApplied: React.MutableRefObject<boolean>
  syncProgress: (progress: LearningProgress) => void
  retrySyncNow: () => void
}

/**
 * 管理用户认证和学习进度同步
 */
export function useAuthSync(
  onProgressLoaded: (progress: LearningProgress) => void,
): UseAuthSyncReturn {
  const [userId, setUserId] = useState('')
  const [userEmail, setUserEmail] = useState('')
  const [registeredAt, setRegisteredAt] = useState('')
  const [cloudLoaded, setCloudLoaded] = useState(false)
  const [syncState, setSyncState] = useState<SyncState>('local')
  const [syncRetry, setSyncRetry] = useState(0)

  const currentUserId = useRef('')
  const cloudApplied = useRef(false)

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
      cloudApplied.current = true
      setSyncState('synced')
      currentUserId.current = user.id
      setUserId(user.id)
      setUserEmail(user.email || '')
      setRegisteredAt(user.created_at || '')

      const progress = user.user_metadata?.learning_progress
      if (progress) {
        const cloudLessonDone =
          progress.lessonDone && typeof progress.lessonDone === 'object'
            ? Object.fromEntries(
                Object.entries(progress.lessonDone as Record<number, number>).map(
                  ([index, count]) => [index, clampLessonAnswered(count)],
                ),
              )
            : {}

        const cloudLessonCorrect =
          progress.lessonCorrect && typeof progress.lessonCorrect === 'object'
            ? Object.fromEntries(
                Object.entries(progress.lessonCorrect as Record<number, number>).map(
                  ([index, count]) => [index, clampLessonCorrect(count)],
                ),
              )
            : {}

        onProgressLoaded({
          lessonDone: cloudLessonDone,
          lessonCorrect: cloudLessonCorrect,
          completedLessons: completedFromLessonProgress(
            cloudLessonDone,
            progress.completedLessons,
            cloudLessonCorrect,
          ),
          mistakes: normalizeMistakes(progress.mistakes),
        })
      } else {
        onProgressLoaded({
          lessonDone: {},
          lessonCorrect: {},
          completedLessons: [],
          mistakes: [],
        })
      }
      setCloudLoaded(true)
    }

    const clearUser = (hadAuthenticatedUser: boolean) => {
      cloudApplied.current = false
      currentUserId.current = ''
      if (hadAuthenticatedUser) {
        onProgressLoaded({
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

    s.auth.getUser().then(({ data }) => {
      if (!mounted) return
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
      if (event === 'SIGNED_IN' && user.id !== currentUserId.current) {
        setCloudLoaded(false)
        applyUser(user)
      }
    })

    return () => {
      mounted = false
      data.subscription.unsubscribe()
    }
  }, [onProgressLoaded])

  // 同步学习进度到云端
  const syncProgress = (progress: LearningProgress) => {
    if (!cloudLoaded || !userId) return

    const s = getSupabaseBrowser()
    if (!s) return

    const syncedCompleted = completedFromLessonProgress(
      progress.lessonDone,
      progress.completedLessons,
      progress.lessonCorrect,
    )

    const timer = window.setTimeout(() => {
      void (async () => {
        setSyncState('syncing')
        const { error } = await s.auth.updateUser({
          data: {
            learning_progress: {
              version: 2,
              lessonDone: progress.lessonDone,
              lessonCorrect: progress.lessonCorrect,
              completedLessons: syncedCompleted,
              mistakes: progress.mistakes,
              updatedAt: new Date().toISOString(),
            },
          },
        })
        if (error) {
          console.error('Failed to sync learning progress', error)
          setSyncState('failed')
          return
        }
        setSyncState('synced')
      })()
    }, 500)

    return () => window.clearTimeout(timer)
  }

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
    currentUserId,
    cloudApplied,
    syncProgress,
    retrySyncNow,
  }
}
