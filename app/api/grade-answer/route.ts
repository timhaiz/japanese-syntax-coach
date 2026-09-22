import {NextResponse} from 'next/server'
import {gradeWithAI} from '@/lib/ai'
import {gradeWithJev} from '@/lib/typesafe-grading'
type Verdict='correct'|'mostly_correct'|'needs_fix'|'incorrect'
const normalize=(s:string)=>s.replace(/[\s。！？!?，,、]/g,'')
export async function POST(req:Request){
 const body=await req.json().catch(()=>({})) as {answer?:string;standardAnswer?:string;acceptedAnswers?:string[];hint?:string}
 const answer=body.answer||''; const standard=body.standardAnswer||''
 const alternatives=[standard,...(Array.isArray(body.acceptedAnswers)?body.acceptedAnswers:[])].filter((value):value is string=>typeof value==='string')
 const exact=alternatives.some(value=>normalize(answer)===normalize(value))

 // Fast path: exact match always wins
 if(exact){
  return NextResponse.json({
   verdict:'correct' as Verdict,
   correctedAnswer:standard,
   errorTags:[],
   explanation:'句型结构正确，继续保持主动输出。',
   source:'rule',
   hint:body.hint
  })
 }

 // TypeSafe Jev path (primary AI grading)
 const jev=await gradeWithJev({answer,standardAnswer:standard,context:String(body.hint||''),userAgent:req.headers.get('user-agent')||undefined})
 if(jev){
  return NextResponse.json({...jev,source:'typesafe',hint:body.hint})
 }

 // OpenAI fallback (if Jev fails)
 const ai=await gradeWithAI({answer,standardAnswer:standard,context:String(body.hint||''),userAgent:req.headers.get('user-agent')||undefined})
 if(ai)return NextResponse.json({...ai,source:'ai'})

 // Final fallback: rule-based
 const result:{verdict:Verdict;correctedAnswer:string;errorTags:string[];explanation:string;hint?:string;acceptedAlternatives?:string[]}={
  verdict:'needs_fix', correctedAnswer:standard, errorTags:['句型顺序'], explanation:'先对照句型骨架检查助词、否定形式和句尾。', hint:body.hint
 }
 return NextResponse.json({...result,source:'rule'})
}
