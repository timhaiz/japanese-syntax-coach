import {createServerClient} from '@supabase/ssr'
import {createClient, type SupabaseClient} from '@supabase/supabase-js'
import {cookies} from 'next/headers'

export async function getSupabaseServer(request?: Request): Promise<SupabaseClient | null>{
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL
 const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
 if(!url||!key)return null
 const authorization=request?.headers.get('authorization')?.trim()
 if(authorization){
  const match=authorization.match(/^Bearer\s+(\S+)$/i)
  if(!match)return null
  return createClient(url,key,{global:{headers:{Authorization:`Bearer ${match[1]}`}},auth:{autoRefreshToken:false,persistSession:false}})
 }
 const store=await cookies()
 return createServerClient(url,key,{cookies:{getAll:()=>store.getAll(),setAll:items=>{try{items.forEach(({name,value,options})=>store.set(name,value,options))}catch{}}}})
}
