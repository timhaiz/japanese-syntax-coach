import { NextResponse } from 'next/server'
import { updateMembershipFromAppleTransaction, verifyAppleNotification, verifyAppleTransaction } from '@/lib/apple/server'

export const runtime = 'nodejs'

export async function POST(request: Request) {
  const body = await request.json().catch(() => null) as { signedPayload?: unknown } | null
  if (typeof body?.signedPayload !== 'string') return NextResponse.json({ error: 'signedPayload required' }, { status: 400 })
  try {
    const notification = await verifyAppleNotification(body.signedPayload)
    const signedTransaction = notification.data?.signedTransactionInfo
    if (signedTransaction) {
      const transaction = await verifyAppleTransaction(signedTransaction)
      await updateMembershipFromAppleTransaction(transaction, notification.notificationType)
    }
    return NextResponse.json({ received: true })
  } catch (error) {
    console.error('Apple notification rejected', error instanceof Error ? error.message : error)
    return NextResponse.json({ error: 'Invalid Apple notification' }, { status: 400 })
  }
}
