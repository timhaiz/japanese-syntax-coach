import { createHash } from 'node:crypto'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import type { TextbookPackage } from '@/lib/textbooks'

export type TtsJob = {
  id: string
  userId: string
  textbookId: string
  total: number
  completed: number
  status: 'queued' | 'running' | 'completed' | 'failed'
  error?: string
}

type TtsManifest = {
  provider: 'voicevox'
  speaker: number
  sentences: Record<string, string>
}

const jobs = new Map<string, TtsJob>()
const validSegment = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

const rootDirectory = () =>
  path.resolve(process.env.VOICEVOX_AUDIO_DIR || path.join(process.cwd(), 'data', 'tts'))

const jobFile = (jobId: string) => {
  if (!/^[a-z0-9-]{8,80}$/.test(jobId)) throw new Error('Invalid job ID')
  return path.join(rootDirectory(), 'jobs', `${jobId}.json`)
}

const persistJob = async (job: TtsJob) => {
  await mkdir(path.join(rootDirectory(), 'jobs'), { recursive: true })
  await writeFile(jobFile(job.id), `${JSON.stringify(job, null, 2)}\n`)
}

const sentenceList = (textbook: TextbookPackage['textbook']) =>
  [...new Set(textbook.lessons.flatMap((lesson) =>
    lesson.grammar
      .map((point) => point.example.trim())
      .filter(Boolean),
  ))]

const directoryFor = (userId: string, textbookId: string) => {
  if (!validSegment.test(userId) || !validSegment.test(textbookId)) throw new Error('Invalid audio path')
  return path.join(rootDirectory(), userId, textbookId)
}

const fileForSentence = (sentence: string) => `${createHash('sha256').update(sentence).digest('hex').slice(0, 16)}.wav`

export async function getTtsJob(jobId: string) {
  const memoryJob = jobs.get(jobId)
  if (memoryJob) return memoryJob
  try {
    return JSON.parse(await readFile(jobFile(jobId), 'utf8')) as TtsJob
  } catch {
    return null
  }
}

export function getTtsDirectory(userId: string, textbookId: string) {
  return directoryFor(userId, textbookId)
}

export async function deleteUserTtsData(userId: string) {
  if (!validSegment.test(userId)) throw new Error('Invalid user path')
  await rm(path.join(rootDirectory(), userId), { recursive: true, force: true })
}

export async function readTtsManifest(userId: string, textbookId: string): Promise<TtsManifest | null> {
  try {
    const value = JSON.parse(await readFile(path.join(directoryFor(userId, textbookId), 'manifest.json'), 'utf8')) as TtsManifest
    if (value.provider !== 'voicevox' || !value.sentences || typeof value.sentences !== 'object') return null
    return value
  } catch {
    return null
  }
}

export function queueTtsGeneration(userId: string, textbook: TextbookPackage['textbook']) {
  const sentences = sentenceList(textbook)
  const id = `${Date.now().toString(36)}-${createHash('sha256').update(`${userId}:${textbook.id}:${Date.now()}`).digest('hex').slice(0, 10)}`
  const job: TtsJob = { id, userId, textbookId: textbook.id, total: sentences.length, completed: 0, status: 'queued' }
  jobs.set(id, job)
  void persistJob(job)
  void generateTts(job, textbook, sentences)
  return job
}

async function generateTts(job: TtsJob, textbook: TextbookPackage['textbook'], sentences: string[]) {
  job.status = 'running'
  await persistJob(job)
  const engineUrl = (process.env.VOICEVOX_URL || 'http://127.0.0.1:50021').replace(/\/$/, '')
  const speaker = Number(process.env.VOICEVOX_SPEAKER || 3)
  const directory = directoryFor(job.userId, textbook.id)
  const manifest: TtsManifest = { provider: 'voicevox', speaker, sentences: {} }
  try {
    await mkdir(directory, { recursive: true })
    const health = await fetch(`${engineUrl}/version`)
    if (!health.ok) throw new Error(`VOICEVOX Engine 返回 ${health.status}`)

    for (const sentence of sentences) {
      const filename = fileForSentence(sentence)
      const queryUrl = new URL(`${engineUrl}/audio_query`)
      queryUrl.searchParams.set('text', sentence)
      queryUrl.searchParams.set('speaker', String(speaker))
      const queryResponse = await fetch(queryUrl, { method: 'POST' })
      if (!queryResponse.ok) throw new Error(`audio_query 返回 ${queryResponse.status}`)
      const synthesisResponse = await fetch(`${engineUrl}/synthesis?speaker=${speaker}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: await queryResponse.text(),
      })
      if (!synthesisResponse.ok) throw new Error(`synthesis 返回 ${synthesisResponse.status}`)
      await writeFile(path.join(directory, filename), Buffer.from(await synthesisResponse.arrayBuffer()))
      manifest.sentences[sentence] = `/api/tts/audio?textbookId=${encodeURIComponent(textbook.id)}&file=${filename}`
      job.completed += 1
      await persistJob(job)
    }
    await writeFile(path.join(directory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
    job.status = 'completed'
    await persistJob(job)
  } catch (error) {
    job.status = 'failed'
    job.error = error instanceof Error ? error.message : String(error)
    await persistJob(job)
  }
}
