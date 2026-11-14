export type TtsClientRequestStore = {
  save(scope: string, textbookId: string, requestId: string): void
  get(scope: string, textbookId: string): string | null
  remove(scope: string, textbookId: string, requestId: string): void
}

type StorageLike = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

const STORAGE_KEY = 'japanese-syntax-coach:tts-request:v1'
const keyFor = (scope: string, textbookId: string) =>
  `${STORAGE_KEY}:${encodeURIComponent(scope)}:${encodeURIComponent(textbookId)}`

export function createTtsClientRequestStore(storage?: StorageLike): TtsClientRequestStore {
  const currentStorage = () => storage ?? globalThis.localStorage
  return {
    save(scope, textbookId, requestId) {
      currentStorage().setItem(keyFor(scope, textbookId), requestId)
    },
    get(scope, textbookId) {
      return currentStorage().getItem(keyFor(scope, textbookId))
    },
    remove(scope, textbookId, requestId) {
      const key = keyFor(scope, textbookId)
      const target = currentStorage()
      if (target.getItem(key) === requestId) target.removeItem(key)
    },
  }
}
