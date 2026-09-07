import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'

type Body={newDelta?:number;reviewDelta?:number;minuteDelta?:number;claim?:'new'|'review'|'time'|'bonus'}
export async function POST(request:Request){
 const body=await request.json().catch(()=>({})) as Body
 const supabase=await getSupabaseServer()
 if(!supabase)return NextResponse.json({error:'Supabase is not configured'},{status:503})
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 const validDelta=(value:unknown)=>Number.isInteger(value)&&Number(value)>=0&&Number(value)<=5?Number(value):0
 const {data,error}=await supabase.rpc('update_daily_learning_progress',{p_new_delta:validDelta(body.newDelta),p_review_delta:validDelta(body.reviewDelta),p_minute_delta:validDelta(body.minuteDelta),p_claim:body.claim??null})
 if(error)return NextResponse.json({error:'Unable to update daily progress'},{status:500})
 return NextResponse.json({daily:data})
}
