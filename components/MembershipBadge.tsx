'use client'

import type { MembershipStatus } from '@/lib/hooks/useMembership'

export function MembershipBadge({ status, iconOnly = false }: { status: MembershipStatus; iconOnly?: boolean }) {
  if (status === 'anonymous') return null
  const label = status === 'member' ? '会员' : status === 'loading' ? '检查中' : '免费版'
  return (
    <span
      className={`membership-badge ${status}${iconOnly ? ' icon-only' : ''}`}
      aria-label={`当前账号：${label}`}
      title={iconOnly ? label : undefined}
    >
      {iconOnly ? (status === 'member' ? '✦' : '○') : `${status === 'member' ? '✦ ' : ''}${label}`}
    </span>
  )
}
