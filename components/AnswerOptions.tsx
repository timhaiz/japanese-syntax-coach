'use client'

import type { Question } from '@/lib/question-bank'
import { withKana } from '@/lib/kana'

export type WordToken = { id: string; text: string }

function tokenKana(text: string) {
  const decorated = withKana(text)
  return decorated.startsWith(text) ? decorated.slice(text.length) : ''
}

type AnswerOptionsProps = {
  question: Question
  graded: boolean
  selectedChoice: string
  selectedTokens: WordToken[]
  candidateTokens: WordToken[]
  onChoice: (value: string) => void
  onRemoveToken: (token: WordToken) => void
  onAddToken: (token: WordToken) => void
}

export function AnswerOptions({
  question,
  graded,
  selectedChoice,
  selectedTokens,
  candidateTokens,
  onChoice,
  onRemoveToken,
  onAddToken,
}: AnswerOptionsProps) {
  const selectedTokenIds = new Set(selectedTokens.map((t) => t.id))
  if (question.options) {
    return (
      <div className="choice-list" role="group" aria-label="答案选项">
        {question.options.map((option) => {
          const value = option.slice(0, 1)
          return (
            <button
              key={option}
              type="button"
              className={selectedChoice === value ? 'choice selected' : ''}
              onClick={() => !graded && onChoice(value)}
              disabled={graded}
              aria-pressed={selectedChoice === value}
              aria-label={option}
            >
              {withKana(option)}
            </button>
          )
        })}
      </div>
    )
  }

  return (
    <div className="token-builder">
      <div className="token-answer" aria-label="已选答案">
        {selectedTokens.length ? (
          selectedTokens.map((token) => (
            <button
              type="button"
              className="token-button token-selected"
              key={token.id}
              onClick={(event) => {
                event.currentTarget.blur()
                if (!graded) onRemoveToken(token)
              }}
              disabled={graded}
              aria-label={`移除词块 ${token.text}`}
              data-kana={tokenKana(token.text) || undefined}
            >
              {token.text}
            </button>
          ))
        ) : (
          <span className="token-placeholder">点击下方词块组成答案</span>
        )}
      </div>
      <div className="token-bank" aria-label="候选词块">
        {candidateTokens.map((token) =>
          selectedTokenIds.has(token.id) ? (
            <span aria-hidden="true" className="token-slot" key={token.id}>
              <span data-kana={tokenKana(token.text) || undefined}>{token.text}</span>
            </span>
          ) : (
            <button
              type="button"
              className="token-button"
              key={token.id}
              onClick={(event) => {
                event.currentTarget.blur()
                if (!graded) onAddToken(token)
              }}
              disabled={graded}
              aria-label={token.text}
              data-kana={tokenKana(token.text) || undefined}
            >
              {token.text}
            </button>
          ),
        )}
      </div>
    </div>
  )
}
