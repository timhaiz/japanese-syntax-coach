import {NextResponse} from 'next/server'
import {getSupabaseServer,parseBearerToken} from '@/lib/supabase-server'

export async function getAuthenticatedSupabase(request: Request){
 const supabase=await getSupabaseServer(request)
 if(!supabase)return {response:NextResponse.json({error:'Unauthorized'},{status:401})}
 const authorization=request.headers.get('authorization')
 const token=parseBearerToken(authorization)
 const {data:{user}}=token
  ?await supabase.auth.getUser(token)
  :authorization===null
   ?await supabase.auth.getUser()
   :{data:{user:null}}
 if(!user)return {response:NextResponse.json({error:'Unauthorized'},{status:401})}
 return {supabase,user}
}

