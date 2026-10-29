import { NextResponse } from 'next/server'
import { getAuthenticatedSupabase } from '@/lib/auth/request-supabase'
import { updateMembershipFromAppleTransaction, verifyAppleTransaction } from '@/lib/apple/server'

export const runtime = 'nodejs'

export async function POST(request: Request) {
  const authenticated = await getAuthenticatedSupabase(request)
  if ('response' in authenticated) return NextResponse.json({ error: '请先登录。' }, { status: 401 })
  const {supabase, user} = authenticated
  const body = await request.json().catch(() => null) as { signedTransaction?: unknown } | null
  if (typeof body?.signedTransaction !== 'string') return NextResponse.json({ error: 'signedTransaction required' }, { status: 400 })
  try {
    const transaction = await verifyAppleTransaction(body.signedTransaction)
    if (transaction.appAccountToken && transaction.appAccountToken !== user.id) {
      return NextResponse.json({ error: '交易账号与当前账号不匹配。' }, { status: 403 })
    }
    const result = await updateMembershipFromAppleTransaction({ ...transaction, appAccountToken: user.id }, 'SUBSCRIBED')
    return NextResponse.json(result)
  } catch (error) {
    console.error('Apple entitlement rejected', error instanceof Error ? error.message : error)
    return NextResponse.json({ error: '无法验证 Apple 购买记录。' }, { status: 400 })
  }
}
