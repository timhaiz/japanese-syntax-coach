import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const source = await readFile(
  new URL('../lib/tts/client-request-store.ts', import.meta.url),
  'utf8',
)
const context = vm.createContext({ encodeURIComponent, JSON })
const module = new vm.SourceTextModule(stripTypeScriptTypes(source), { context })
await module.link(() => {
  throw new Error('Unexpected import')
})
await module.evaluate()
const { createTtsClientRequestStore } = module.namespace

function createStorage() {
  const values = new Map()
  return {
    getItem(key) {
      return values.get(key) ?? null
    },
    setItem(key, value) {
      values.set(key, String(value))
    },
    removeItem(key) {
      values.delete(key)
    },
  }
}

test('persists and retrieves a request UUID across store instances', () => {
  const storage = createStorage()
  createTtsClientRequestStore(storage).save('user-1', 'book-1', 'request-1')
  assert.equal(createTtsClientRequestStore(storage).get('user-1', 'book-1'), 'request-1')
})

test('retains the same request UUID after a simulated network exception', async () => {
  const storage = createStorage()
  const store = createTtsClientRequestStore(storage)
  store.save('user-1', 'book-1', 'request-1')
  await assert.rejects(async () => {
    const requestId = store.get('user-1', 'book-1')
    assert.equal(requestId, 'request-1')
    throw new Error('simulated network exception')
  }, /simulated network exception/)
  assert.equal(createTtsClientRequestStore(storage).get('user-1', 'book-1'), 'request-1')
})

test('keeps request identities isolated by user and textbook', () => {
  const store = createTtsClientRequestStore(createStorage())
  store.save('user-1', 'book-1', 'request-1')
  store.save('user-2', 'book-1', 'request-2')
  store.save('user-1', 'book-2', 'request-3')
  assert.equal(store.get('user-1', 'book-1'), 'request-1')
  assert.equal(store.get('user-2', 'book-1'), 'request-2')
  assert.equal(store.get('user-1', 'book-2'), 'request-3')
})

test('removes only when the stored request ID still matches', () => {
  const store = createTtsClientRequestStore(createStorage())
  store.save('user-1', 'book-1', 'old-request')
  store.save('user-1', 'book-1', 'new-request')
  store.remove('user-1', 'book-1', 'old-request')
  assert.equal(store.get('user-1', 'book-1'), 'new-request')
  store.remove('user-1', 'book-1', 'new-request')
  assert.equal(store.get('user-1', 'book-1'), null)
})
