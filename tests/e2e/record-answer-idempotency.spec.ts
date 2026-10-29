import {test, expect} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'

const migrationPath = 'supabase/migrations/202610291400_native_answer_idempotency.sql'

test('idempotency: 答题记录 API 声明原生请求幂等契约', () => {
  const source = readFileSync(resolve(process.cwd(), 'app/api/record-answer/route.ts'), 'utf8')
  expect(source).toContain('clientRequestId')
  expect(source).toContain('duplicate')
  expect(source).toContain('record_textbook_learning_attempt_idempotent')
  expect(source).toContain('p_user_id: user.id')
  expect(source).toContain('status: 503')
  expect(source.indexOf('Invalid client request ID')).toBeLessThan(source.indexOf('const authenticated = await getAuthenticatedSupabase'))
})

test('idempotency: 答题幂等迁移使用用户范围唯一键和持久化响应', () => {
  const migration = readFileSync(resolve(process.cwd(), migrationPath), 'utf8')
  expect(migration).toContain('create table')
  expect(migration).toMatch(/primary key\s*\(user_id, client_request_id\)|unique\s*\(user_id, client_request_id\)/i)
  expect(migration).toMatch(/user_id[\s\S]*client_request_id/)
  expect(migration).toContain('record jsonb')
  expect(migration).toContain('auth.uid()')
  expect(migration).toContain('on conflict')
  expect(migration).toContain('for update')
  expect(migration).toContain('security definer')
  expect(migration).toContain('set search_path = pg_catalog, public')
  expect(migration).toContain('revoke all on table public.answer_request_idempotency from public, anon, authenticated')
  expect(migration).toContain('revoke all on function public.record_textbook_learning_attempt_idempotent(')
  expect(migration).toContain('grant execute on function public.record_textbook_learning_attempt_idempotent(')
  expect(migration).toContain('to authenticated')
  expect(migration).toContain('public.record_textbook_learning_attempt(')
  expect(migration).toContain('p_user_id <> auth.uid()')
})
