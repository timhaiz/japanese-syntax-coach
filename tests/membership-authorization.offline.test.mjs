import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isVoiceGenerationMember } from '../lib/tts/membership.ts'

// No email or app metadata: these checks exercise the profile path only.
const user = {}

test('expired active profile does not grant access', () => {
  assert.equal(isVoiceGenerationMember(user, {
    membership_status: 'active', membership_ends_at: '2000-01-01T00:00:00Z',
  }), false)
})

test('unexpired active profile grants access', () => {
  assert.equal(isVoiceGenerationMember(user, {
    membership_status: 'active', membership_ends_at: '2999-01-01T00:00:00Z',
  }), true)
})

test('free profile does not grant access', () => {
  assert.equal(isVoiceGenerationMember(user, {
    membership_status: 'free', membership_ends_at: '2999-01-01T00:00:00Z',
  }), false)
})

test('explicit voice entitlement in app metadata grants access', () => {
  assert.equal(isVoiceGenerationMember({ app_metadata: { voice_generation: true } }, null), true)
})

test('a profile expires exactly at its end time', () => {
  const originalNow = Date.now
  const end = Date.parse('2030-01-01T00:00:00Z')
  const profile = { membership_status: 'active', membership_ends_at: '2030-01-01T00:00:00Z' }
  try {
    Date.now = () => end - 1
    assert.equal(isVoiceGenerationMember(user, profile), true)
    Date.now = () => end
    assert.equal(isVoiceGenerationMember(user, profile), false)
    Date.now = () => end + 1
    assert.equal(isVoiceGenerationMember(user, profile), false)
  } finally {
    Date.now = originalNow
  }
})

test('user-controlled metadata does not grant voice access', () => {
  assert.equal(isVoiceGenerationMember({ user_metadata: { voice_generation: true, membership_status: 'active' } }, null), false)
})

test('trusted voice metadata remains an independent entitlement after profile expiry', () => {
  assert.equal(isVoiceGenerationMember(
    { app_metadata: { voicevox_enabled: true } },
    { membership_status: 'expired', membership_ends_at: '2000-01-01T00:00:00Z' },
  ), true)
})
