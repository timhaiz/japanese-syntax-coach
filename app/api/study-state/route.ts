import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'

export async function GET(){
 const supabase=await getSupabaseServer()
 if(!supabase)return NextResponse.json({error:'Supabase is not configured'},{status:503})
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 const [due,completed,mastery,attempts]=await Promise.all([
  supabase.from('question_review_state').select('question_id').lte('next_review_at',new Date().toISOString()).order('next_review_at',{ascending:true}).limit(5),
  supabase.from('lesson_progress').select('lesson_id,answered_count,correct_count,completed_at').order('lesson_id',{ascending:true}),
  supabase.from('knowledge_point_mastery').select('knowledge_point,attempts,correct_attempts,mastery,last_answered_at').order('mastery',{ascending:true}),
  supabase.from('answer_attempts').select('exercise_id,verdict,error_tags,created_at').order('created_at',{ascending:false}).limit(500)
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
 const rows=attempts.error?[]:(attempts.data??[])
 let streak=0
 for(const row of rows){if(row.verdict==='correct')streak++;else break}
 const total=rows.length, incorrect=rows.filter(row=>row.verdict!=='correct').length
 const tagCounts=new Map<string,number>()
 for(const row of rows) for(const tag of row.error_tags??[]) tagCounts.set(tag,(tagCounts.get(tag)??0)+1)
 const topErrorTags=[...tagCounts.entries()].sort((a,b)=>b[1]-a[1]).slice(0,5).map(([tag,count])=>({tag,count}))
 const seenCorrect=new Set<string>(); let eligibleReviews=0; let forgotten=0
 for(const row of [...rows].reverse()){
  const questionId=(row as {exercise_id?:string}).exercise_id
  if(!questionId) continue
  if(row.verdict==='correct') seenCorrect.add(questionId)
  else if(seenCorrect.has(questionId)){ eligibleReviews++; forgotten++ }
 }
 const forgettingRate=eligibleReviews?Math.round(forgotten/eligibleReviews*100):0
 return NextResponse.json({dueQuestionIds:(due.data??[]).map(item=>item.question_id),lessons,knowledgePoints:mastery.error?[]:(mastery.data??[]),metrics:{totalAttempts:total,incorrectAttempts:incorrect,errorRate:total?Math.round(incorrect/total*100):0,forgettingRate,correctStreak:streak,topErrorTags}})
}
