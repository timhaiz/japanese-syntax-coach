'use client'
import { useEffect, useState } from 'react'
import type { CSSProperties } from 'react'

function greetingForHour(hour: number) {
  if (hour < 5) return '晚上好'
  if (hour < 12) return '早上好'
  if (hour < 18) return '下午好'
  return '晚上好'
}

export function HomeHero({
  learnerName,
  lessonId,
  progress,
  onStart,
  actionLabel,
  actionDisabled = false,
}: {
  learnerName: string
  lessonId: number
  progress: number
  onStart: () => void
  actionLabel?: string
  actionDisabled?: boolean
}) {
  const [greeting, setGreeting] = useState('你好')

  useEffect(() => {
    setGreeting(greetingForHour(new Date().getHours()))
  }, [])

  const orbStyle = {
    background: `conic-gradient(var(--green) 0 ${progress}%,#dfe9e3 ${progress}%`,
  } as CSSProperties
  return (
    <section className="hero home-hero">
      <div className="hero-copy">
        <p className="eyebrow">{greeting}，{learnerName}</p>
        <h1>
          一课一练，<em>把句型练成反射。</em>
        </h1>
        <p className="muted">每课 20 道主动输出题：先看句型骨架，再练到能快速组织日语。</p>
        <button className="primary" onClick={onStart} disabled={actionDisabled}>
          {actionLabel ?? `开始第 ${lessonId} 课`} <span>→</span>
        </button>
      </div>
      <div className="orb" style={orbStyle}>
        <div className="orb-inner">
          本课
          <br />
          <b>{progress}%</b>
        </div>
      </div>
    </section>
  )
}
