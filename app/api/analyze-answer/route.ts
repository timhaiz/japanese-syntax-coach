import {NextResponse} from 'next/server'
import OpenAI, {APIConnectionTimeoutError} from 'openai'

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
  const userAgent=req.headers.get('user-agent')||undefined
  const prompt=`日语记忆教练。只分析题目中的词和句型，不重新判分，不引入超纲语法。题目：${body.prompt||''}\n用户答案：${body.answer||''}\n标准答案：${body.standardAnswer||''}\n提示：${body.hint||''}\n只返回 JSON：{"analysis":"简体中文记忆法，80字以内","words":[{"word":"词","kana":"假名","meaning":"中文","memory":"记法"}],"pitfalls":["易错点"]}。words最多5个，pitfalls最多2个。`
  try{
    const baseUrl=(process.env.OPENAI_BASE_URL||'https://api.openai.com/v1').replace(/\/$/,'')
    // Third-party compatible endpoints may need a few extra seconds on cold start.
    const client=new OpenAI({apiKey:key,baseURL:baseUrl,timeout:15000,maxRetries:0,defaultHeaders:userAgent?{'User-Agent':userAgent}:undefined})
    const stream=await client.responses.create({model:process.env.OPENAI_MODEL||'gpt-5.4-mini',input:prompt,store:false,stream:true,max_output_tokens:350})
    const encoder=new TextEncoder()
    const readable=new ReadableStream({
      async start(controller){
        try{
          for await(const event of stream){
            if(event.type==='response.output_text.delta')controller.enqueue(encoder.encode(`data: ${JSON.stringify({type:'delta',text:event.delta})}\n\n`))
          }
          controller.enqueue(encoder.encode('data: {"type":"done"}\n\n'))
        }catch(error){
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({type:'error',message:error instanceof APIConnectionTimeoutError?'timeout':'network-error'})}\n\n`))
        }finally{controller.close()}
      },
    })
    return new Response(readable,{headers:{'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-cache, no-transform','Connection':'keep-alive'}})
  }catch(error){
    const reason=error instanceof APIConnectionTimeoutError?'timeout':'network-error'
    if(!reason||reason==='network-error'){
      const status=(error as {status?:number})?.status
      if(status===401||status===403)return NextResponse.json({analysis:'AI 鉴权失败，请检查 API Key。',source:'fallback',reason:`upstream-${status}`})
      if(status===429)return NextResponse.json({analysis:'AI 当前额度不足或请求过于频繁，请稍后重试。',source:'fallback',reason:'upstream-429'})
    }
    return NextResponse.json({analysis:reason==='timeout'?'AI 分析响应超时，请稍后重试。':'无法连接 AI 服务，请检查 OPENAI_BASE_URL 是否为第三方接口的 /v1 地址。',source:'fallback',reason})
  }
}
