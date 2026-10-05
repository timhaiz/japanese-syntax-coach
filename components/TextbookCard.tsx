'use client'

import type { TextbookOption } from './TextbookSwitcher'

export function TextbookCard({
  textbook,
  selected,
  onSelect,
}: {
  textbook: TextbookOption
  selected: boolean
  onSelect: () => void
}) {
  return (
    <article className={`textbook-card${selected ? ' selected' : ''}`}>
      <div className="textbook-card-cover" aria-hidden="true">
        {textbook.cover ? <img src={textbook.cover} alt="" /> : <span>词本</span>}
      </div>
      <div className="textbook-card-body">
        <div className="textbook-card-heading">
          <h2>{textbook.title}</h2>
          {textbook.builtIn && <span className="textbook-card-badge">内置</span>}
        </div>
        <div className="textbook-card-progress-row">
          <span>学习进度 {textbook.progress}%</span>
          <strong>{textbook.progress}%</strong>
        </div>
        <div className="textbook-card-progress" aria-label={`学习进度 ${textbook.progress}%`}>
          <i style={{ width: `${textbook.progress}%` }} />
        </div>
      </div>
      <button
        type="button"
        className={`textbook-card-action${selected ? ' selected' : ''}`}
        aria-pressed={selected}
        onClick={onSelect}
      >
        {selected ? '学习中' : '开始学习'}
      </button>
    </article>
  )
}
