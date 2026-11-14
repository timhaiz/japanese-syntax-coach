import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const component = await readFile(new URL('../components/AppleSubscriptionControls.tsx', import.meta.url), 'utf8')
const page = await readFile(new URL('../app/subscription/page.tsx', import.meta.url), 'utf8')
const support = await readFile(new URL('../app/support/page.tsx', import.meta.url), 'utf8')
const terms = await readFile(new URL('../app/terms/page.tsx', import.meta.url), 'utf8')
const nativeSubscription = await readFile(new URL('../ios/JapaneseSyntaxCoach/Billing/SubscriptionView.swift', import.meta.url), 'utf8')

test('原生页不暗示手动重试一定能解决同步', () => {
  assert.doesNotMatch(nativeSubscription, /无法自动同步，需要手动重试/)
  assert.match(nativeSubscription, /无法自动同步，请保留记录/)
})

test('网页支持新购买、恢复购买与 Apple 订阅管理', () => {
  assert.match(component, /type:\s*['"]purchase['"]/)
  assert.match(component, /type:\s*['"]restore['"]/)
  assert.match(component, /type:\s*['"]manageSubscriptions['"]/)
})

test('订阅页面说明美元方案与恢复购买同步规则', () => {
  assert.match(page, /\$0\.99/)
  assert.match(page, /\$6\.59/)
  assert.match(page, /恢复购买会重新验证 Apple 交易，并将会员状态同步到当前账号/)
  assert.match(page, /会员权益持续到当前 Apple 账单周期结束/)
})

test('支持页面说明美元订阅方案与恢复购买操作', () => {
  assert.match(support, /\$0\.99\/月/)
  assert.match(support, /\$6\.59\/年/)
  assert.match(support, /先在「账户 → 订阅与购买」点一次「恢复购买」/)
})

test('服务条款说明月度与年度美元订阅方案', () => {
  assert.match(terms, /当前提供月度会员（\$0\.99\/月）和年度会员（\$6\.59\/年）/)
})
