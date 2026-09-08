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
 return NextResponse.json({dueQuestionIds:(due.data??[]).map(item=>item.question_id),lessons:completed.data??[]})
}
