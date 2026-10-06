import { useEffect, useState } from 'react'

export type MembershipStatus = 'anonymous' | 'loading' | 'free' | 'member'

export function useMembership(userId: string) {
  const [status, setStatus] = useState<MembershipStatus>(userId ? 'loading' : 'anonymous')
  const [endsAt, setEndsAt] = useState<string | null>(null)

  useEffect(() => {
    if (!userId) {
      setStatus('anonymous')
      setEndsAt(null)
      return
    }
    let mounted = true
    setStatus('loading')
    void fetch('/api/membership', { cache: 'no-store' })
      .then(async (response) => response.ok ? response.json() : null)
      .then((value: { status?: MembershipStatus; endsAt?: string | null } | null) => {
        if (!mounted) return
        setStatus(value?.status === 'member' ? 'member' : 'free')
        setEndsAt(value?.endsAt ?? null)
      })
      .catch(() => {
        if (mounted) setStatus('free')
      })
    return () => { mounted = false }
  }, [userId])

  return { status, endsAt }
}
