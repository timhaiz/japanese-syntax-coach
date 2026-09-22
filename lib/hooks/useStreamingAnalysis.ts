import { useState } from 'react'

export type AnalysisWord = {
  word: string
  kana: string
  meaning: string
  memory: string
}

export type AnalysisResult = {
  analysis?: string
  words?: AnalysisWord[]
  pitfalls?: string[]
  similarQuestions?: { prompt: string; answer: string }[]
  source?: string
}

export function useStreamingAnalysis() {
  const [analysis, setAnalysis] = useState<AnalysisResult | null>(null)
  const [loading, setLoading] = useState(false)
  const [preview, setPreview] = useState('')

  const startAnalysis = async (params: {
    prompt: string
    answer: string
    standardAnswer: string
    hint: string
  }) => {
    setLoading(true)
    setPreview('')
    try {
      const response = await fetch('/api/analyze-answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(params),
      })
      const contentType = response.headers.get('content-type') || ''
      if (!contentType.includes('text/event-stream')) {
        setAnalysis(await response.json())
        return
      }
      const reader = response.body?.getReader()
      if (!reader) throw new Error('stream-unavailable')
      const decoder = new TextDecoder()
      let buffer = ''
      let output = ''
      let streamError = ''
      while (true) {
        const { value, done } = await reader.read()
        buffer += decoder.decode(value || new Uint8Array(), { stream: !done })
        const frames = buffer.split('\n\n')
        buffer = frames.pop() || ''
        for (const frame of frames) {
          const line = frame.split('\n').find((item) => item.startsWith('data: '))
          if (!line) continue
          const event = JSON.parse(line.slice(6)) as { type?: string; text?: string; message?: string }
          if (event.type === 'delta' && event.text) {
            output += event.text
            const match = output.match(/"analysis"\s*:\s*"((?:\\.|[^"\\])*)/)
            if (match) {
              try {
                setPreview(JSON.parse(`"${match[1]}"`))
              } catch {
                // Wait for the next complete JSON escape sequence.
              }
            }
          } else if (event.type === 'error') {
            streamError = event.message || 'stream-error'
          }
        }
        if (done) break
      }
      if (streamError) throw new Error(streamError)
      setAnalysis(JSON.parse(output || '{}'))
    } catch {
      setAnalysis({
        analysis: 'AI 分析暂时不可用，请对照标准答案拆分词语和句型记忆。',
        source: 'fallback',
      })
    } finally {
      setLoading(false)
    }
  }

  const resetAnalysis = () => {
    setAnalysis(null)
    setPreview('')
  }

  return { analysis, loading, preview, startAnalysis, resetAnalysis }
}
