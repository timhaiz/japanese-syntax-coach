import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'

type Body={questionId?:string;lessonId?:number;answer?:string;correct?:boolean;errorTags?:string[];mode?:'new'|'review'|'mistakes'}
export async function POST(request:Request){
 const body=await request.json().catch(()=>({})) as Body
 if(!body.questionId||!Number.isInteger(body.lessonId)||typeof body.answer!=='string'||typeof body.correct!=='boolean'||!['new','review','mistakes'].includes(body.mode??''))return NextResponse.json({error:'Invalid answer record'},{status:400})
 const supabase=await getSupabaseServer()
 if(!supabase)return NextResponse.json({error:'Supabase is not configured'},{status:503})
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 const {data,error}=await supabase.rpc('record_learning_attempt',{p_question_id:body.questionId,p_lesson_id:body.lessonId,p_answer:body.answer,p_correct:body.correct,p_error_tags:body.errorTags??[],p_mode:body.mode})
 if(error)return NextResponse.json({error:'Unable to save answer record'},{status:500})
 return NextResponse.json({record:data})
}
