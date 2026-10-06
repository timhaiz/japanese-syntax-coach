import { readFile } from 'node:fs/promises'
import { NextResponse } from 'next/server'
import { getSupabaseServer } from '@/lib/supabase-server'
import { getTtsDirectory } from '@/lib/tts/server'
import { isVoiceGenerationMember } from '@/lib/tts/membership'

export const runtime = 'nodejs'

export async function GET(request: Request) {
  const params = new URL(request.url).searchParams
  const textbookId = params.get('textbookId') || ''
  const file = params.get('file') || ''
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(textbookId) || !/^[a-f0-9]{16}\.wav$/.test(file)) {
    return NextResponse.json({ error: 'Invalid audio path' }, { status: 400 })
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
  try {
    const audio = await readFile(`${getTtsDirectory(user.id, textbookId)}/${file}`)
    return new Response(audio, { headers: { 'Content-Type': 'audio/wav', 'Cache-Control': 'private, max-age=31536000, immutable' } })
  } catch {
    return NextResponse.json({ error: 'Audio not found' }, { status: 404 })
  }
}
