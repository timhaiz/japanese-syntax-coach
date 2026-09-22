'use client'

import type { Question } from '@/lib/question-bank'
import { withKana } from '@/lib/kana'

export type AnswerAnalysis = {
  analysis?: string
  words?: { word: string; kana: string; meaning: string; memory: string }[]
  pitfalls?: string[]
  similarQuestions?: { prompt: string; answer: string }[]
}

type FeedbackData = {
  answerMatches: boolean
  verdictLabel: string
  responseText: string
  expectedAnswerText: string
  gradeSource: 'ai' | 'rule' | null
  gradeExplanation: string
  question: Question
}

type AnalysisState = {
  analysis: AnswerAnalysis | null
  analysisLoading: boolean
  analysisPreview: string
  onAnalyze: () => void
}

export function PracticeFeedback({
  feedbackData,
  analysisState,
}: {
  feedbackData: FeedbackData
  analysisState: AnalysisState
}) {
  const { answerMatches, verdictLabel, responseText, expectedAnswerText, gradeSource, gradeExplanation, question } =
    feedbackData
  const { analysis, analysisLoading, analysisPreview, onAnalyze } = analysisState
  return (
    <div className={'feedback ' + (answerMatches ? 'ok' : 'warn')}>
      <b>{answerMatches ? '✓ ' + verdictLabel : '△ ' + verdictLabel}</b>
      <p>你的答案：{responseText ? withKana(responseText) : '未作答'}</p>
      <p>参考答案：{withKana(expectedAnswerText)}</p>
      {gradeExplanation && (
        <small>
          {gradeSource === 'ai' ? 'AI 批改：' : '规则批改：'}
          {gradeExplanation}
        </small>
      )}
      {!answerMatches && <small>提示：{question.hint}</small>}
      {!analysis && (
        <button className="analysis-button" onClick={onAnalyze} disabled={analysisLoading}>
          {analysisLoading ? '分析中…' : 'AI 分析记忆方法'}
        </button>
      )}
      {analysisLoading && analysisPreview && (
        <div className="analysis streaming">
          <small>AI 正在生成分析…</small>
          <p>{analysisPreview}</p>
        </div>
      )}
      {analysis && (
        <div className="analysis">
          {analysis.analysis && <p>{analysis.analysis}</p>}
          {analysis.words?.map((word) => (
            <div key={word.word}>
              <b>
                {word.word}（{word.kana}）
              </b>
              <span>
                {word.meaning} · {word.memory}
              </span>
            </div>
          ))}
          {analysis.pitfalls?.map((pitfall) => (
            <small key={pitfall}>易错点：{pitfall}</small>
          ))}
          {analysis.similarQuestions?.map((item) => (
            <small key={item.prompt}>
              变式：{withKana(item.prompt)}（参考：{withKana(item.answer)}）
            </small>
          ))}
        </div>
      )}
    </div>
  )
}
