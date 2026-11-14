import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import vm from 'node:vm'

const source = await readFile(new URL('../lib/tts/audio-manifest.ts', import.meta.url), 'utf8')
const pending = []
const context = vm.createContext({
  Map,
  Promise,
  encodeURIComponent,
  fetch: () => new Promise((resolve) => pending.push(resolve)),
})
const module = new vm.SourceTextModule(stripTypeScriptTypes(source), { context })
await module.link(() => {
  throw new Error('Unexpected import')
})
await module.evaluate()
const { clearTtsManifestCache, resolveGeneratedAudio, setTtsManifestScope } = module.namespace

const response = (manifest) => ({ ok: true, json: async () => manifest })

test('clearing the manifest cache prevents a late old request from evicting a new one', async () => {
  const oldRequest = resolveGeneratedAudio('hello', 'book-1')
  clearTtsManifestCache()
  const currentRequest = resolveGeneratedAudio('hello', 'book-1')
  assert.equal(pending.length, 2)

  pending[0](response({ provider: 'other', sentences: {} }))
  assert.equal(await oldRequest, undefined)
  pending[1](
    response({ provider: 'voicevox', speaker: 3, sentences: { hello: '/audio/current.wav' } }),
  )
  assert.equal(await currentRequest, '/audio/current.wav')
  assert.equal(await resolveGeneratedAudio('hello', 'book-1'), '/audio/current.wav')
  assert.equal(pending.length, 2)
})

test('manifest cache is partitioned by authenticated scope and textbook', async () => {
  setTtsManifestScope('user-1')
  const firstUser = resolveGeneratedAudio('hello', 'shared-book')
  setTtsManifestScope('user-2')
  const secondUser = resolveGeneratedAudio('hello', 'shared-book')
  assert.equal(pending.length, 4)

  pending[2](
    response({ provider: 'voicevox', speaker: 3, sentences: { hello: '/audio/user-1.wav' } }),
  )
  pending[3](
    response({ provider: 'voicevox', speaker: 3, sentences: { hello: '/audio/user-2.wav' } }),
  )
  assert.equal(await firstUser, '/audio/user-1.wav')
  assert.equal(await secondUser, '/audio/user-2.wav')
})
