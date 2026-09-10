'use client'

type Tab = 'home' | 'lessons' | 'mistakes' | 'me'

export function BottomNav({ activeTab, onNavigate }: { activeTab: string; onNavigate: (tab: Tab) => void }) {
  return (
    <nav aria-label="主导航">
      <button aria-current={activeTab === 'home' ? 'page' : undefined} aria-label="首页" className={activeTab === 'home' ? 'selected' : ''} onClick={() => onNavigate('home')}>⌂<small>首页</small></button>
      <button aria-current={activeTab === 'lessons' || activeTab === 'lesson' ? 'page' : undefined} aria-label="课程" className={activeTab === 'lessons' || activeTab === 'lesson' ? 'selected' : ''} onClick={() => onNavigate('lessons')}>▤<small>课程</small></button>
      <button aria-current={activeTab === 'mistakes' ? 'page' : undefined} aria-label="错题本" className={activeTab === 'mistakes' ? 'selected' : ''} onClick={() => onNavigate('mistakes')}>☆<small>错题本</small></button>
      <button aria-current={activeTab === 'me' ? 'page' : undefined} aria-label="我的" className={activeTab === 'me' ? 'selected' : ''} onClick={() => onNavigate('me')}>◎<small>我的</small></button>
    </nav>
  )
}
