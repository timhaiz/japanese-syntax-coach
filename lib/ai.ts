export type GradeResult={verdict:'correct'|'mostly_correct'|'needs_fix'|'incorrect';correctedAnswer:string;errorTags:string[];explanation:string;hint?:string;acceptedAlternatives?:string[]}
export async function gradeWithAI(input:{answer:string;standardAnswer:string;context?:string}):Promise<GradeResult|null>{
 const key=process.env.OPENAI_API_KEY;if(!key)return null
 const model=process.env.OPENAI_MODEL||'gpt-4o-mini'
 const prompt=`你是日语教练。仅根据已学范围批改。标准答案：${input.standardAnswer}\n用户答案：${input.answer}\n课程上下文：${input.context||''}\n返回严格JSON，字段 verdict(correct|mostly_correct|needs_fix|incorrect), correctedAnswer, errorTags(助词/活用/句型顺序/词汇/假名/语义/自然度), explanation, hint。标点省略视为正确。`
 const res=await fetch('https://api.openai.com/v1/chat/completions',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${key}`},body:JSON.stringify({model,temperature:0.1,response_format:{type:'json_object'},messages:[{role:'user',content:prompt}]})}).catch(()=>null)
 if(!res?.ok)return null
 const data=await res.json();try{return JSON.parse(data.choices?.[0]?.message?.content||'')}catch{return null}
}
