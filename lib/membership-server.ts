import { getSupabaseServer } from '@/lib/supabase-server'
import { isVoiceGenerationMember } from '@/lib/tts/membership'

/**
 * Resolve the current account and paid membership once for protected APIs.
 * Local development can still exercise the AI fallback when Supabase is not configured;
 * deployed environments fail closed because NODE_ENV is production there.
 */
export async function getCurrentMembership() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return { supabase: null, user: null, profile: null, isMember: false, configured: false }
  }

  const supabase = await getSupabaseServer()
  if (!supabase) return { supabase: null, user: null, profile: null, isMember: false, configured: false }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { supabase, user: null, profile: null, isMember: false, configured: true }

  const { data: profile } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()

  return {
    supabase,
    user,
    profile,
    isMember: isVoiceGenerationMember(user, profile),
    configured: true,
  }
}
