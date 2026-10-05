export type TtsManifest = {
  provider: 'voicevox'
  speaker: number
  sentences: Record<string, string>
}

const manifestCache = new Map<string, Promise<TtsManifest | null>>()

const loadManifest = (textbookId: string): Promise<TtsManifest | null> => {
  const cached = manifestCache.get(textbookId)
  if (cached) return cached

  const request = fetch(`/audio/grammar/${encodeURIComponent(textbookId)}/manifest.json`, {
    cache: 'force-cache',
  })
    .then(async (response) => {
      if (!response.ok) return null
      const value = (await response.json()) as Partial<TtsManifest>
      if (value.provider !== 'voicevox' || !value.sentences || typeof value.sentences !== 'object') {
        return null
      }
      return value as TtsManifest
    })
    .catch(() => null)

  manifestCache.set(textbookId, request)
  return request
}

export async function resolveGeneratedAudio(
  text: string,
  textbookId: string,
  explicitAudio?: string,
): Promise<string | undefined> {
  if (explicitAudio) return explicitAudio
  const manifest = await loadManifest(textbookId)
  return manifest?.sentences[text.trim()]
}
