import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  builtInTextbookPackage,
  type TextbookPackage,
} from '@/lib/textbooks'
import {
  getStoredTextbookPackages,
  parseTextbookJson,
  saveTextbookPackage,
} from '@/lib/textbook-import'
import { textbookProgress } from '@/lib/textbook-progress'

const SELECTED_TEXTBOOK_KEY = 'japanese-syntax-coach:selected-textbook:v1'

export function useTextbookCatalog() {
  const [textbooks, setTextbooks] = useState<TextbookPackage[]>([builtInTextbookPackage])
  const [selectedId, setSelectedId] = useState(builtInTextbookPackage.textbook.id)
  const [uploadError, setUploadError] = useState('')
  const [progressById, setProgressById] = useState<Record<string, number>>({})

  useEffect(() => {
    const available = [builtInTextbookPackage, ...getStoredTextbookPackages()]
    setTextbooks(available)
    setProgressById(
      Object.fromEntries(
        available.map(({ textbook }) => [
          textbook.id,
          textbookProgress(
            textbook.id,
            textbook.lessons.map((lesson) =>
              textbook.questions.filter((question) => question.lessonId === lesson.id).length,
            ),
          ),
        ]),
      ),
    )
    try {
      const savedId = localStorage.getItem(SELECTED_TEXTBOOK_KEY)
      if (savedId && available.some((item) => item.textbook.id === savedId)) setSelectedId(savedId)
    } catch {
      // Keep the built-in textbook active when browser storage is unavailable.
    }
  }, [])

  const selectedTextbook = useMemo(
    () => textbooks.find((item) => item.textbook.id === selectedId) ?? builtInTextbookPackage,
    [selectedId, textbooks],
  )

  const textbookOptions = useMemo(
    () => textbooks.map(({ textbook }) => ({
      id: textbook.id,
      title: textbook.title,
      shortTitle: textbook.shortTitle || (textbook.title.length > 12 ? `${textbook.title.slice(0, 12)}…` : textbook.title),
      cover: textbook.cover,
      progress: progressById[textbook.id] ?? 0,
      builtIn: textbook.id === builtInTextbookPackage.textbook.id,
    })),
    [progressById, textbooks],
  )

  const activateTextbook = useCallback((id: string) => {
    setSelectedId(id)
    setUploadError('')
    try {
      localStorage.setItem(SELECTED_TEXTBOOK_KEY, id)
    } catch {
      // The active choice remains valid for the current tab.
    }
  }, [])

  const selectTextbook = useCallback((id: string) => {
    if (textbooks.some((item) => item.textbook.id === id)) activateTextbook(id)
  }, [activateTextbook, textbooks])

  const importTextbook = useCallback(async (file: File) => {
    setUploadError('')
    let text: string
    try {
      text = await file.text()
    } catch {
      setUploadError('读取文件失败，请选择可读取的 JSON 文件。')
      return
    }
    const parsed = parseTextbookJson(text, textbooks.map((item) => item.textbook.id))
    if (!parsed.success) {
      setUploadError(parsed.errors.join(' '))
      return
    }
    const emptyLessons = parsed.data.textbook.lessons.filter(
      (lesson) => !parsed.data.textbook.questions.some((question) => question.lessonId === lesson.id),
    )
    if (emptyLessons.length) {
      setUploadError(`第 ${emptyLessons.map((lesson) => lesson.id).join('、')} 课没有练习题，无法导入。`)
      return
    }
    const saved = saveTextbookPackage(parsed.data)
    if (!saved.success) {
      setUploadError(saved.errors.join(' '))
      return
    }
    setTextbooks((current) => [...current, saved.data])
    setProgressById((current) => ({ ...current, [saved.data.textbook.id]: 0 }))
    activateTextbook(saved.data.textbook.id)
  }, [activateTextbook, textbooks])

  const refreshProgress = useCallback((id: string, questionCounts: number[]) => {
    setProgressById((current) => ({ ...current, [id]: textbookProgress(id, questionCounts) }))
  }, [])

  return { textbooks, selectedTextbook, selectedId, textbookOptions, uploadError, selectTextbook, importTextbook, refreshProgress }
}
