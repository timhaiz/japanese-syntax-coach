import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getSupabaseBrowser } from '@/lib/supabase'
import { builtInTextbookPackage, type TextbookPackage } from '@/lib/textbooks'
import beginnerLowerPackage from '@/docs/textbooks/shin-standard-japanese-beginner-lower.json'
import intermediateLowerPackage from '@/docs/textbooks/shin-standard-japanese-intermediate-lower.json'
import intermediateUpperPackage from '@/docs/textbooks/shin-standard-japanese-intermediate-upper.json'

const freeTextbookPackages: TextbookPackage[] = [
  beginnerLowerPackage as unknown as TextbookPackage,
  intermediateLowerPackage as unknown as TextbookPackage,
  intermediateUpperPackage as unknown as TextbookPackage,
]
import {
  getStoredTextbookPackages,
  parseTextbookJson,
  saveTextbookPackage,
} from '@/lib/textbook-import'
import { textbookProgress } from '@/lib/textbook-progress'
import { createTtsClientRequestStore } from '@/lib/tts/client-request-store'
import { clearTtsManifestCache, setTtsManifestScope } from '@/lib/tts/audio-manifest'

const SELECTED_TEXTBOOK_KEY = 'japanese-syntax-coach:selected-textbook:v1'
const ttsRequestStore = createTtsClientRequestStore()
const scopedSelectedKey = (scope: string) => `${SELECTED_TEXTBOOK_KEY}:${scope || 'anonymous'}`
const activeRequestKey = (scope: string, textbookId: string) => JSON.stringify([scope, textbookId])

function createRequestId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export function useTextbookCatalog() {
  const [textbooks, setTextbooks] = useState<TextbookPackage[]>([builtInTextbookPackage])
  const [selectedId, setSelectedId] = useState(builtInTextbookPackage.textbook.id)
  const [storageScope, setStorageScope] = useState<string | null>(null)
  const [textbooksScope, setTextbooksScope] = useState<string | null>(null)
  const [uploadError, setUploadError] = useState('')
  const [uploadNotice, setUploadNotice] = useState('')
  const [progressById, setProgressById] = useState<Record<string, number>>({})
  const activeRequests = useRef(new Set<string>())

  const runTtsRequest = useCallback(
    (scope: string, textbook: TextbookPackage, requestId: string) => {
      const textbookId = textbook.textbook.id
      const activeKey = activeRequestKey(scope, textbookId)
      if (activeRequests.current.has(activeKey)) return
      activeRequests.current.add(activeKey)

      void (async () => {
        try {
          const response = await fetch('/api/tts/generate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Idempotency-Key': requestId },
            body: JSON.stringify({ textbook }),
          })
          const payload = (await response.json().catch(() => ({}))) as {
            job?: { id?: string; total?: number }
            error?: string
          }
          if (response.status === 403) {
            setUploadNotice('教材已导入。例句语音生成为会员功能，当前账号暂未开放。')
            return
          }
          if (response.status !== 202 || !payload.job?.id) {
            setUploadNotice(
              `教材已导入，但语音任务未创建：${payload.error || '服务器暂时不可用。'}`,
            )
            return
          }

          const jobId = payload.job.id
          const total = payload.job.total ?? 0
          setUploadNotice(`教材已导入，正在生成 ${total} 条例句语音。`)
          for (let attempt = 0; attempt < 120; attempt += 1) {
            await new Promise((resolve) => window.setTimeout(resolve, 2000))
            const statusResponse = await fetch(
              `/api/tts/generate?jobId=${encodeURIComponent(jobId)}`,
              { cache: 'no-store' },
            )
            const statusPayload = (await statusResponse.json().catch(() => ({}))) as {
              job?: { status?: string; completed?: number; total?: number; errorCode?: string }
            }
            const status = statusPayload.job
            if (!status) {
              setUploadNotice('教材语音任务状态暂时无法读取，稍后会继续恢复。')
              return
            }
            if (status.status === 'succeeded' || status.status === 'completed') {
              ttsRequestStore.remove(scope, textbookId, requestId)
              setUploadNotice(`例句语音已生成，共 ${status.total ?? total} 条。`)
              return
            }
            if (status.status === 'failed') {
              ttsRequestStore.remove(scope, textbookId, requestId)
              setUploadNotice(`教材已导入，但语音生成失败：${status.errorCode || '请稍后重试。'}`)
              return
            }
            setUploadNotice(`正在生成例句语音：${status.completed ?? 0} / ${status.total ?? total}`)
          }
          setUploadNotice('语音生成仍在后台进行，完成后即可恢复查看。')
        } catch {
          setUploadNotice('教材已导入，但语音任务暂时无法连接；请求身份已保留，可稍后恢复。')
        } finally {
          activeRequests.current.delete(activeKey)
        }
      })()
    },
    [],
  )

  useEffect(() => {
    const supabase = getSupabaseBrowser()
    if (!supabase) {
      setStorageScope('anonymous')
      return
    }
    let mounted = true
    const applyScope = (scope: string) => {
      const nextScope = scope || 'anonymous'
      setTtsManifestScope(nextScope)
      clearTtsManifestCache()
      if (mounted) setStorageScope(nextScope)
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
    const available = [
      builtInTextbookPackage,
      ...freeTextbookPackages,
      ...getStoredTextbookPackages(storageScope),
    ]
    setTextbooks(available)
    setTextbooksScope(storageScope)
    setProgressById(
      Object.fromEntries(
        available.map(({ textbook }) => [
          textbook.id,
          textbookProgress(
            textbook.id,
            textbook.lessons.map(
              (lesson) =>
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

  useEffect(() => {
    if (!storageScope || textbooksScope !== storageScope) return
    for (const textbook of textbooks) {
      try {
        const requestId = ttsRequestStore.get(storageScope, textbook.textbook.id)
        if (requestId) runTtsRequest(storageScope, textbook, requestId)
      } catch {
        setUploadNotice('无法读取本地语音任务状态；请检查浏览器存储设置。')
        return
      }
    }
  }, [runTtsRequest, storageScope, textbooks, textbooksScope])

  const selectedTextbook = useMemo(
    () => textbooks.find((item) => item.textbook.id === selectedId) ?? builtInTextbookPackage,
    [selectedId, textbooks],
  )

  const textbookOptions = useMemo(
    () =>
      textbooks.map(({ textbook }) => ({
        id: textbook.id,
        title: textbook.title,
        shortTitle:
          textbook.shortTitle ||
          (textbook.title.length > 12 ? `${textbook.title.slice(0, 12)}…` : textbook.title),
        cover: textbook.cover,
        progress: progressById[textbook.id] ?? 0,
        builtIn: textbook.id === builtInTextbookPackage.textbook.id,
      })),
    [progressById, textbooks],
  )

  const activateTextbook = useCallback(
    (id: string) => {
      setSelectedId(id)
      setUploadError('')
      setUploadNotice('')
      try {
        localStorage.setItem(scopedSelectedKey(storageScope ?? 'anonymous'), id)
      } catch {
        // The active choice remains valid for the current tab.
      }
    },
    [storageScope],
  )

  const selectTextbook = useCallback(
    (id: string) => {
      if (textbooks.some((item) => item.textbook.id === id)) activateTextbook(id)
    },
    [activateTextbook, textbooks],
  )

  const importTextbook = useCallback(
    async (file: File) => {
      setUploadError('')
      if (!storageScope || textbooksScope !== storageScope) {
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
      const parsed = parseTextbookJson(
        text,
        textbooks.map((item) => item.textbook.id),
      )
      if (!parsed.success) {
        setUploadError(parsed.errors.join(' '))
        return
      }
      const emptyLessons = parsed.data.textbook.lessons.filter(
        (lesson) =>
          !parsed.data.textbook.questions.some((question) => question.lessonId === lesson.id),
      )
      if (emptyLessons.length) {
        setUploadError(
          `第 ${emptyLessons.map((lesson) => lesson.id).join('、')} 课没有练习题，无法导入。`,
        )
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

      let requestId: string | null
      try {
        requestId = ttsRequestStore.get(storageScope, saved.data.textbook.id)
        if (!requestId) {
          requestId = createRequestId()
          ttsRequestStore.save(storageScope, saved.data.textbook.id, requestId)
        }
      } catch {
        setUploadNotice('教材已导入，但无法安全保存语音请求身份；未提交语音任务。')
        return
      }
      runTtsRequest(storageScope, saved.data, requestId)
    },
    [activateTextbook, runTtsRequest, storageScope, textbooks, textbooksScope],
  )

  const refreshProgress = useCallback((id: string, questionCounts: number[]) => {
    setProgressById((current) => ({ ...current, [id]: textbookProgress(id, questionCounts) }))
  }, [])

  return {
    textbooks,
    selectedTextbook,
    selectedId,
    textbookOptions,
    uploadError,
    uploadNotice,
    selectTextbook,
    importTextbook,
    refreshProgress,
  }
}
