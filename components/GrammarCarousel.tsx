'use client'

import { useRef, useState } from 'react'
import type { GrammarPoint } from '@/lib/courses'

function speakJapanese(text: string) {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return
  const synthesis = window.speechSynthesis
  const utterance = new SpeechSynthesisUtterance(text)
  utterance.lang = 'ja-JP'
  const japaneseVoice = synthesis
    .getVoices()
    .find((voice) => voice.lang.toLowerCase().startsWith('ja'))
  if (japaneseVoice) utterance.voice = japaneseVoice
  synthesis.cancel()
  synthesis.speak(utterance)
}

type GrammarCarouselProps = {
  lessonId: number
  grammar: GrammarPoint[]
  onStartPractice: () => void
  practiceDisabled?: boolean
  practiceLabel: string
}

export function GrammarCarousel({
  lessonId,
  grammar,
  onStartPractice,
  practiceDisabled = false,
  practiceLabel,
}: GrammarCarouselProps) {
  const [index, setIndex] = useState(0)
  const touchStartX = useRef<number | null>(null)
  const lastIndex = Math.max(grammar.length - 1, 0)
  const current = grammar[index]

  const move = (direction: -1 | 1) => {
    setIndex((value) => Math.max(0, Math.min(lastIndex, value + direction)))
  }

  const handleTouchStart = (event: React.TouchEvent<HTMLElement>) => {
    touchStartX.current = event.touches[0]?.clientX ?? null
  }

  const handleTouchEnd = (event: React.TouchEvent<HTMLElement>) => {
    if (touchStartX.current === null) return
    const endX = event.changedTouches[0]?.clientX ?? touchStartX.current
    const distance = endX - touchStartX.current
    touchStartX.current = null
    if (Math.abs(distance) < 42) return
    move(distance < 0 ? 1 : -1)
  }

  if (!current) return null

  return (
    <section
      className="grammar-carousel"
      aria-label={`第 ${lessonId} 课句型卡片`}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
      onKeyDown={(event) => {
        if (event.key === 'ArrowLeft') move(-1)
        if (event.key === 'ArrowRight') move(1)
      }}
      tabIndex={0}
    >
      <div className="grammar-carousel-head">
        <span>句型卡片</span>
        <b>
          {index + 1} / {grammar.length}
        </b>
      </div>
      <div className="grammar-carousel-viewport">
        <div
          className="grammar-carousel-track"
          style={{ transform: `translateX(-${index * 100}%)` }}
        >
          {grammar.map((item, itemIndex) => (
            <article className="grammar-card" key={`${item.pattern}-${itemIndex}`}>
              <span className="grammar-card-number">{String(itemIndex + 1).padStart(2, '0')}</span>
              <h2>{item.pattern}</h2>
              <p className="grammar-card-meaning">{item.meaning}</p>
              <div className="grammar-card-detail">
                <small>接续</small>
                <p>{item.connection}</p>
                <small>说明</small>
                <p>{item.explanation}</p>
                <small>例句</small>
                <p className="grammar-card-example">{item.example}</p>
                {item.responses?.map((response) => (
                  <p className="grammar-card-extra" key={response}>应答：{response}</p>
                ))}
                {item.pitfalls?.map((pitfall) => (
                  <p className="grammar-card-extra" key={pitfall}>易错：{pitfall}</p>
                ))}
              </div>
              <button
                className="grammar-speak"
                type="button"
                aria-label={`朗读句型 ${item.pattern}`}
                onClick={() => speakJapanese(item.example)}
              >
                🔊 朗读例句
              </button>
            </article>
          ))}
        </div>
      </div>
      <div className="grammar-carousel-controls">
        <button type="button" className="outline" onClick={() => move(-1)} disabled={index === 0}>
          ← 上一个
        </button>
        {index < lastIndex ? (
          <button type="button" className="primary" onClick={() => move(1)}>
            下一个 →
          </button>
        ) : (
          <button
            type="button"
            className="primary"
            onClick={onStartPractice}
            disabled={practiceDisabled}
          >
            {practiceLabel} <span>→</span>
          </button>
        )}
      </div>
      <div className="grammar-dots" aria-label="句型卡片进度">
        {grammar.map((item, itemIndex) => (
          <button
            type="button"
            key={`${item.pattern}-dot-${itemIndex}`}
            className={itemIndex === index ? 'active' : ''}
            aria-label={`查看第 ${itemIndex + 1} 个句型`}
            aria-current={itemIndex === index ? 'step' : undefined}
            onClick={() => setIndex(itemIndex)}
          />
        ))}
      </div>
      <small className="grammar-swipe-hint">左右滑动或使用按钮查看下一个句型</small>
    </section>
  )
}
