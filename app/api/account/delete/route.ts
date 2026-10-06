import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { getSupabaseServer } from '@/lib/supabase-server'
import { deleteUserTtsData } from '@/lib/tts/server'

export const runtime = 'nodejs'

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({})) as { confirmation?: string }
  if (body.confirmation !== 'DELETE') {
    return NextResponse.json({ error: '请确认删除账号后再试。' }, { status: 400 })
  }

  const supabase = await getSupabaseServer()
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!supabase || !serviceRoleKey || !url) {
    return NextResponse.json({ error: '账号注销服务尚未配置。' }, { status: 503 })
  }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: '请先登录。' }, { status: 401 })

  try {
    await deleteUserTtsData(user.id)
  } catch {
    return NextResponse.json({ error: '账号数据清理失败，请稍后重试。' }, { status: 500 })
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { error } = await admin.auth.admin.deleteUser(user.id)
  if (error) return NextResponse.json({ error: '账号注销失败，请稍后重试。' }, { status: 500 })
  return NextResponse.json({ deleted: true })
}
