'use client'
import {useState} from 'react'
import {courses} from '@/lib/courses'

const lessons=courses.map((c,i)=>({...c,progress:i===0?42:i<3?18:0,locked:i>3}))
const exercises=[
 {id:1,type:'翻译',prompt:'我是学生。',answer:'私は学生です。',hint:'A は B です'},
 {id:2,type:'翻译',prompt:'我不是老师。',answer:'私は先生ではありません。',hint:'ではありません = 不是'},
 {id:3,type:'助词',prompt:'这是 ___ 我的书。',answer:'これは私の本です。',hint:'连接两个名词'},
 {id:4,type:'翻译',prompt:'田中先生是学生吗？',answer:'田中さんは学生ですか。',hint:'句尾加 ですか'},
]

export default function Home(){
 const [tab,setTab]=useState('home'); const [active,setActive]=useState(0); const [input,setInput]=useState(''); const [graded,setGraded]=useState(false); const [done,setDone]=useState(0)
 const ex=exercises[active%exercises.length]
 const cleaned=(s:string)=>s.replace(/[\s。！？!?，,、．.]/g,'')
 const answerMatches=cleaned(input)===cleaned(ex.answer)
 const missingPunctuation=answerMatches&&/[。．.]$/.test(ex.answer)&&!/[。．.]$/.test(input.trim())
 const grade=()=>setGraded(true)
 return <main className="shell">
  <header><div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>标准日本语 · 上册</small></div></div><div className="streak">🔥 3 天</div><button className="avatar">N</button></header>
  {tab==='home'&&<><section className="hero"><div><p className="eyebrow">早上好，N</p><h1>今天也把句型<br/><em>练成反射。</em></h1><p className="muted">20 分钟，完成 10 道主动输出练习</p><button className="primary" onClick={()=>setTab('practice')}>开始今日训练 <span>→</span></button></div><div className="orb"><div className="orb-inner">今日<br/><b>42%</b></div></div></section>
   <section className="stats"><div><b>12</b><span>待复习</span></div><div><b>第 1 课</b><span>当前课程</span></div><div><b>68%</b><span>本周掌握</span></div></section>
   <section className="section-head"><div><p className="eyebrow">继续学习</p><h2>课程进度</h2></div><button className="link" onClick={()=>setTab('lessons')}>查看全部 →</button></section>
   <div className="lesson-card" onClick={()=>setTab('lesson')}><div className="lesson-no">01</div><div className="lesson-info"><div className="tag">正在学习</div><h3>自我介绍与判断句</h3><p>A は B です · ではありません · ですか · の</p><div className="progress"><i style={{width:'42%'}}/></div><small>已掌握 42%</small></div><span className="arrow">→</span></div>
   <section className="section-head"><div><p className="eyebrow">复习日历</p><h2>间隔复习</h2></div></section><div className="review-row">{['今天','明天','周四','周日'].map((d,i)=><div className={i===0?'review active':'review'} key={d}><span>{d}</span><b>{[12,8,5,3][i]}</b><small>道题</small></div>)}</div>
  </>}
  {tab==='lessons'&&<><div className="page-title"><p className="eyebrow">课程地图</p><h1>标准日本语·上册</h1><p className="muted">24 课 · 从句型骨架开始，逐步建立语感</p></div><div className="lesson-grid">{lessons.map(l=><button key={l.id} className={'lesson-tile '+(l.locked?'locked':'')} onClick={()=>!l.locked&&(setActive(l.id-1),setTab('lesson'))}><span>{String(l.id).padStart(2,'0')}</span><div><b>第 {l.id} 课</b><small>{l.title}</small>{!l.locked&&<div className="mini-progress"><i style={{width:`${l.progress}%`}}/></div>}</div><em>{l.locked?'🔒':l.progress+'%'}</em></button>)}</div></>}
  {tab==='lesson'&&<><button className="back" onClick={()=>setTab('home')}>← 返回</button><div className="page-title"><div className="tag">第 1 课 · 核心句型</div><h1>自我介绍与<br/>判断句</h1><p className="muted">先掌握 4 个句型骨架，再开始输出练习。</p></div><div className="grammar-list">{[['A は B です。','A 是 B。','私は学生です。'],['A は B ではありません。','A 不是 B。','私は先生ではありません。'],['A は B ですか。','A 是 B 吗？','田中さんは学生ですか。'],['A の B','A 的 B','これは私の本です。']].map((g,i)=><div className="grammar" key={i}><span>0{i+1}</span><div><b>{g[0]}</b><p>{g[1]}</p><small>{g[2]}</small></div><button onClick={()=>speechSynthesis?.speak(new SpeechSynthesisUtterance(g[2]))}>🔊</button></div>)}</div><button className="primary wide" onClick={()=>setTab('practice')}>开始练习 <span>→</span></button></>}
  {tab==='practice'&&<><div className="practice-top"><button className="back" onClick={()=>setTab('home')}>× 退出</button><span>第 1 课 · 练习</span><b>{Math.min(done+1,10)} / 10</b></div><div className="quiz"><div className="quiz-meta"><span className="tag">{ex.type}</span><span>句型骨架</span></div><h2>把下面的中文说成日语</h2><div className="prompt">{ex.prompt}</div><p className="hint">辅助提示：{ex.hint}（不确定时再看）<br/>书写时不要忘记写标点符号，标点不影响判分。</p><textarea value={input} onChange={e=>setInput(e.target.value)} placeholder="在这里输入你的答案…" disabled={graded}/>{graded&&<div className={'feedback '+(answerMatches?'ok':'warn')}><b>{answerMatches?'✓ 很好，句型正确':'△ 句型或词语还需要调整'}</b><p>参考答案：{ex.answer}</p>{missingPunctuation&&<small>答案判定正确；下次书写时不要忘记写标点符号。</small>}{!answerMatches&&<small>记忆点：{ex.hint}</small>}</div>}<button className="primary wide" onClick={()=>{if(graded){if(done>=9){setDone(10);setInput('');setGraded(false);setTab('home')}else{setDone(done+1);setActive(active+1);setInput('');setGraded(false)}}else grade()}}>{graded?(done>=9?'完成训练':'下一题'):'提交答案'} <span>→</span></button></div></>}
  <nav><button className={tab==='home'?'selected':''} onClick={()=>setTab('home')}>⌂<small>首页</small></button><button className={tab==='lessons'||tab==='lesson'?'selected':''} onClick={()=>setTab('lessons')}>▤<small>课程</small></button><button className={tab==='practice'?'selected':''} onClick={()=>setTab('practice')}>◉<small>训练</small></button><button>☆<small>错题本</small></button></nav>
 </main>
}
