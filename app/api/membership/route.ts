import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'
import { isVoiceGenerationMember } from '@/lib/tts/membership'

export async function GET(request: Request) {
  const supabase = await getSupabaseServer(request)
  if (!supabase) return NextResponse.json({ error: 'Supabase is not configured' }, { status: 503 })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ authenticated: false, status: 'anonymous', isMember: false })

  const { data, error } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()
  const profile = error ? null : data
  const isMember = isVoiceGenerationMember(user, profile)
  if (error && !isMember) {
    return NextResponse.json(
      { error: 'Membership status temporarily unavailable' },
      { status: 503, headers: { 'Cache-Control': 'private, no-store' } },
    )
  }
  return NextResponse.json({
    authenticated: true,
    status: isMember ? 'member' : 'free',
    isMember,
    endsAt: profile?.membership_ends_at ?? null,
  }, { headers: { 'Cache-Control': 'private, no-store' } })
}
