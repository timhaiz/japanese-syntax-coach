import { createHash } from 'node:crypto'
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import type { TextbookPackage } from '@/lib/textbooks'

export type TtsJob = {
  id: string
  userId: string
  textbookId: string
  total: number
  completed: number
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'
  error?: string
}

type TtsManifest = {
  provider: 'voicevox'
  speaker: number
  sentences: Record<string, string>
}

const jobs = new Map<string, TtsJob>()
const runningJobs = new Map<string, Promise<void>>()
const jobWriteChains = new Map<string, Promise<void>>()
const deletingUsers = new Set<string>()
const jobControllers = new Map<string, AbortController>()
const validSegment = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

const rootDirectory = () =>
  path.resolve(process.env.VOICEVOX_AUDIO_DIR || path.join(process.cwd(), 'data', 'tts'))

const jobFile = (jobId: string) => {
  if (!/^[a-z0-9-]{8,80}$/.test(jobId)) throw new Error('Invalid job ID')
  return path.join(rootDirectory(), 'jobs', `${jobId}.json`)
}

const persistJob = async (job: TtsJob) => {
  const previous = jobWriteChains.get(job.id) ?? Promise.resolve()
  const current = previous.catch(() => undefined).then(async () => {
    await mkdir(path.join(rootDirectory(), 'jobs'), { recursive: true })
    await writeFile(jobFile(job.id), `${JSON.stringify(job, null, 2)}\n`)
  })
  jobWriteChains.set(job.id, current)
  try {
    await current
  } finally {
    if (jobWriteChains.get(job.id) === current) jobWriteChains.delete(job.id)
  }
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

export function releaseUserTtsDeletion(userId: string) {
  deletingUsers.delete(userId)
}

export async function cancelUserTtsJobs(userId: string) {
  deletingUsers.add(userId)
  const pending: Promise<void>[] = []
  for (const job of jobs.values()) {
    if (job.userId !== userId) continue
    jobControllers.get(job.id)?.abort()
    if (job.status !== 'completed' && job.status !== 'failed' && job.status !== 'cancelled') {
      job.status = 'cancelled'
      pending.push(persistJob(job))
    }
    const running = runningJobs.get(job.id)
    if (running) pending.push(running)
  }
  const results = await Promise.allSettled(pending)
  const failedWrite = results.find((result) => result.status === 'rejected')
  if (failedWrite?.status === 'rejected') throw failedWrite.reason
}

export async function deleteUserTtsData(userId: string) {
  if (!validSegment.test(userId)) throw new Error('Invalid user path')
  await rm(path.join(rootDirectory(), userId), { recursive: true, force: true })
  const jobsDirectory = path.join(rootDirectory(), 'jobs')
  const entries = await readdir(jobsDirectory).catch(() => [])
  await Promise.all(entries
    .filter((entry) => entry.endsWith('.json'))
    .map(async (entry) => {
      const file = path.join(jobsDirectory, entry)
      try {
        const job = JSON.parse(await readFile(file, 'utf8')) as TtsJob
        if (job.userId === userId) await rm(file, { force: true })
      } catch {
        // Ignore malformed or concurrently removed job records.
      }
    }))
  for (const [jobId, job] of jobs) {
    if (job.userId === userId) jobs.delete(jobId)
  }
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

export function isValidTtsTextbookId(textbookId: string) {
  return validSegment.test(textbookId)
}

export async function queueTtsGeneration(userId: string, textbook: TextbookPackage['textbook']) {
  if (deletingUsers.has(userId)) throw new Error('Account deletion is in progress')
  const sentences = sentenceList(textbook)
  const id = `${Date.now().toString(36)}-${createHash('sha256').update(`${userId}:${textbook.id}:${Date.now()}`).digest('hex').slice(0, 10)}`
  const job: TtsJob = { id, userId, textbookId: textbook.id, total: sentences.length, completed: 0, status: 'queued' }
  jobs.set(id, job)
  const controller = new AbortController()
  jobControllers.set(id, controller)
  let markReady!: () => void
  let rejectReady!: (error: unknown) => void
  const ready = new Promise<void>((resolve, reject) => {
    markReady = resolve
    rejectReady = reject
  })
  const running = (async () => {
    try {
      await persistJob(job)
      markReady()
      if (isCancelled(job)) return
      await generateTts(job, textbook, sentences, controller.signal)
    } catch (error) {
      jobs.delete(id)
      rejectReady(error)
    }
  })()
  runningJobs.set(id, running)
  void running.then(
    () => { runningJobs.delete(id); jobControllers.delete(id) },
    () => { runningJobs.delete(id); jobControllers.delete(id) },
  )
  await ready
  return job
}

const isCancelled = (job: TtsJob) => job.status === 'cancelled'

async function generateTts(
  job: TtsJob,
  textbook: TextbookPackage['textbook'],
  sentences: string[],
  signal: AbortSignal,
) {
  const engineUrl = (process.env.VOICEVOX_URL || 'http://127.0.0.1:50021').replace(/\/$/, '')
  const speaker = Number(process.env.VOICEVOX_SPEAKER || 3)
  const directory = directoryFor(job.userId, textbook.id)
  const manifest: TtsManifest = { provider: 'voicevox', speaker, sentences: {} }
  try {
    if (isCancelled(job)) return
    job.status = 'running'
    await persistJob(job)
    await mkdir(directory, { recursive: true })
    if (isCancelled(job)) return
    const health = await fetch(`${engineUrl}/version`, { signal })
    if (!health.ok) throw new Error(`VOICEVOX Engine 返回 ${health.status}`)

    for (const sentence of sentences) {
      if (isCancelled(job)) return
      const filename = fileForSentence(sentence)
      const queryUrl = new URL(`${engineUrl}/audio_query`)
      queryUrl.searchParams.set('text', sentence)
      queryUrl.searchParams.set('speaker', String(speaker))
      const queryResponse = await fetch(queryUrl, { method: 'POST', signal })
      if (!queryResponse.ok) throw new Error(`audio_query 返回 ${queryResponse.status}`)
      const synthesisResponse = await fetch(`${engineUrl}/synthesis?speaker=${speaker}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: await queryResponse.text(),
        signal,
      })
      if (!synthesisResponse.ok) throw new Error(`synthesis 返回 ${synthesisResponse.status}`)
      if (isCancelled(job)) return
      await writeFile(path.join(directory, filename), Buffer.from(await synthesisResponse.arrayBuffer()))
      if (isCancelled(job)) return
      manifest.sentences[sentence] = `/api/tts/audio?textbookId=${encodeURIComponent(textbook.id)}&file=${filename}`
      job.completed += 1
      await persistJob(job)
    }
    if (isCancelled(job)) return
    await writeFile(path.join(directory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
    if (isCancelled(job)) return
    job.status = 'completed'
    await persistJob(job)
  } catch (error) {
    if (isCancelled(job)) return
    job.status = 'failed'
    job.error = error instanceof Error ? error.message : String(error)
    try {
      await persistJob(job)
    } catch {
      // The task is already contained; a failed terminal-state write must not reject its detached promise.
    }
  }
}
