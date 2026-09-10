'use client'

export function AppHeader({ lessonId, learnerName, onProfile }: { lessonId: number; learnerName: string; onProfile: () => void }) {
  return (
    <header>
      <div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>标准日本语 · 上册</small></div></div>
      <div className="streak">第 {lessonId} 课</div>
      <button className="avatar" aria-label="打开个人中心" title="个人中心" onClick={onProfile}>{learnerName.slice(0, 1).toUpperCase()}</button>
    </header>
  )
}
