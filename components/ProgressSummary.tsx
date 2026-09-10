'use client'
export function ProgressSummary({ lessonProgress, lessonId, overallProgress }: { lessonProgress: number; lessonId: number; overallProgress: number }) {
  return <section className="stats"><div><b>{lessonProgress}%</b><span>本课进度</span></div><div><b>第 {lessonId} 课</b><span>继续学习</span></div><div><b>{overallProgress}%</b><span>整体掌握</span></div></section>
}
