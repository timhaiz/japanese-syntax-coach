export type TtsManifest = {
  provider: 'voicevox'
  speaker: number
  sentences: Record<string, string>
}

const manifestCache = new Map<string, Promise<TtsManifest | null>>()
let manifestScope = 'anonymous'
const manifestKey = (textbookId: string) => JSON.stringify([manifestScope, textbookId])

export function clearTtsManifestCache() {
  manifestCache.clear()
}

export function setTtsManifestScope(scope: string) {
  const nextScope = scope || 'anonymous'
  if (manifestScope !== nextScope) manifestCache.clear()
  manifestScope = nextScope
}

const loadManifest = (textbookId: string): Promise<TtsManifest | null> => {
  const cacheKey = manifestKey(textbookId)
  const cached = manifestCache.get(cacheKey)
  if (cached) return cached

  const request = fetch(`/api/tts/manifest?textbookId=${encodeURIComponent(textbookId)}`, {
    cache: 'no-store',
  })
    .catch(() => null)
    .then(async (response) => {
      if (!response?.ok) {
        return fetch(`/audio/grammar/${encodeURIComponent(textbookId)}/manifest.json`, {
          cache: 'force-cache',
        })
      }
      return response
    })
    .then(async (response) => {
      if (!response.ok) return null
      const value = (await response.json()) as Partial<TtsManifest>
      if (
        value.provider !== 'voicevox' ||
        !value.sentences ||
        typeof value.sentences !== 'object'
      ) {
        return null
      }
      return value as TtsManifest
    })
    .catch(() => null)

  request.then((manifest) => {
    if (!manifest && manifestCache.get(cacheKey) === request) manifestCache.delete(cacheKey)
  })

  manifestCache.set(cacheKey, request)
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
