import { readFile, rm } from 'node:fs/promises'
import path from 'node:path'

type TtsManifest = {
  provider: 'voicevox'
  speaker: number
  sentences: Record<string, string>
}

const validSegment = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

const rootDirectory = () =>
  path.resolve(process.env.VOICEVOX_AUDIO_DIR || path.join(process.cwd(), 'data', 'tts'))

const directoryFor = (userId: string, textbookId: string) => {
  if (!validSegment.test(userId) || !validSegment.test(textbookId)) throw new Error('Invalid audio path')
  return path.join(rootDirectory(), userId, textbookId)
}

export function getTtsRepository() {
  return null
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
