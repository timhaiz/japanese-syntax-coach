'use client'
export function LessonGrid({ lessons, onSelect }: { lessons: { id:number; title:string; progress:number; locked:boolean }[]; onSelect:(index:number)=>void }) {
  return <div className="lesson-grid">{lessons.map(l=><button key={l.id} className={'lesson-tile '+(l.locked?'locked':'')} onClick={()=>!l.locked&&onSelect(l.id-1)}><span>{String(l.id).padStart(2,'0')}</span><div><b>第 {l.id} 课</b><small>{l.title}</small>{!l.locked&&<div className="mini-progress"><i style={{width:`${l.progress}%`}}/></div>}</div><em>{l.locked?'🔒':l.progress+'%'}</em></button>)}</div>
}
