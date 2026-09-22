/**
 * 判分状态管理 Hook
 *
 * 合并分散的判分相关状态：
 * - aiVerdict
 * - gradeExplanation
 * - gradeSource
 */

import { useState, useCallback } from 'react'

export type GradingState = {
  aiVerdict: 'correct' | 'mostly_correct' | 'needs_fix' | 'incorrect' | null
  explanation: string
  source: 'ai' | 'rule' | 'typesafe' | null
  isGraded: boolean
}

const initialState: GradingState = {
  aiVerdict: null,
  explanation: '',
  source: null,
  isGraded: false,
}

export function useGradingState() {
  const [state, setState] = useState<GradingState>(initialState)

  const setGrading = useCallback((update: Partial<GradingState>) => {
    setState((prev) => ({ ...prev, ...update }))
  }, [])

  const setAiVerdict = useCallback((verdict: GradingState['aiVerdict']) => {
    setState((prev) => ({ ...prev, aiVerdict: verdict }))
  }, [])

  const setExplanation = useCallback((explanation: string) => {
    setState((prev) => ({ ...prev, explanation }))
  }, [])

  const setSource = useCallback((source: GradingState['source']) => {
    setState((prev) => ({ ...prev, source }))
  }, [])

  const setGraded = useCallback((isGraded: boolean) => {
    setState((prev) => ({ ...prev, isGraded }))
  }, [])

  const reset = useCallback(() => {
    setState(initialState)
  }, [])

  return {
    gradingState: state,
    setGrading,
    setAiVerdict,
    setExplanation,
    setSource,
    setGraded,
    resetGrading: reset,
  }
}
