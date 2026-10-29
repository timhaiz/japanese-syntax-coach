import { NextResponse } from 'next/server'
import { getAuthenticatedSupabase } from '@/lib/auth/request-supabase'
import { isVoiceGenerationMember } from '@/lib/tts/membership'
import { getTtsJob, queueTtsGeneration } from '@/lib/tts/server'
import { validateTextbookPackage } from '@/lib/textbook-import'

export const runtime = 'nodejs'

export async function POST(request: Request) {
  const authenticated = await getAuthenticatedSupabase(request)
  if ('response' in authenticated) return NextResponse.json({ error: '请先登录后使用教材语音生成功能。' }, { status: 401 })
  const {supabase, user} = authenticated

  const { data: profile } = await supabase
    .from('profiles')
    .select('membership_status,membership_ends_at')
    .eq('id', user.id)
    .maybeSingle()
  if (!isVoiceGenerationMember(user, profile)) {
    return NextResponse.json({ error: '教材语音生成功能仅对会员开放。' }, { status: 403 })
  }

  const body = await request.json().catch(() => null) as { textbook?: unknown } | null
  const result = validateTextbookPackage(body?.textbook)
  if (!result.success) return NextResponse.json({ error: result.errors.join(' ') }, { status: 400 })
  const job = queueTtsGeneration(user.id, result.data.textbook)
  return NextResponse.json({ job }, { status: 202 })
}

export async function GET(request: Request) {
  const jobId = new URL(request.url).searchParams.get('jobId') || ''
  const job = await getTtsJob(jobId)
  if (!job) return NextResponse.json({ error: '任务不存在或服务器已重启。' }, { status: 404 })
  const authenticated = await getAuthenticatedSupabase(request)
  if ('response' in authenticated) return authenticated.response
  const {user} = authenticated
  if (user.id !== job.userId) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  return NextResponse.json({ job })
}
