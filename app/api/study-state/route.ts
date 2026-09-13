import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'

export async function GET(){
 const supabase=await getSupabaseServer()
 if(!supabase)return NextResponse.json({error:'Supabase is not configured'},{status:503})
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 const [due,completed]=await Promise.all([
  supabase.from('question_review_state').select('question_id').lte('next_review_at',new Date().toISOString()).order('next_review_at',{ascending:true}).limit(5),
  supabase.from('lesson_progress').select('lesson_id,answered_count,correct_count,completed_at').order('lesson_id',{ascending:true})
 ])
 if(due.error||completed.error)return NextResponse.json({error:'Unable to load study state'},{status:500})
 // Older clients could increment this counter past the 20-question lesson limit.
 // Normalize it at the API boundary so every client renders a valid lesson state
 // without mutating or deleting the user's historical rows.
 const lessons=(completed.data??[]).map((lesson)=>({
  ...lesson,
  answered_count:Math.max(0,Math.min(20,Number(lesson.answered_count)||0)),
  correct_count:Math.max(0,Math.min(20,Number(lesson.correct_count)||0)),
 }))
 return NextResponse.json({dueQuestionIds:(due.data??[]).map(item=>item.question_id),lessons})
}
