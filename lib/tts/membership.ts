type MembershipProfile = {
  membership_status?: string | null
  membership_ends_at?: string | null
}

type AuthUser = {
  email?: string | null
  app_metadata?: Record<string, unknown>
}

const activeStatuses = new Set(['active', 'trialing', 'paid', 'member', 'premium'])

/**
 * Voice generation is a paid capability. Billing can set this value on the
 * profile row, while app_metadata is useful during a staged rollout.
 */
export function isVoiceGenerationMember(
  user: AuthUser,
  profile?: MembershipProfile | null,
): boolean {
  const status = profile?.membership_status
  const endsAt = profile?.membership_ends_at ? Date.parse(profile.membership_ends_at) : NaN
  if (activeStatuses.has(String(status).toLowerCase()) && (!Number.isFinite(endsAt) || endsAt > Date.now())) {
    return true
  }

  const metadata = user.app_metadata ?? {}
  if (metadata.voice_generation === true || metadata.voicevox_enabled === true) return true
  if (activeStatuses.has(String(metadata.subscription_status ?? metadata.membership_status).toLowerCase())) {
    return true
  }

  const allowedEmails = (process.env.VOICEVOX_MEMBER_EMAILS ?? '')
    .split(',')
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean)
  return Boolean(user.email && allowedEmails.includes(user.email.toLowerCase()))
}
