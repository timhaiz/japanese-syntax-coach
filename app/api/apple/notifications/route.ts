import { NextResponse } from 'next/server'
import { VerificationException, VerificationStatus } from '@apple/app-store-server-library'
import { AppleVerifierConfigurationError } from '@/lib/apple/server'
import { updateMembershipFromAppleTransaction, verifyAppleNotification, verifyAppleTransaction } from '@/lib/apple/server'

export const runtime = 'nodejs'

export async function POST(request: Request) {
  const body = await request.json().catch(() => null) as { signedPayload?: unknown } | null
  if (typeof body?.signedPayload !== 'string') return NextResponse.json({ error: 'signedPayload required' }, { status: 400 })
  try {
    const notification = await verifyAppleNotification(body.signedPayload)
    const signedTransaction = notification.data?.signedTransactionInfo
    if (!signedTransaction) {
      if (notification.notificationType === 'TEST') return NextResponse.json({ received: true })
      return NextResponse.json({ error: 'Apple notification not processed' }, { status: 503 })
    }
    const transaction = await verifyAppleTransaction(signedTransaction)
    try {
      const result = await updateMembershipFromAppleTransaction(transaction, notification.notificationType)
      if (result?.updated !== true) return NextResponse.json({ error: 'Apple notification not processed' }, { status: 503 })
    } catch {
      console.error('Apple notification processing failed')
      return NextResponse.json({ error: 'Apple notification not processed' }, { status: 503 })
    }
    return NextResponse.json({ received: true })
  } catch (error) {
    if (error instanceof AppleVerifierConfigurationError ||
      (error instanceof VerificationException && error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE)) {
      console.error('Apple notification verification unavailable')
      return NextResponse.json({ error: 'Apple notification not processed' }, { status: 503 })
    }
    console.error('Apple notification rejected')
    return NextResponse.json({ error: 'Invalid Apple notification' }, { status: 400 })
  }
}
