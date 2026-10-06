'use client'

import type { MembershipStatus } from '@/lib/hooks/useMembership'

export function MembershipBadge({ status }: { status: MembershipStatus }) {
  if (status === 'anonymous') return null
  const label = status === 'member' ? '会员' : status === 'loading' ? '检查中' : '免费版'
  return (
    <span className={`membership-badge ${status}`} aria-label={`当前账号：${label}`}>
      {status === 'member' ? '✦ ' : ''}{label}
    </span>
  )
}
