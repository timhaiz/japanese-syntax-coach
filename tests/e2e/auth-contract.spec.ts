import {test, expect} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'

test('Bearer authentication contract is wired through protected APIs',()=>{
  const source=readFileSync(resolve(process.cwd(),'lib/supabase-server.ts'),'utf8')
  expect(source).toContain("request?.headers.get('authorization')")
  expect(source).toContain('Bearer')
  expect(source).toContain('auth: {autoRefreshToken:false,persistSession:false}')
  const helper=readFileSync(resolve(process.cwd(),'lib/auth/request-supabase.ts'),'utf8')
  expect(helper).toContain('auth.getUser()')
  for(const route of ['study-state','record-answer','apple/entitlements','account/delete','tts/generate','tts/audio','tts/manifest']){
    const routeSource=readFileSync(resolve(process.cwd(),`app/api/${route}/route.ts`),'utf8')
    expect(routeSource).toContain('getAuthenticatedSupabase(request)')
    expect(routeSource).not.toMatch(/body\.userId|searchParams\.get\(['"]userId/)
  }
})
