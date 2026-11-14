const isDecimal = (value) => /^(0|[1-9]\d*)$/.test(value)

export async function readBoundedJsonRequest(request, maxBytes) {
  if (
    !Number.isSafeInteger(maxBytes) ||
    maxBytes <= 0 ||
    !request?.body?.getReader ||
    !request.headers?.get
  ) {
    return { ok: false, kind: 'invalid_json' }
  }

  const declaredLength = request.headers.get('content-length')
  if (
    declaredLength !== null &&
    isDecimal(declaredLength) &&
    BigInt(declaredLength) > BigInt(maxBytes)
  ) {
    return { ok: false, kind: 'too_large' }
  }

  const reader = request.body.getReader()
  const chunks = []
  let totalBytes = 0
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      if (!(value instanceof Uint8Array)) return { ok: false, kind: 'invalid_json' }
      totalBytes += value.byteLength
      if (totalBytes > maxBytes) {
        await reader.cancel().catch(() => {})
        return { ok: false, kind: 'too_large' }
      }
      chunks.push(value)
    }
  } catch {
    return { ok: false, kind: 'invalid_json' }
  } finally {
    reader.releaseLock()
  }

  try {
    const buffer = Buffer.concat(chunks, totalBytes)
    const text = new TextDecoder('utf-8', { fatal: true }).decode(buffer)
    return { ok: true, value: JSON.parse(text) }
  } catch {
    return { ok: false, kind: 'invalid_json' }
  }
}
