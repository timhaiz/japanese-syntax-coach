import test from 'node:test'
import assert from 'node:assert/strict'
import { createDecipheriv, randomBytes } from 'node:crypto'
import { sealNotification, openNotification } from '../lib/apple/notification-envelope.mjs'

const metadata = Object.freeze({ environment: 'Sandbox', notificationUUID: 'test-id', firstReceivedAt: '2026-01-01T00:00:00.000Z', expiresAt: '2026-01-02T00:00:00.000Z' })

test('round trips and authenticates metadata and ciphertext', () => {
  const key = randomBytes(32)
  const plaintext = Buffer.from('synthetic notification')
  const envelope = sealNotification({ key, keyId: 'test-key', metadata, plaintext })
  assert.deepEqual(openNotification({ key, metadata, envelope }), plaintext)
  assert.throws(() => openNotification({ key, metadata: { ...metadata, expiresAt: '2026-01-03T00:00:00.000Z' }, envelope }))
  const changed = { ...envelope, tag: Buffer.alloc(16).toString('base64url') }
  assert.throws(() => openNotification({ key, metadata, envelope: changed }))
})

test('uses the specified ordered AAD independent of metadata property order', () => {
  const key = randomBytes(32)
  const plaintext = Buffer.from('synthetic')
  const reordered = { expiresAt: metadata.expiresAt, firstReceivedAt: metadata.firstReceivedAt, notificationUUID: metadata.notificationUUID, environment: metadata.environment }
  const envelope = sealNotification({ key, keyId: 'test-key', metadata: reordered, plaintext })
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.nonce, 'base64url'))
  decipher.setAAD(Buffer.from(JSON.stringify([1, 'test-key', metadata.environment, metadata.notificationUUID, metadata.firstReceivedAt, metadata.expiresAt])))
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64url'))
  assert.deepEqual(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64url')), decipher.final()]), plaintext)
  assert.deepEqual(openNotification({ key, metadata, envelope }), plaintext)
})

test('uses fresh nonces and hides plaintext, including empty plaintext round trip', () => {
  const key = randomBytes(32)
  const plaintext = Buffer.from('synthetic secret notification')
  const envelopes = Array.from({ length: 64 }, () => sealNotification({ key, keyId: 'test-key', metadata, plaintext }))
  assert.equal(new Set(envelopes.map(envelope => envelope.nonce)).size, envelopes.length)
  for (const envelope of envelopes) assert.equal(JSON.stringify(envelope).includes(plaintext.toString()), false)
  const empty = sealNotification({ key, keyId: 'test-key', metadata, plaintext: Buffer.alloc(0) })
  assert.deepEqual(openNotification({ key, metadata, envelope: empty }), Buffer.alloc(0))
})

test('rejects wrong keys and tampering of all authenticated fields', () => {
  const key = randomBytes(32)
  const envelope = sealNotification({ key, keyId: 'test-key', metadata, plaintext: Buffer.from('synthetic payload') })
  assert.throws(() => openNotification({ key: randomBytes(32), metadata, envelope }))
  for (const field of ['nonce', 'ciphertext', 'tag']) {
    const bytes = Buffer.from(envelope[field], 'base64url')
    bytes[0] ^= 1
    assert.throws(() => openNotification({ key, metadata, envelope: { ...envelope, [field]: bytes.toString('base64url') } }))
  }
  assert.throws(() => openNotification({ key, metadata, envelope: { ...envelope, keyId: 'other-key' } }))
  for (const field of Object.keys(metadata)) {
    assert.throws(() => openNotification({ key, metadata: { ...metadata, [field]: metadata[field] + 'x' }, envelope }))
  }
  assert.throws(() => openNotification({ key, metadata, envelope: { ...envelope, version: 2 } }))
})

test('rejects invalid or noncanonical encodings and incorrect nonce or tag lengths', () => {
  const key = randomBytes(32)
  const envelope = sealNotification({ key, keyId: 'test-key', metadata, plaintext: Buffer.from('synthetic') })
  for (const field of ['nonce', 'ciphertext', 'tag']) {
    for (const value of ['!', 'AA=', 'A', 'AB', 42]) {
      assert.throws(() => openNotification({ key, metadata, envelope: { ...envelope, [field]: value } }))
    }
  }
  for (const field of ['nonce', 'tag']) {
    assert.throws(() => openNotification({ key, metadata, envelope: { ...envelope, [field]: Buffer.alloc(1).toString('base64url') } }))
  }
})

test('validates inputs and never includes secrets in errors', () => {
  const key = randomBytes(32)
  const plaintext = Buffer.from('synthetic secret notification')
  const envelope = sealNotification({ key, keyId: 'test-key', metadata, plaintext })
  const fail = fn => assert.throws(fn, error => {
    assert.equal(error.message, 'Invalid notification envelope')
    assert.equal(error.message.includes(plaintext.toString()), false)
    assert.equal(error.message.includes(key.toString('hex')), false)
    assert.equal(error.message.includes(key.toString('base64url')), false)
    return true
  })
  for (const badKey of [randomBytes(31), randomBytes(33), key.toString('hex'), null]) {
    fail(() => sealNotification({ key: badKey, keyId: 'test-key', metadata, plaintext }))
    fail(() => openNotification({ key: badKey, metadata, envelope }))
  }
  for (const keyId of ['', 'x'.repeat(129), 'invalid key', 'é', null]) fail(() => sealNotification({ key, keyId, metadata, plaintext }))
  for (const field of Object.keys(metadata)) {
    const missing = { ...metadata }
    delete missing[field]
    for (const invalid of [missing, { ...metadata, [field]: '' }, { ...metadata, [field]: 'x'.repeat(1025) }, { ...metadata, [field]: 1 }]) {
      fail(() => sealNotification({ key, keyId: 'test-key', metadata: invalid, plaintext }))
      fail(() => openNotification({ key, metadata: invalid, envelope }))
    }
  }
  for (const extra of [Object.defineProperty({ ...metadata }, 'extra', { value: 'x' }), { ...metadata, [Symbol('extra')]: 'x' }]) {
    fail(() => sealNotification({ key, keyId: 'test-key', metadata: extra, plaintext }))
    fail(() => openNotification({ key, metadata: extra, envelope }))
  }
  fail(() => sealNotification({ key, keyId: 'test-key', metadata: { ...metadata, extra: 'x' }, plaintext }))
  fail(() => sealNotification({ key, keyId: 'test-key', metadata, plaintext: plaintext.toString() }))
  fail(() => openNotification({ key, metadata, envelope: { ...envelope, tag: Buffer.alloc(16).toString('base64url') } }))
  fail(() => openNotification())
})
