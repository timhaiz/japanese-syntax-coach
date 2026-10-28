import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'
import { isValidTtsTextbookId, readTtsManifest } from '@/lib/tts/server'
import { isVoiceGenerationMember } from '@/lib/tts/membership'

export const runtime = 'nodejs'

export async function GET(request: Request) {
  const textbookId = new URL(request.url).searchParams.get('textbookId') || ''
  if (!isValidTtsTextbookId(textbookId)) {
    return NextResponse.json({ error: '无效的教材 ID。' }, { status: 400 })
  }
  const supabase = await getSupabaseServer()
  if (!supabase) return NextResponse.json({ error: 'Supabase is not configured' }, { status: 503 })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { data: profile } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()
  if (!isVoiceGenerationMember(user, profile)) {
    return NextResponse.json({ error: '教材语音播放仅对会员开放。', memberRequired: true }, { status: 403 })
  }
  const manifest = await readTtsManifest(user.id, textbookId)
  if (!manifest) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json(manifest, { headers: { 'Cache-Control': 'private, max-age=60' } })
}
