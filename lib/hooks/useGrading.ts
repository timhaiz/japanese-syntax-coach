import { useState, useCallback } from 'react'
import type { Question } from '@/lib/question-bank'
import {
  calculateLocalVerdict,
  generateFeedback,
  recordAnswer,
  buildAnswerRecordParams,
  isAnswerCorrect,
  getSubmittedAnswer,
  type AiVerdict,
  type LocalVerdict,
} from '@/lib/utils/grading-utils'
import type { PracticeMode } from '@/lib/types'

type GradingState = {
  aiVerdict: AiVerdict
  gradeExplanation: string
  gradeSource: 'ai' | 'rule' | null
}

type UseGradingReturn = {
  gradingState: GradingState
  setAiVerdict: (verdict: AiVerdict) => void
  resetGrading: () => void
  gradeAnswer: (params: {
    question: Question
    selectedChoice: string
    tokenAnswer: string
    practiceMode: PracticeMode
    replayMode: boolean
    userId: string
    onCorrect?: () => void
    onIncorrect?: () => void
  }) => { isCorrect: boolean; localVerdict: LocalVerdict }
}

/**
 * 管理答题判分逻辑
 */
export function useGrading(): UseGradingReturn {
  const [aiVerdict, setAiVerdict] = useState<AiVerdict>(null)
  const [gradeExplanation, setGradeExplanation] = useState('')
  const [gradeSource, setGradeSource] = useState<'ai' | 'rule' | null>(null)

  const resetGrading = useCallback(() => {
    setAiVerdict(null)
    setGradeExplanation('')
    setGradeSource(null)
  }, [])

  const gradeAnswer = useCallback(
    ({
      question,
      selectedChoice,
      tokenAnswer,
      practiceMode,
      replayMode,
      userId,
      onCorrect,
      onIncorrect,
    }: {
      question: Question
      selectedChoice: string
      tokenAnswer: string
      practiceMode: PracticeMode
      replayMode: boolean
      userId: string
      onCorrect?: () => void
      onIncorrect?: () => void
    }) => {
      const userAnswer = getSubmittedAnswer(question, selectedChoice, tokenAnswer)
      const { verdict: localVerdict, matches: localMatches } = calculateLocalVerdict(
        question,
        userAnswer,
      )

      // 生成反馈文本
      const feedback = generateFeedback(question, userAnswer, localMatches)
      setGradeExplanation(feedback)
      setGradeSource('rule')

      // 判断是否正确
      const correct = isAnswerCorrect(aiVerdict, localMatches)

      // 执行回调
      if (correct && onCorrect) {
        onCorrect()
      } else if (!correct && onIncorrect) {
        onIncorrect()
      }

      // 记录答题
      if (userId) {
        const params = buildAnswerRecordParams(
          question,
          userAnswer,
          localMatches,
          aiVerdict || localVerdict,
          practiceMode,
          replayMode,
        )
        void recordAnswer(params)
      }

      return { isCorrect: correct, localVerdict }
    },
    [aiVerdict],
  )

  return {
    gradingState: {
      aiVerdict,
      gradeExplanation,
      gradeSource,
    },
    setAiVerdict,
    resetGrading,
    gradeAnswer,
  }
}
