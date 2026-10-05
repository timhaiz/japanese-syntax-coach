'use client'

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useTextbookCatalog } from '@/lib/hooks/useTextbookCatalog'
import type { TextbookOption } from './TextbookSwitcher'
import { TextbookCard } from './TextbookCard'

export function TextbookLibrary() {
  const {
    selectedId,
    textbookOptions,
    selectTextbook,
    importTextbook,
    uploadError,
  } = useTextbookCatalog()
  const [query, setQuery] = useState('')
  const [moreOpen, setMoreOpen] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  const books = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase()
    return textbookOptions.filter((book) => {
      if (!normalizedQuery) return true
      return `${book.title} ${book.shortTitle}`.toLocaleLowerCase().includes(normalizedQuery)
    })
  }, [query, textbookOptions])

  const openImporter = () => {
    setMoreOpen(false)
    inputRef.current?.click()
  }

  return (
    <main className="shell textbook-library-shell" data-testid="textbook-library">
      <header className="textbook-library-header">
        <Link className="textbook-back-button" href="/" aria-label="返回首页">
          <span aria-hidden="true">‹</span>
        </Link>
        <label className="textbook-search">
          <span aria-hidden="true">⌕</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索词本"
            aria-label="搜索教材"
          />
        </label>
        <button
          className="textbook-more-button"
          type="button"
          aria-label="更多教材操作"
          aria-expanded={moreOpen}
          onClick={() => setMoreOpen((value) => !value)}
        >
          ⋮
        </button>
        {moreOpen && (
          <div className="textbook-more-menu" role="menu">
            <button type="button" role="menuitem" onClick={openImporter}>
              导入教材 JSON
            </button>
          </div>
        )}
      </header>

      <section className="textbook-library-summary" aria-live="polite">
        <span>
          当前 <strong>{selectedId ? 1 : 0}</strong> 本词本正在学习
        </span>
        <span className="textbook-library-count">共 {textbookOptions.length} 本</span>
      </section>

      <section className="textbook-library-list" aria-label="可用教材">
        {books.length > 0 ? (
          books.map((book) => (
            <TextbookCard
              key={book.id}
              textbook={book}
              selected={book.id === selectedId}
              onSelect={() => selectTextbook(book.id)}
            />
          ))
        ) : (
          <div className="textbook-empty-state">
            <strong>{query ? '没有找到匹配的教材' : '这里还没有教材'}</strong>
            <span>{query ? '换个关键词试试。' : '可从右上角更多菜单导入教材。'}</span>
          </div>
        )}
      </section>

      {uploadError && (
        <p className="textbook-library-error" role="alert">
          {uploadError}
        </p>
      )}

      <input
        ref={inputRef}
        className="textbook-file-input"
        type="file"
        accept="application/json,.json"
        onChange={(event) => {
          const file = event.target.files?.[0]
          if (file) {
            void importTextbook(file)
          }
          event.target.value = ''
        }}
      />
    </main>
  )
}
