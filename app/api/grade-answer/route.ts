import {NextResponse} from 'next/server'
import {gradeWithAI} from '@/lib/ai'
import { getCurrentMembership } from '@/lib/membership-server'

export const runtime = 'nodejs'
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

 const membership = await getCurrentMembership()
 if (membership.configured && !membership.user) {
  return NextResponse.json({error:'请先登录后使用 AI 判分。',memberRequired:true},{status:401})
 }
 if (membership.configured && !membership.isMember) {
  return NextResponse.json({error:'AI 判分仅对会员开放。',memberRequired:true},{status:403})
 }
 if (!membership.configured && process.env.NODE_ENV === 'production') {
  return NextResponse.json({error:'会员服务暂未配置，请稍后重试。'},{status:503})
 }

 // OpenAI grading
 const ai=await gradeWithAI({answer,standardAnswer:standard,context:String(body.hint||''),userAgent:req.headers.get('user-agent')||undefined})
 if(ai)return NextResponse.json({...ai,source:'ai'})

 // Final fallback: rule-based
 const result:{verdict:Verdict;correctedAnswer:string;errorTags:string[];explanation:string;hint?:string;acceptedAlternatives?:string[]}={
  verdict:'needs_fix', correctedAnswer:standard, errorTags:['句型顺序'], explanation:'先对照句型骨架检查助词、否定形式和句尾。', hint:body.hint
 }
 return NextResponse.json({...result,source:'rule'})
}
