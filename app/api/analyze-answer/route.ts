import {NextResponse} from 'next/server'

const isAnalysisResult=(value:unknown):value is {analysis:string;words:{word:string;kana:string;meaning:string;memory:string}[];pitfalls:string[]}=>{
  if(!value||typeof value!=='object')return false
  const result=value as {analysis?:unknown;words?:unknown;pitfalls?:unknown}
  if(typeof result.analysis!=='string'||!Array.isArray(result.words)||!Array.isArray(result.pitfalls))return false
  return result.words.every(item=>{if(!item||typeof item!=='object')return false;const word=item as Record<string,unknown>;return ['word','kana','meaning','memory'].every(key=>typeof word[key]==='string')})&&result.pitfalls.every(item=>typeof item==='string')
}

export async function POST(req:Request){
  const body=await req.json().catch(()=>({})) as {prompt?:string;answer?:string;standardAnswer?:string;hint?:string}
  const key=process.env.OPENAI_API_KEY
  if(!key)return NextResponse.json({analysis:'AI 分析未配置：缺少 OPENAI_API_KEY。',source:'fallback',reason:'missing-api-key'})
  const prompt=`你是中文用户的日语记忆教练。请分析这道题，帮助用户记忆，不要重新判分。题目：${body.prompt||''}\n用户答案：${body.answer||''}\n标准答案：${body.standardAnswer||''}\n原有提示：${body.hint||''}\n请严格返回 JSON：{"analysis":"用简体中文说明记忆方法，最多 120 字","words":[{"word":"日语词","kana":"假名","meaning":"中文义","memory":"简短记法"}],"pitfalls":["易错点"]}。只分析题目中出现的词和句型，不引入超纲语法。`
  try{
    const baseUrl=(process.env.OPENAI_BASE_URL||'https://api.openai.com/v1').replace(/\/$/,'')
    // Third-party compatible endpoints may need a few extra seconds on cold start.
    const response=await fetch(`${baseUrl}/responses`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${key}`},body:JSON.stringify({model:process.env.OPENAI_MODEL||'gpt-5.4-mini',input:prompt,store:false}),signal:AbortSignal.timeout(20000)})
    if(!response.ok)return NextResponse.json({analysis:`AI 服务返回 ${response.status}，请检查第三方接口地址、Key、模型名和额度。`,source:'fallback',reason:`upstream-${response.status}`})
    const data=await response.json();const outputText=data.output_text||data.output?.flatMap((item:{content?:{text?:string}[]})=>item.content||[]).map((item:{text?:string})=>item.text||'').join('')||''
    let parsed:unknown
    try{parsed=JSON.parse(outputText||'{}')}catch{return NextResponse.json({analysis:'AI 返回的内容不是合法 JSON，请稍后重试；你仍可使用规则批改结果。',source:'fallback',reason:'invalid-json'})}
    if(!isAnalysisResult(parsed))return NextResponse.json({analysis:'AI 返回格式不完整，请对照标准答案拆分短语、助词和假名记忆。',source:'fallback',reason:'invalid-response-shape'})
    return NextResponse.json({...parsed,source:'ai'})
  }catch(error){
    const reason=error instanceof DOMException&&error.name==='TimeoutError'?'timeout':'network-error'
    return NextResponse.json({analysis:reason==='timeout'?'AI 分析响应超时，请稍后重试。':'无法连接 AI 服务，请检查 OPENAI_BASE_URL 是否为第三方接口的 /v1 地址。',source:'fallback',reason})
  }
}
