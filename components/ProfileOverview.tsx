'use client'
export function ProfileOverview({
  email,
  registrationDate,
  lessonId,
  progress,
  totalAnswered,
  completedCount,
  syncLabel,
  onLogin,
  metrics,
}: {
  email: string
  registrationDate: string
  lessonId: number
  progress: number
  totalAnswered: number
  completedCount: number
  syncLabel: string
  onLogin: () => void
  metrics?: { correctStreak: number; errorRate: number; forgettingRate?: number; topErrorTags: { tag: string; count: number }[] }
}) {
  return (
    <>
      <div className="profile-card">
        <div className="profile-avatar">{email ? email.slice(0, 1).toUpperCase() : 'N'}</div>
        <div>
          <h2>{email || 'N 学习者'}</h2>
          <p>{email ? '已登录' : '尚未登录'}</p>
        </div>
        <button className="outline" onClick={onLogin}>
          {email ? '切换账号' : '登录 / 注册'}
        </button>
      </div>
      <div className="profile-stats">
        <div>
          <b>第 {lessonId} 课</b>
          <span>当前课程</span>
        </div>
        <div>
          <b>{progress}%</b>
          <span>学习进度</span>
        </div>
        <div>
          <b>{totalAnswered}</b>
          <span>累计练习</span>
        </div>
      </div>
      <div className="info-list">
        {metrics && <div><span>连续答对</span><b>{metrics.correctStreak} 题</b></div>}
        {metrics && <div><span>总体错误率</span><b>{metrics.errorRate}%</b></div>}
        {metrics && <div><span>遗忘率</span><b>{metrics.forgettingRate ?? 0}%</b></div>}
        {metrics && <div><span>最常错知识点</span><b>{metrics.topErrorTags[0]?.tag || '暂无'}</b></div>}
        <div>
          <span>注册时间</span>
          <b>{registrationDate}</b>
        </div>
        <div>
          <span>同步状态</span>
          <b>{syncLabel}</b>
        </div>
        <div>
          <span>已完成课程</span>
          <b>{completedCount} / 24</b>
        </div>
        <div>
          <span>累计练习</span>
          <b>{totalAnswered} 题</b>
        </div>
      </div>
    </>
  )
}
