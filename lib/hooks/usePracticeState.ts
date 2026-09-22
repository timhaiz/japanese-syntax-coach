/**
 * 练习模式状态管理 Hook
 *
 * 合并练习相关的分散状态：
 * - practiceMode
 * - fullLessonMode
 * - replayMode
 * - sessionProgress
 * - fullLessonProgress
 */

import { useState, useCallback } from 'react'

export type PracticeMode = 'lesson' | 'mistakes' | 'mixed'

export type PracticeState = {
  mode: PracticeMode
  isFullLesson: boolean
  isReplay: boolean
  sessionProgress: number
  fullLessonProgress: number
  activeLesson: number
}

const initialState: PracticeState = {
  mode: 'lesson',
  isFullLesson: false,
  isReplay: false,
  sessionProgress: 0,
  fullLessonProgress: 0,
  activeLesson: 0,
}

export function usePracticeState() {
  const [state, setState] = useState<PracticeState>(initialState)

  const setPracticeMode = useCallback((mode: PracticeMode) => {
    setState((prev) => ({ ...prev, mode }))
  }, [])

  const setFullLessonMode = useCallback((isFullLesson: boolean) => {
    setState((prev) => ({ ...prev, isFullLesson }))
  }, [])

  const setReplayMode = useCallback((isReplay: boolean) => {
    setState((prev) => ({ ...prev, isReplay }))
  }, [])

  const incrementSessionProgress = useCallback(() => {
    setState((prev) => ({ ...prev, sessionProgress: prev.sessionProgress + 1 }))
  }, [])

  const setFullLessonProgress = useCallback((progress: number) => {
    setState((prev) => ({ ...prev, fullLessonProgress: progress }))
  }, [])

  const setActiveLesson = useCallback((lesson: number) => {
    setState((prev) => ({ ...prev, activeLesson: lesson }))
  }, [])

  const startPractice = useCallback((lessonIndex: number, mode: PracticeMode = 'lesson') => {
    setState({
      mode,
      isFullLesson: true,
      isReplay: false,
      sessionProgress: 0,
      fullLessonProgress: 0,
      activeLesson: lessonIndex,
    })
  }, [])

  const startReplay = useCallback((lessonIndex: number) => {
    setState({
      mode: 'lesson',
      isFullLesson: true,
      isReplay: true,
      sessionProgress: 0,
      fullLessonProgress: 0,
      activeLesson: lessonIndex,
    })
  }, [])

  const reset = useCallback(() => {
    setState(initialState)
  }, [])

  return {
    practiceState: state,
    setPracticeMode,
    setFullLessonMode,
    setReplayMode,
    incrementSessionProgress,
    setFullLessonProgress,
    setActiveLesson,
    startPractice,
    startReplay,
    resetPractice: reset,
  }
}
