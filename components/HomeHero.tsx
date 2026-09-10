'use client'
import type { CSSProperties } from 'react'

export function HomeHero({
  learnerName,
  lessonId,
  progress,
  onStart,
}: {
  learnerName: string
  lessonId: number
  progress: number
  onStart: () => void
}) {
  const orbStyle = {
    background: `conic-gradient(var(--green) 0 ${progress}%,#dfe9e3 ${progress}%`,
  } as CSSProperties
  return (
    <section className="hero home-hero">
      <div className="hero-copy">
        <p className="eyebrow">早上好，{learnerName}</p>
        <h1>
          一课一练，<em>把句型练成反射。</em>
        </h1>
        <p className="muted">每课 20 道主动输出题：先看句型骨架，再练到能快速组织日语。</p>
        <button className="primary" onClick={onStart}>
          开始第 {lessonId} 课 <span>→</span>
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
