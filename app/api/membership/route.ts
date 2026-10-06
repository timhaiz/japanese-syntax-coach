import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'
import { isVoiceGenerationMember } from '@/lib/tts/membership'

export async function GET() {
  const supabase = await getSupabaseServer()
  if (!supabase) return NextResponse.json({ error: 'Supabase is not configured' }, { status: 503 })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ authenticated: false, status: 'anonymous', isMember: false })

  const { data: profile } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()
  const isMember = isVoiceGenerationMember(user, profile)
  return NextResponse.json({
    authenticated: true,
    status: isMember ? 'member' : 'free',
    isMember,
    endsAt: profile?.membership_ends_at ?? null,
  }, { headers: { 'Cache-Control': 'private, no-store' } })
}
