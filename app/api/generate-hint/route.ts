import {NextResponse} from 'next/server'
export async function POST(req:Request){const b=await req.json().catch(()=>({}));return NextResponse.json({hint:b.hint||'先回忆句型骨架，再替换名词或动词。',source:'rule-fallback'})}
