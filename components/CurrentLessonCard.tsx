'use client'
export function CurrentLessonCard({ lesson, onOpen }: { lesson: { id: number; title: string; progress: number; grammar: { pattern: string }[] }; onOpen: () => void }) {
  return <div className="lesson-card" onClick={onOpen}><div className="lesson-no">{String(lesson.id).padStart(2,'0')}</div><div className="lesson-info"><div className="tag">第 {lesson.id} 课 · 句型训练</div><h3>{lesson.title}</h3><p>{lesson.grammar.map(g=>g.pattern).join(' · ')}</p><div className="progress"><i style={{width:`${lesson.progress}%`}}/></div><small>{lesson.progress?`已完成 ${lesson.progress}% · 继续巩固句型`:'查看本课句型，然后完成 20 道练习'}</small></div><span className="arrow">→</span></div>
}
