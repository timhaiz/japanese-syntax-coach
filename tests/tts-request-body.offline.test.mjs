import test from 'node:test'
import assert from 'node:assert/strict'
import { readBoundedJsonRequest } from '../lib/tts/request-body.mjs'

const requestWith = (chunks, headers = {}) => {
  let cancelled = false
  let index = 0
  const request = {
    headers: new Headers(headers),
    body: new ReadableStream({
      pull(controller) {
        if (index === chunks.length) controller.close()
        else controller.enqueue(chunks[index++])
      },
      cancel() {
        cancelled = true
      },
    }),
  }
  return { request, wasCancelled: () => cancelled }
}

const bytes = (text) => new TextEncoder().encode(text)

test('accepts a body exactly at the byte limit without requiring Content-Length', async () => {
  const text = JSON.stringify({ value: 'x'.repeat(10) })
  const { request } = requestWith([bytes(text)])
  assert.deepEqual(await readBoundedJsonRequest(request, bytes(text).byteLength), {
    ok: true,
    value: { value: 'x'.repeat(10) },
  })
})

test('rejects an oversized declared body without consuming the stream', async () => {
  const { request } = requestWith([bytes('{"ok":true}')], { 'Content-Length': '12' })
  const result = await readBoundedJsonRequest(request, 11)
  assert.deepEqual(result, { ok: false, kind: 'too_large' })
  assert.equal(request.body.locked, false)
})

test('rejects streamed bytes above the limit even when Content-Length is absent or understated', async () => {
  for (const headers of [{}, { 'Content-Length': '2' }]) {
    const { request, wasCancelled } = requestWith(
      [bytes('{"value":"'), bytes('too long"}')],
      headers,
    )
    assert.deepEqual(await readBoundedJsonRequest(request, 10), { ok: false, kind: 'too_large' })
    assert.equal(wasCancelled(), true)
  }
})

test('accepts a valid JSON body when Content-Length is overstated but remains under the limit', async () => {
  const { request } = requestWith([bytes('{"ok":true}')], { 'Content-Length': '15' })
  assert.deepEqual(await readBoundedJsonRequest(request, 20), { ok: true, value: { ok: true } })
})

test('rejects missing bodies and malformed JSON as invalid_json', async () => {
  assert.deepEqual(await readBoundedJsonRequest({ headers: new Headers(), body: null }, 20), {
    ok: false,
    kind: 'invalid_json',
  })
  const { request } = requestWith([bytes('{')])
  assert.deepEqual(await readBoundedJsonRequest(request, 20), { ok: false, kind: 'invalid_json' })
})

test('rejects malformed UTF-8 rather than replacing invalid bytes', async () => {
  const { request } = requestWith([Uint8Array.of(0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d)])
  assert.deepEqual(await readBoundedJsonRequest(request, 20), { ok: false, kind: 'invalid_json' })
})

test('rejects malformed Content-Length without trusting it to bypass the stream cap', async () => {
  const { request } = requestWith([bytes('{"ok":true}')], { 'Content-Length': 'not-a-number' })
  assert.deepEqual(await readBoundedJsonRequest(request, 20), { ok: true, value: { ok: true } })
})
