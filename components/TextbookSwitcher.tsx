'use client'

import { useRef } from 'react'

export type TextbookOption = {
  id: string
  title: string
  shortTitle: string
  cover?: string
  progress: number
  builtIn?: boolean
}

export function TextbookSwitcher({
  textbooks,
  selectedId,
  onSelect,
  onUpload,
  uploadError,
}: {
  textbooks: TextbookOption[]
  selectedId: string
  onSelect: (id: string) => void
  onUpload: (file: File) => void
  uploadError?: string
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const selected = textbooks.find((textbook) => textbook.id === selectedId) ?? textbooks[0]

  if (!selected) return null

  return (
    <section className="textbook-switcher" aria-label="教材选择">
      <div className="textbook-cover" aria-hidden="true">
        {selected.cover ? <img src={selected.cover} alt="" /> : <span>书封面</span>}
      </div>
      <div className="textbook-summary">
        <span className="eyebrow">当前教材</span>
        <strong>{selected.title}</strong>
        <small>学习进度 {selected.progress}%</small>
      </div>
      <div className="textbook-actions">
        <label className="textbook-select-label" htmlFor="textbook-select">
          切换书籍
        </label>
        <select
          id="textbook-select"
          value={selectedId}
          onChange={(event) => onSelect(event.target.value)}
          aria-label="切换教材"
        >
          {textbooks.map((textbook) => (
            <option key={textbook.id} value={textbook.id}>
              {textbook.shortTitle}
            </option>
          ))}
        </select>
        <button type="button" className="textbook-upload" onClick={() => inputRef.current?.click()}>
          上传教材 JSON
        </button>
        <input
          ref={inputRef}
          type="file"
          accept="application/json,.json"
          hidden
          onChange={(event) => {
            const file = event.target.files?.[0]
            if (file) onUpload(file)
            event.target.value = ''
          }}
        />
      </div>
      {uploadError && <p className="textbook-upload-error" role="alert">{uploadError}</p>}
    </section>
  )
}
