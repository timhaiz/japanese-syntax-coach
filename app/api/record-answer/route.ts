import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'
import {nextReviewByVerdict, type ReviewVerdict} from '@/lib/review'

type Body={questionId?:string;lessonId?:number;answer?:string;correct?:boolean;verdict?:'correct'|'mostly_correct'|'needs_fix'|'incorrect';errorTags?:string[];knowledgeTags?:string[];mode?:'new'|'review'|'mistakes'|'lesson'|'lesson_replay'}
export async function POST(request:Request){
 const body=await request.json().catch(()=>({})) as Body
 if(!body.questionId||!Number.isInteger(body.lessonId)||typeof body.answer!=='string'||typeof body.correct!=='boolean'||!['new','review','mistakes','lesson','lesson_replay'].includes(body.mode??''))return NextResponse.json({error:'Invalid answer record'},{status:400})
 const supabase=await getSupabaseServer()
 if(!supabase)return NextResponse.json({error:'Supabase is not configured'},{status:503})
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 let {data,error}=await supabase.rpc('record_learning_attempt',{p_question_id:body.questionId,p_lesson_id:body.lessonId,p_answer:body.answer,p_correct:body.correct,p_error_tags:body.errorTags??[],p_mode:body.mode,p_verdict:body.verdict})
 if(error && /function|p_verdict|record_learning_attempt/i.test(error.message||'')) {
   const legacy=await supabase.rpc('record_learning_attempt',{p_question_id:body.questionId,p_lesson_id:body.lessonId,p_answer:body.answer,p_correct:body.correct,p_error_tags:body.errorTags??[],p_mode:body.mode})
   if(legacy.error)return NextResponse.json({error:'Unable to save answer record'},{status:500})
   data=legacy.data; error=null
   const verdict:ReviewVerdict=body.verdict??(body.correct?'correct':'incorrect')
   const reps=Number((legacy.data as {repetitions?:number})?.repetitions)||0
   const schedule=nextReviewByVerdict(reps,verdict)
   await supabase.from('question_review_state').update({repetitions:schedule.reps,interval_days:schedule.intervalDays,next_review_at:schedule.dueAt,updated_at:new Date().toISOString()}).eq('question_id',body.questionId).eq('user_id',user.id)
 }
 if(error)return NextResponse.json({error:'Unable to save answer record'},{status:500})
 await supabase.rpc('record_knowledge_point_attempt',{p_question_correct:body.correct,p_error_tags:body.errorTags??[],p_knowledge_tags:body.knowledgeTags??[]})
 return NextResponse.json({record:data})
}
