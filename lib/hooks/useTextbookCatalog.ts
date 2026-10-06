import { useCallback, useEffect, useMemo, useState } from 'react'
import { getSupabaseBrowser } from '@/lib/supabase'
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

const scopedSelectedKey = (scope: string) => `${SELECTED_TEXTBOOK_KEY}:${scope || 'anonymous'}`

export function useTextbookCatalog() {
  const [textbooks, setTextbooks] = useState<TextbookPackage[]>([builtInTextbookPackage])
  const [selectedId, setSelectedId] = useState(builtInTextbookPackage.textbook.id)
  const [storageScope, setStorageScope] = useState<string | null>(null)
  const [uploadError, setUploadError] = useState('')
  const [uploadNotice, setUploadNotice] = useState('')
  const [progressById, setProgressById] = useState<Record<string, number>>({})

  useEffect(() => {
    const supabase = getSupabaseBrowser()
    if (!supabase) {
      setStorageScope('anonymous')
      return
    }
    let mounted = true
    const applyScope = (scope: string) => {
      if (mounted) setStorageScope(scope || 'anonymous')
    }
    void supabase.auth.getUser().then(({ data }) => applyScope(data.user?.id ?? 'anonymous'))
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      applyScope(session?.user?.id ?? 'anonymous')
    })
    return () => {
      mounted = false
      data.subscription.unsubscribe()
    }
  }, [])

  useEffect(() => {
    if (!storageScope) return
    const available = [builtInTextbookPackage, ...getStoredTextbookPackages(storageScope)]
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
      const savedId = localStorage.getItem(scopedSelectedKey(storageScope))
      if (savedId && available.some((item) => item.textbook.id === savedId)) setSelectedId(savedId)
      else setSelectedId(builtInTextbookPackage.textbook.id)
    } catch {
      // Keep the built-in textbook active when browser storage is unavailable.
    }
  }, [storageScope])

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
    setUploadNotice('')
    try {
      localStorage.setItem(scopedSelectedKey(storageScope ?? 'anonymous'), id)
    } catch {
      // The active choice remains valid for the current tab.
    }
  }, [storageScope])

  const selectTextbook = useCallback((id: string) => {
    if (textbooks.some((item) => item.textbook.id === id)) activateTextbook(id)
  }, [activateTextbook, textbooks])

  const importTextbook = useCallback(async (file: File) => {
    setUploadError('')
    if (!storageScope) {
      setUploadError('正在确认当前账号，请稍后再导入教材。')
      return
    }
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
    const saved = saveTextbookPackage(parsed.data, storageScope)
    if (!saved.success) {
      setUploadError(saved.errors.join(' '))
      return
    }
    setTextbooks((current) => [...current, saved.data])
    setProgressById((current) => ({ ...current, [saved.data.textbook.id]: 0 }))
    activateTextbook(saved.data.textbook.id)

    try {
      const response = await fetch('/api/tts/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ textbook: saved.data }),
      })
      const payload = (await response.json().catch(() => ({}))) as {
        job?: { id?: string; total?: number }
        error?: string
      }
      if (response.status === 202) {
        const jobId = payload.job?.id
        const total = payload.job?.total ?? 0
        setUploadNotice(`教材已导入，正在生成 ${total} 条例句语音。`)
        if (jobId) {
          void (async () => {
            for (let attempt = 0; attempt < 120; attempt += 1) {
              await new Promise((resolve) => window.setTimeout(resolve, 2000))
              const statusResponse = await fetch(`/api/tts/generate?jobId=${encodeURIComponent(jobId)}`, { cache: 'no-store' })
              const statusPayload = (await statusResponse.json().catch(() => ({}))) as {
                job?: { status?: string; completed?: number; total?: number; error?: string }
              }
              const status = statusPayload.job
              if (!status) return
              if (status.status === 'completed') {
                setUploadNotice(`例句语音已生成，共 ${status.total ?? total} 条。`)
                return
              }
              if (status.status === 'failed') {
                setUploadNotice(`教材已导入，但语音生成失败：${status.error || '请稍后重试。'}`)
                return
              }
              setUploadNotice(`正在生成例句语音：${status.completed ?? 0} / ${status.total ?? total}`)
            }
            setUploadNotice('语音生成仍在后台进行，完成后即可播放。')
          })()
        }
      } else if (response.status === 403) {
        setUploadNotice('教材已导入。例句语音生成为会员功能，当前账号暂未开放。')
      } else if (!response.ok) {
        setUploadNotice(`教材已导入，但语音任务未创建：${payload.error || '服务器暂时不可用。'}`)
      }
    } catch {
      setUploadNotice('教材已导入，但语音服务器暂时无法连接；之后可重新导入生成。')
    }
  }, [activateTextbook, storageScope, textbooks])

  const refreshProgress = useCallback((id: string, questionCounts: number[]) => {
    setProgressById((current) => ({ ...current, [id]: textbookProgress(id, questionCounts) }))
  }, [])

  return { textbooks, selectedTextbook, selectedId, textbookOptions, uploadError, uploadNotice, selectTextbook, importTextbook, refreshProgress }
}
