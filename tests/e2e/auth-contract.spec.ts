import {test, expect} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'
import {parseBearerToken} from '../../lib/supabase-server'
import {accountTokenBelongsToUser} from '../../lib/apple/account-token'

test('Bearer parser accepts only non-empty Bearer tokens',()=>{
  expect(parseBearerToken('Bearer abc')).toBe('abc')
  expect(parseBearerToken('bearer abc')).toBe('abc')
  expect(parseBearerToken('Bearer')).toBeNull()
  expect(parseBearerToken('Bearer   ')).toBeNull()
  expect(parseBearerToken('Basic abc')).toBeNull()
  expect(parseBearerToken(null)).toBeNull()
})

test('Bearer authentication contract is wired through protected APIs',()=>{
  const source=readFileSync(resolve(process.cwd(),'lib/supabase-server.ts'),'utf8')
  expect(source).toMatch(/request\?\.headers\.get\(['"]authorization['"]\)/)
  expect(source).toContain('Bearer')
  expect(source).toMatch(/auth\s*:\s*\{\s*autoRefreshToken\s*:\s*false\s*,\s*persistSession\s*:\s*false\s*\}/)
  const helper=readFileSync(resolve(process.cwd(),'lib/auth/request-supabase.ts'),'utf8')
  expect(helper).toMatch(/auth\.getUser\(\s*token\s*\)/)
  expect(helper).toMatch(/auth\.getUser\(\s*\)/)
  expect(helper).toContain('getSupabaseServer(request)')
  expect(helper).toMatch(/authorization[\s\S]*?token[\s\S]*?getUser\(\s*token\s*\)/)
  expect(helper).toMatch(/authorization[\s\S]*?getUser\(\s*\)/)
  for(const route of ['study-state','record-answer','apple/entitlements','account/delete','tts/generate','tts/audio','tts/manifest','review']){
    const routeSource=readFileSync(resolve(process.cwd(),`app/api/${route}/route.ts`),'utf8')
    expect(routeSource).toContain('getAuthenticatedSupabase(request)')
    expect(routeSource).not.toMatch(/body\.userId|searchParams\.get\(['"]userId/)
  }
  const reviewSource=readFileSync(resolve(process.cwd(),'app/api/review/route.ts'),'utf8')
  expect(reviewSource).toContain("'userId' in body")
  expect(reviewSource).toContain('userId: user.id')
})

test('Apple account token comparison ignores UUID letter case',()=>{
  const userId='3f7c1a2e-5b6d-4c8e-9a01-2b3c4d5e6f70'
  expect(accountTokenBelongsToUser(userId,userId)).toBe(true)
  expect(accountTokenBelongsToUser(userId.toUpperCase(),userId)).toBe(true)
  expect(accountTokenBelongsToUser(` ${userId.toUpperCase()} `,userId)).toBe(true)
  expect(accountTokenBelongsToUser('3f7c1a2e-5b6d-4c8e-9a01-2b3c4d5e6f71',userId)).toBe(false)
  // A transaction without an account token claims no ownership.
  expect(accountTokenBelongsToUser(undefined,userId)).toBe(true)
  expect(accountTokenBelongsToUser('',userId)).toBe(true)
})

test('Apple entitlement route compares the account token case-insensitively',()=>{
  const routeSource=readFileSync(resolve(process.cwd(),'app/api/apple/entitlements/route.ts'),'utf8')
  expect(routeSource).toContain('accountTokenBelongsToUser')
  expect(routeSource).not.toMatch(/appAccountToken\s*!==\s*user\.id/)
})
