import {createServerClient} from '@supabase/ssr'
import {createClient, type SupabaseClient} from '@supabase/supabase-js'
import {cookies} from 'next/headers'

export function parseBearerToken(authorization: string | null | undefined): string | null {
 const match=authorization?.trim().match(/^Bearer\s+(\S+)$/i)
 return match?.[1] ?? null
}

export async function getSupabaseServer(request?: Request): Promise<SupabaseClient | null>{
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL
 const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
 if(!url||!key)return null
 const authorization=request?.headers.get('authorization')
 if(authorization!==undefined&&authorization!==null){
  const token=parseBearerToken(authorization)
  if(!token)return null
  return createClient(url,key,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{autoRefreshToken:false,persistSession:false}})
 }
 const store=await cookies()
 return createServerClient(url,key,{cookies:{getAll:()=>store.getAll(),setAll:items=>{try{items.forEach(({name,value,options})=>store.set(name,value,options))}catch{}}}})
}
