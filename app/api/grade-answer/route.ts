import {NextResponse} from 'next/server'
import {gradeWithAI} from '@/lib/ai'
type Verdict='correct'|'mostly_correct'|'needs_fix'|'incorrect'
const normalize=(s:string)=>s.replace(/[\s。！？!?，,、]/g,'')
export async function POST(req:Request){
 const body=await req.json().catch(()=>({})) as {answer?:string;standardAnswer?:string;hint?:string}
 const answer=body.answer||''; const standard=body.standardAnswer||''
 const exact=normalize(answer)===normalize(standard)
 const ai=await gradeWithAI({answer,standardAnswer:standard,context:String(body.hint||'')})
 if(ai)return NextResponse.json({...ai,source:'ai'})
 const result:{verdict:Verdict;correctedAnswer:string;errorTags:string[];explanation:string;hint?:string;acceptedAlternatives?:string[]}={
  verdict:exact?'correct':'needs_fix', correctedAnswer:standard, errorTags:exact?[]:['句型顺序'], explanation:exact?'句型结构正确，继续保持主动输出。':'先对照句型骨架检查助词、否定形式和句尾。', hint:body.hint
 }
 return NextResponse.json({...result,source:'rule'})
}
