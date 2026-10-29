import {NextResponse} from 'next/server'
import {getSupabaseServer} from '@/lib/supabase-server'

export async function getAuthenticatedSupabase(request: Request){
 const supabase=await getSupabaseServer(request)
 if(!supabase)return {response:NextResponse.json({error:'Unauthorized'},{status:401})}
 const {data:{user}}=await supabase.auth.getUser()
 if(!user)return {response:NextResponse.json({error:'Unauthorized'},{status:401})}
 return {supabase,user}
}

