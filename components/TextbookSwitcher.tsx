'use client'

export type TextbookOption = {
  id: string
  title: string
  shortTitle: string
  cover?: string
  progress: number
  builtIn?: boolean
}

export function TextbookSwitcher({
  textbook,
}: {
  textbook: TextbookOption
}) {
  return (
    <section className="textbook-switcher" aria-label="当前教材">
      <div className="textbook-cover" aria-hidden="true">
        {textbook.cover ? <img src={textbook.cover} alt="" /> : <span>教材</span>}
      </div>
      <div className="textbook-summary">
        <span className="eyebrow">当前教材</span>
        <strong>{textbook.title}</strong>
        <small>学习进度 {textbook.progress}%</small>
      </div>
      <a className="textbook-library-link" href="/textbooks">
        教材库 <span aria-hidden="true">→</span>
      </a>
    </section>
  )
}
