'use client'

import { useEffect, useState } from 'react'
import { getSupabaseBrowser } from '@/lib/supabase'
import {
  isIOSApp,
  sendIOSMessage,
  type IOSPurchaseResult,
} from '@/lib/apple/ios-bridge'

const MONTHLY_PRODUCT_ID = 'com.juxintong.nihongo.monthly'
const YEARLY_PRODUCT_ID = 'com.juxintong.nihongo.yearly'

export function AppleSubscriptionControls() {
  const [available, setAvailable] = useState(false)
  const [userId, setUserId] = useState('')
  const [pending, setPending] = useState<string | null>(null)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    const detected = isIOSApp()
    setAvailable(detected)
    if (!detected) return

    const supabase = getSupabaseBrowser()
    void supabase?.auth.getUser().then(({ data }) => {
      setUserId(data.user?.id ?? '')
    })

    const submitEntitlement = async (result: IOSPurchaseResult) => {
      setPending(null)
      setMessage('')
      setError('')
      if (!result.success || !result.signedTransaction) {
        if (result.message) setError(result.message)
        return
      }

      const response = await fetch('/api/apple/entitlements', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ signedTransaction: result.signedTransaction }),
      })
      if (!response.ok) {
        const payload = await response.json().catch(() => ({})) as { error?: string }
        setError(payload.error || '购买记录验证失败，请稍后重试。')
        return
      }
      setMessage('会员已开通，刷新页面后即可使用会员功能。')
      window.setTimeout(() => window.location.reload(), 900)
    }

    const previousPurchaseHandler = window.__syntaxCoachApplePurchaseResult
    const previousRestoreHandler = window.__syntaxCoachAppleRestoreResult
    window.__syntaxCoachApplePurchaseResult = (result) => { void submitEntitlement(result) }
    window.__syntaxCoachAppleRestoreResult = (result) => { void submitEntitlement(result) }
    return () => {
      window.__syntaxCoachApplePurchaseResult = previousPurchaseHandler
      window.__syntaxCoachAppleRestoreResult = previousRestoreHandler
    }
  }, [])

  if (!available) return null

  const purchase = (productID: string) => {
    setMessage('')
    setError('')
    if (!userId) {
      setError('请先登录，再购买会员。')
      return
    }
    setPending(productID)
    sendIOSMessage({ type: 'purchase', productID, userID: userId })
  }

  const restore = () => {
    setMessage('')
    setError('')
    if (!userId) {
      setError('请先登录，再恢复购买。')
      return
    }
    setPending('restore')
    sendIOSMessage({ type: 'restore' })
  }

  return (
    <section className="ios-subscription-controls" aria-labelledby="ios-subscription-title">
      <div>
        <p className="ios-subscription-kicker">App Store 订阅</p>
        <h2 id="ios-subscription-title">在 iPhone 上开通会员</h2>
        <p>付款由 Apple 处理，订阅会自动续期。你可以在 Apple 账户的订阅设置中取消。</p>
      </div>
      <div className="ios-subscription-actions">
        <button type="button" onClick={() => purchase(MONTHLY_PRODUCT_ID)} disabled={pending !== null}>
          {pending === MONTHLY_PRODUCT_ID ? '处理中…' : '月度会员 · ¥18'}
        </button>
        <button type="button" onClick={() => purchase(YEARLY_PRODUCT_ID)} disabled={pending !== null}>
          {pending === YEARLY_PRODUCT_ID ? '处理中…' : '年度会员 · ¥180'}
        </button>
        <button type="button" className="secondary" onClick={restore} disabled={pending !== null}>
          {pending === 'restore' ? '恢复中…' : '恢复购买'}
        </button>
        <button type="button" className="text" onClick={() => sendIOSMessage({ type: 'manageSubscriptions' })}>
          管理 Apple 订阅
        </button>
      </div>
      {message && <p className="ios-subscription-message success">{message}</p>}
      {error && <p className="ios-subscription-message error">{error}</p>}
    </section>
  )
}
