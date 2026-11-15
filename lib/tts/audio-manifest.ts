export type TtsManifest = {
  provider: 'voicevox' | 'minimax'
  speaker?: number
  voice?: string
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

  const builtIn = textbookId === 'builtin-japanese-syntax'
  const staticUrl = `/audio/grammar/${encodeURIComponent(textbookId)}/manifest.json`
  const apiUrl = `/api/tts/manifest?textbookId=${encodeURIComponent(textbookId)}`
  const request = fetch(builtIn ? staticUrl : apiUrl, {
    cache: builtIn ? 'force-cache' : 'no-store',
  })
    .catch(() => null)
    .then(async (response) => {
      if (!response?.ok) {
        return fetch(builtIn ? apiUrl : staticUrl, {
          cache: builtIn ? 'no-store' : 'force-cache',
        })
      }
      return response
    })
    .then(async (response) => {
      if (!response.ok) return null
      const value = (await response.json()) as Partial<TtsManifest>
      if (
        (value.provider !== 'voicevox' && value.provider !== 'minimax') ||
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
