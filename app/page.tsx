'use client'
import {useEffect,useState} from 'react'
import {courses} from '@/lib/courses'
import {getSupabaseBrowser} from '@/lib/supabase'

const courseLessons=courses.map((c)=>({...c,progress:0,locked:false}))
const exercises=[
 {id:1,type:'翻译',prompt:'我是学生。',answer:'私は学生です。',hint:'A は B です'},
 {id:2,type:'翻译',prompt:'我不是老师。',answer:'私は先生ではありません。',hint:'ではありません = 不是'},
 {id:3,type:'助词',prompt:'这是 ___ 我的书。',answer:'これは私の本です。',hint:'连接两个名词'},
 {id:4,type:'翻译',prompt:'田中先生是学生吗？',answer:'田中さんは学生ですか。',hint:'句尾加 ですか'},
 {id:5,type:'翻译',prompt:'我是公司职员。',answer:'私は会社員です。',hint:'A は B です'},
 {id:6,type:'翻译',prompt:'小李不是医生。',answer:'李さんは医者ではありません。',hint:'ではありません = 不是'},
 {id:7,type:'助词',prompt:'这是 ___ 佐藤先生的伞。',answer:'これは佐藤さんの傘です。',hint:'用 の 连接所属关系'},
 {id:8,type:'翻译',prompt:'那个人是日本人吗？',answer:'あの人は日本人ですか。',hint:'句尾加 ですか'},
 {id:9,type:'翻译',prompt:'我不是大学生。',answer:'私は大学生ではありません。',hint:'ではありません = 不是'},
 {id:10,type:'翻译',prompt:'山田先生是老师。',answer:'山田さんは先生です。',hint:'A は B です'},
]

export default function Home(){
 const [tab,setTab]=useState('home'); const [active,setActive]=useState(0); const [input,setInput]=useState(''); const [graded,setGraded]=useState(false); const [done,setDone]=useState(0); const [userEmail,setUserEmail]=useState('')
 const [reviewDone,setReviewDone]=useState(0); const [minutes,setMinutes]=useState(0); const [claimed,setClaimed]=useState({new:false,review:false,time:false,bonus:false}); const [practiceMode,setPracticeMode]=useState<'new'|'review'>('new'); const [completedLessons,setCompletedLessons]=useState<number[]>([]); const [lessonDone,setLessonDone]=useState<Record<number,number>>({})
 useEffect(()=>{const s=getSupabaseBrowser();if(!s)return; s.auth.getUser().then(({data})=>setUserEmail(data.user?.email||'')); const {data}=s.auth.onAuthStateChange((_e,session)=>setUserEmail(session?.user?.email||'')); return ()=>data.subscription.unsubscribe()},[])
 useEffect(()=>{const key=`syntax-coach-daily-${new Date().toLocaleDateString('sv-SE')}`;const saved=localStorage.getItem(key);if(saved){try{const data=JSON.parse(saved);setDone(data.done||0);setReviewDone(data.reviewDone||0);setMinutes(data.minutes||0);setClaimed(data.claimed||{new:false,review:false,time:false,bonus:false})}catch{localStorage.removeItem(key)}}},[])
 useEffect(()=>{const saved=localStorage.getItem('syntax-coach-completed-lessons');if(saved){try{setCompletedLessons(JSON.parse(saved).filter((n:number)=>n===0))}catch{localStorage.removeItem('syntax-coach-completed-lessons')}}},[])
 useEffect(()=>{const saved=localStorage.getItem('syntax-coach-lesson-progress');if(saved){try{setLessonDone(JSON.parse(saved))}catch{localStorage.removeItem('syntax-coach-lesson-progress')}}},[])
 useEffect(()=>{localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify(lessonDone))},[lessonDone])
 useEffect(()=>{localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify(completedLessons))},[completedLessons])
 useEffect(()=>{if(tab==='home'&&lessonDone[active]>=10)setCompletedLessons(value=>value.includes(active)?value:[...value,active])},[tab,active,lessonDone])
 useEffect(()=>{if(tab==='lesson'&&active>0)setDone(0)},[tab,active])
 useEffect(()=>{if(tab==='practice'&&done>0)setLessonDone(value=>({...value,[active]:Math.min(10,done)}))},[tab,done,active])
 useEffect(()=>{const key=`syntax-coach-daily-${new Date().toLocaleDateString('sv-SE')}`;localStorage.setItem(key,JSON.stringify({done,reviewDone,minutes,claimed}))},[done,reviewDone,minutes,claimed])
 useEffect(()=>{const timer=window.setInterval(()=>{if(!document.hidden)setMinutes(value=>Math.min(20,value+1))},60000);return()=>window.clearInterval(timer)},[])
 const activeLessonDone=lessonDone[active]??(active===0?done:0)
 const displayedLessons=courseLessons.map((lesson,index)=>({...lesson,progress:Math.min(100,Math.round(((lessonDone[index]??(index===0?done:0))/10)*100)),locked:index>0&&!completedLessons.includes(index-1)}))
 const lessons=displayedLessons
 const selectedLesson=displayedLessons[Math.min(active,displayedLessons.length-1)]
 const progress=practiceMode==='new'?activeLessonDone:reviewDone; const sessionLimit=practiceMode==='new'?10:5
 const currentGrammar=selectedLesson.grammar[progress%selectedLesson.grammar.length]
 const priorGrammar=active>0?displayedLessons[active-1]?.grammar[progress%displayedLessons[active-1].grammar.length]:undefined
 const isReviewQuestion=active>0&&progress%10>=7
 const ex=active===0?exercises[progress%exercises.length]:isReviewQuestion&&priorGrammar?{id:active+1,type:'旧课复习',prompt:`复习第 ${active} 课：请根据「${priorGrammar.meaning}」表达一个句子。`,answer:priorGrammar.example,hint:`旧课句型：${priorGrammar.pattern}`}:{id:active+1,type:'新课',prompt:`请根据「${currentGrammar.meaning}」表达一个句子。`,answer:currentGrammar.example,hint:`句型：${currentGrammar.pattern}`}
 const cleaned=(s:string)=>s.replace(/[\s。！？!?，,、．.]/g,'')
 const answerMatches=cleaned(input)===cleaned(ex.answer)
 const missingPunctuation=answerMatches&&/[。．.]$/.test(ex.answer)&&!/[。．.]$/.test(input.trim())
 const grade=()=>setGraded(true)
 const startPractice=(mode:'new'|'review')=>{setPracticeMode(mode);setInput('');setGraded(false);setTab('practice')}
 const nextQuestion=()=>{const complete=progress>=sessionLimit-1;if(practiceMode==='new'){setDone(value=>Math.min(10,value+1));setLessonDone(value=>({...value,[active]:Math.min(10,(value[active]??0)+1)}))}else setReviewDone(value=>Math.min(5,value+1));setInput('');setGraded(false);if(complete)setTab('home')}
 const taskStatus={new:done>=10,review:reviewDone>=5,time:minutes>=20}; const claim=(key:'new'|'review'|'time'|'bonus')=>setClaimed(c=>({...c,[key]:true})); const allTasks=taskStatus.new&&taskStatus.review&&taskStatus.time
 const todayProgress=Math.round((done/10)*100)
 return <main className="shell">
  <header><div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>标准日本语 · 上册</small></div></div><div className={'streak '+(done>=10?'finished':'')}>{done>=10?'✓ 今日完成':`今日 ${done} / 10`}</div><button className="avatar" onClick={()=>setTab('me')}>N</button></header>
  {tab==='home'&&<><section className="hero"><div><p className="eyebrow">早上好，N</p><h1>今天也把句型<br/><em>练成反射。</em></h1><p className="muted">每天 20 分钟，完成 10 道主动输出练习</p><button className="primary" onClick={()=>setTab('practice')}>开始今日训练 <span>→</span></button></div><div className="orb" style={{background:`conic-gradient(var(--green) 0 ${todayProgress}%,#dfe9e3 ${todayProgress}%`}}><div className="orb-inner">今日<br/><b>{todayProgress}%</b></div></div></section>
   <section className="stats"><div><b>12</b><span>待复习</span></div><div><b>第 1 课</b><span>当前课程</span></div><div><b>68%</b><span>本周掌握</span></div></section>
   <section className="section-head"><div><p className="eyebrow">今日目标</p><h2>完成任务，领取积分</h2></div><strong className="points">{(claimed.new?15:0)+(claimed.review?15:0)+(claimed.time?15:0)+(claimed.bonus?15:0)} 分</strong></section>
   <div className="daily-tasks"><div className={'task '+(taskStatus.new?'complete':'')}><span className="task-check">{taskStatus.new?'✓':'01'}</span><div><b>完成新的 10 道题</b><small>{Math.min(done,10)} / 10 · 主动输出</small></div>{taskStatus.new?<button className="claim" onClick={()=>claim('new')} disabled={claimed.new}>{claimed.new?'已领取':'领取 15 分'}</button>:<button className="task-action" onClick={()=>setTab('practice')}>去完成</button>}</div><div className={'task '+(taskStatus.review?'complete':'')}><span className="task-check">{taskStatus.review?'✓':'02'}</span><div><b>完成 5 道复习题</b><small>{reviewDone} / 5 · 间隔复习</small></div>{taskStatus.review?<button className="claim" onClick={()=>claim('review')} disabled={claimed.review}>{claimed.review?'已领取':'领取 15 分'}</button>:<button className="task-action" onClick={()=>setReviewDone(5)}>模拟完成</button>}</div><div className={'task '+(taskStatus.time?'complete':'')}><span className="task-check">{taskStatus.time?'✓':'03'}</span><div><b>累计学习 20 分钟</b><small>{minutes} / 20 分钟 · 专注学习</small></div>{taskStatus.time?<button className="claim" onClick={()=>claim('time')} disabled={claimed.time}>{claimed.time?'已领取':'领取 15 分'}</button>:<button className="task-action" onClick={()=>setMinutes(20)}>完成计时</button>}</div>{allTasks&&<div className="bonus-task"><span>🎉</span><div><b>三项任务全部完成</b><small>额外奖励 15 分</small></div><button className="claim bonus" onClick={()=>claim('bonus')} disabled={claimed.bonus}>{claimed.bonus?'已领取':'领取 15 分'}</button></div>}</div>
   <section className="section-head"><div><p className="eyebrow">继续学习</p><h2>课程进度</h2></div><button className="link" onClick={()=>setTab('lessons')}>查看全部 →</button></section>
<div className="lesson-card" onClick={()=>setTab('lesson')}><div className="lesson-no">01</div><div className="lesson-info"><div className="tag">正在学习</div><h3>{displayedLessons[0].title}</h3><p>{displayedLessons[0].grammar.map(g=>g.pattern).join(' · ')}</p><div className="progress"><i style={{width:`${displayedLessons[0].progress}%`}}/></div><small>已掌握 {displayedLessons[0].progress}%</small></div><span className="arrow">→</span></div>
   <section className="section-head"><div><p className="eyebrow">复习日历</p><h2>间隔复习</h2></div></section><div className="review-row">{['今天','明天','周四','周日'].map((d,i)=><div className={i===0?'review active':'review'} key={d}><span>{d}</span><b>{[12,8,5,3][i]}</b><small>道题</small></div>)}</div>
  </>}
  {tab==='lessons'&&<><div className="page-title"><p className="eyebrow">课程地图</p><h1>标准日本语·上册</h1><p className="muted">24 课 · 从句型骨架开始，逐步建立语感</p></div><div className="lesson-grid">{lessons.map(l=><button key={l.id} className={'lesson-tile '+(l.locked?'locked':'')} onClick={()=>!l.locked&&(setActive(l.id-1),setTab('lesson'))}><span>{String(l.id).padStart(2,'0')}</span><div><b>第 {l.id} 课</b><small>{l.title}</small>{!l.locked&&<div className="mini-progress"><i style={{width:`${l.progress}%`}}/></div>}</div><em>{l.locked?'🔒':l.progress+'%'}</em></button>)}</div></>}
  {tab==='lesson'&&<><button className="back" onClick={()=>setTab('home')}>← 返回</button><div className="page-title"><div className="tag">第 {selectedLesson.id} 课 · 核心句型</div><h1>{selectedLesson.title}</h1><p className="muted">{selectedLesson.goal}</p></div><div className="grammar-list">{selectedLesson.grammar.map((g,i)=><div className="grammar" key={i}><span>0{i+1}</span><div><b>{g.pattern}</b><p>{g.meaning}</p><small>{g.example}</small></div><button onClick={()=>speechSynthesis?.speak(new SpeechSynthesisUtterance(g.example))}>🔊</button></div>)}</div><button className="primary wide" onClick={()=>setTab('practice')}>开始练习 <span>→</span></button></>}
  {tab==='practice'&&<><div className="practice-top"><button className="back" onClick={()=>setTab('home')}>× 退出</button><span>第 {selectedLesson.id} 课 · 练习</span><b>{Math.min(done+1,10)} / 10</b></div><div className="quiz"><div className="quiz-meta"><span className="tag">{ex.type}</span><span>句型骨架</span></div><h2>把下面的中文说成日语</h2><div className="prompt">{ex.prompt}</div><p className="hint">辅助提示：{ex.hint}（不确定时再看）<br/>书写时不要忘记写标点符号，标点不影响判分。</p><textarea value={input} onChange={e=>setInput(e.target.value)} placeholder="在这里输入你的答案…" disabled={graded}/>{graded&&<div className={'feedback '+(answerMatches?'ok':'warn')}><b>{answerMatches?'✓ 很好，句型正确':'△ 句型或词语还需要调整'}</b><p>参考答案：{ex.answer}</p>{missingPunctuation&&<small>答案判定正确；下次书写时不要忘记写标点符号。</small>}{!answerMatches&&<small>记忆点：{ex.hint}</small>}</div>}<button className="primary wide" onClick={()=>{if(graded){if(done>=9){setDone(10);setInput('');setGraded(false);setTab('home')}else{setDone(done+1);setInput('');setGraded(false)}}else grade()}}>{graded?(done>=9?'完成训练':'下一题'):'提交答案'} <span>→</span></button></div></>}
  {tab==='mistakes'&&<><div className="page-title"><p className="eyebrow">复习重点</p><h1>错题本</h1><p className="muted">把容易忘的地方，再练一次。</p></div><div className="mistake-card"><div className="mistake-icon">文</div><div><b>ではありません</b><p>第 1 课 · 假名书写</p><small>已复习 2 次 · 下次复习今天</small></div><span>→</span></div><div className="empty-note">目前有 1 个重点错题<br/>完成练习后，错题会自动收录。</div></>}
  {tab==='me'&&<><div className="page-title"><p className="eyebrow">个人中心</p><h1>我的</h1><p className="muted">学习记录会在登录后同步到云端。</p></div><div className="profile-card"><div className="profile-avatar">{userEmail?userEmail.slice(0,1).toUpperCase():'N'}</div><div><h2>{userEmail||'N 学习者'}</h2><p>{userEmail?'已登录':'尚未登录'}</p></div><button className="outline" onClick={()=>location.href='/login'}>{userEmail?'切换账号':'登录 / 注册'}</button></div><div className="profile-stats"><div><b>第 1 课</b><span>当前课程</span></div><div><b>42%</b><span>学习进度</span></div><div><b>{done*12}</b><span>积分</span></div><div><b>{done} / 10</b><span>今日训练</span></div></div><div className="info-list"><div><span>注册时间</span><b>{userEmail?'已同步':'登录后显示'}</b></div><div><span>已完成课程</span><b>0 / 24</b></div><div><span>累计练习</span><b>{done} 题</b></div></div></>}
  <nav><button className={tab==='home'?'selected':''} onClick={()=>setTab('home')}>⌂<small>首页</small></button><button className={tab==='lessons'||tab==='lesson'?'selected':''} onClick={()=>setTab('lessons')}>▤<small>课程</small></button><button className={tab==='mistakes'?'selected':''} onClick={()=>setTab('mistakes')}>☆<small>错题本</small></button><button className={tab==='me'?'selected':''} onClick={()=>setTab('me')}>◎<small>我的</small></button></nav>
 </main>
}
