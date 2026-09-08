export type GradeResult={verdict:'correct'|'mostly_correct'|'needs_fix'|'incorrect';correctedAnswer:string;errorTags:string[];explanation:string;hint?:string;acceptedAlternatives?:string[]}
const isGradeResult=(value:unknown):value is GradeResult=>{
 if(!value||typeof value!=='object')return false
 const result=value as Record<string,unknown>
 return ['correct','mostly_correct','needs_fix','incorrect'].includes(String(result.verdict))&&typeof result.correctedAnswer==='string'&&typeof result.explanation==='string'&&Array.isArray(result.errorTags)&&result.errorTags.every(tag=>typeof tag==='string')
}
export async function gradeWithAI(input:{answer:string;standardAnswer:string;context?:string}):Promise<GradeResult|null>{
 const key=process.env.OPENAI_API_KEY;if(!key)return null
 const model=process.env.OPENAI_MODEL||'gpt-5.4-mini'
 const baseUrl=(process.env.OPENAI_BASE_URL||'https://api.openai.com/v1').replace(/\/$/,'')
 const prompt=`你是日语教练。仅根据已学范围批改。标准答案：${input.standardAnswer}\n用户答案：${input.answer}\n课程上下文：${input.context||''}\n返回严格JSON，字段 verdict(correct|mostly_correct|needs_fix|incorrect), correctedAnswer, errorTags(助词/活用/句型顺序/词汇/假名/语义/自然度), explanation, hint。标点省略视为正确。`
 const res=await fetch(`${baseUrl}/responses`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${key}`},body:JSON.stringify({model,input:prompt,store:false}),signal:AbortSignal.timeout(8000)}).catch(()=>null)
 if(!res?.ok){console.warn('AI grading request failed',res?.status??'network-error');return null}
 const data=await res.json();try{const text=data.output_text||data.output?.flatMap((item:{content?:{text?:string}[]})=>item.content||[]).map((item:{text?:string})=>item.text||'').join('')||'';const parsed=JSON.parse(text);return isGradeResult(parsed)?parsed:null}catch{return null}
}
