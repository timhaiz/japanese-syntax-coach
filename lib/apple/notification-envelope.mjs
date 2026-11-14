import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'

const metadataFields = ['environment', 'notificationUUID', 'firstReceivedAt', 'expiresAt']

function validateKey(key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) throw new Error()
}

function associatedData(keyId, metadata) {
  if (typeof keyId !== 'string' || !/^[A-Za-z0-9._-]{1,128}$/.test(keyId)) throw new Error()
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata) ||
      Reflect.ownKeys(metadata).length !== metadataFields.length ||
      !metadataFields.every(field => Object.hasOwn(metadata, field) && typeof metadata[field] === 'string' && metadata[field].length > 0 && metadata[field].length <= 1024)) throw new Error()
  return Buffer.from(JSON.stringify([1, keyId, ...metadataFields.map(field => metadata[field])]), 'utf8')
}

function decode(value, length) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]*$/.test(value)) throw new Error()
  const decoded = Buffer.from(value, 'base64url')
  if (decoded.toString('base64url') !== value || (length !== undefined && decoded.length !== length)) throw new Error()
  return decoded
}

export function sealNotification(input) {
  try {
    const { key, keyId, metadata, plaintext } = input
    validateKey(key)
    if (!Buffer.isBuffer(plaintext)) throw new Error()
    const aad = associatedData(keyId, metadata)
    const nonce = randomBytes(12)
    const cipher = createCipheriv('aes-256-gcm', key, nonce)
    cipher.setAAD(aad)
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()])
    return { version: 1, keyId, nonce: nonce.toString('base64url'), ciphertext: ciphertext.toString('base64url'), tag: cipher.getAuthTag().toString('base64url') }
  } catch {
    throw new Error('Invalid notification envelope')
  }
}

export function openNotification(input) {
  try {
    const { key, metadata, envelope } = input
    validateKey(key)
    if (!envelope || typeof envelope !== 'object' || envelope.version !== 1) throw new Error()
    const aad = associatedData(envelope.keyId, metadata)
    const nonce = decode(envelope.nonce, 12)
    const ciphertext = decode(envelope.ciphertext)
    const tag = decode(envelope.tag, 16)
    const decipher = createDecipheriv('aes-256-gcm', key, nonce)
    decipher.setAAD(aad)
    decipher.setAuthTag(tag)
    return Buffer.concat([decipher.update(ciphertext), decipher.final()])
  } catch {
    throw new Error('Invalid notification envelope')
  }
}
