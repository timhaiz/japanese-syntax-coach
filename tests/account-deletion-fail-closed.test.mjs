import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

test('web deletion handler confirms and calls /api/account/delete before clearing state', () => {
  const source = read('app/page.tsx')
  const handler = source.split('  const deleteAccount = useCallback(')[1].split('  const loadedStudyUserId')[0]
  assert.match(handler, /window\.confirm/)
  assert.match(handler, /fetch\('\/api\/account\/delete'/)
  assert.match(handler, /confirmation:\s*'DELETE'/)
})

test('iOS deletion entry confirms and delegates to deleteAccountWhenSafe', () => {
  const view = read('ios/JapaneseSyntaxCoach/Billing/AccountView.swift')
  assert.match(view, /confirmationDialog/)
  assert.match(view, /learning\.deleteAccount\(\)/)
  assert.doesNotMatch(view, /learning\.clearUserScopedData\(\)/)
  const store = read('ios/JapaneseSyntaxCoach/Learning/LearningStore.swift')
  const entry = store.split('    func deleteAccount() async throws {')[1].split('    private func deleteAccountWhenSafe')[0]
  assert.match(entry, /try await deleteAccountWhenSafe\(\)/)
})

test('server delegates POST to deleteAccountWhenSafe with confirmation check', () => {
  const route = read('app/api/account/delete/route.ts')
  assert.match(route, /export async function POST\(request: Request\)\s*\{\s*return deleteAccountWhenSafe\(request\)/)
  assert.match(route, /body\.confirmation !== 'DELETE'/)
  assert.match(route, /delete_current_authenticated_user/)
})
