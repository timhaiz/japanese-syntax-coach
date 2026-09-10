'use client'

type Tab = 'home' | 'lessons' | 'mistakes' | 'me'

export function BottomNav({
  activeTab,
  onNavigate,
}: {
  activeTab: string
  onNavigate: (tab: Tab) => void
}) {
  return (
    <nav aria-label="主导航">
      <button
        aria-current={activeTab === 'home' ? 'page' : undefined}
        className={activeTab === 'home' ? 'selected' : ''}
        onClick={() => onNavigate('home')}
      >
        ⌂<small>首页</small>
      </button>
      <button
        aria-current={activeTab === 'lessons' || activeTab === 'lesson' ? 'page' : undefined}
        className={activeTab === 'lessons' || activeTab === 'lesson' ? 'selected' : ''}
        onClick={() => onNavigate('lessons')}
      >
        ▤<small>课程</small>
      </button>
      <button
        aria-current={activeTab === 'mistakes' ? 'page' : undefined}
        className={activeTab === 'mistakes' ? 'selected' : ''}
        onClick={() => onNavigate('mistakes')}
      >
        ☆<small>错题本</small>
      </button>
      <button
        aria-current={activeTab === 'me' ? 'page' : undefined}
        className={activeTab === 'me' ? 'selected' : ''}
        onClick={() => onNavigate('me')}
      >
        ◎<small>我的</small>
      </button>
    </nav>
  )
}
