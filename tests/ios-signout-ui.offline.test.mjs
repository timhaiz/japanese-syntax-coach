import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const account = await readFile(new URL('../ios/JapaneseSyntaxCoach/Billing/AccountView.swift', import.meta.url), 'utf8')
const learning = await readFile(new URL('../ios/JapaneseSyntaxCoach/Learning/LearningStore.swift', import.meta.url), 'utf8')

test('退出按钮不提前清空学习状态，清理由会话变化驱动', () => {
  assert.doesNotMatch(account, /learning\.clearUserScopedData\(\)/)
  assert.match(account, /await auth\.signOut\(\)/)
  assert.match(learning, /auth\.\$session\.sink/)
  assert.match(learning, /guard let key = Self\.accountKey\(session\?\.userID\) else \{\s*clearUserScopedData\(\)/)
})
