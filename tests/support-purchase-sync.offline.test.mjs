import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const source = readFileSync(new URL('../app/support/page.tsx', import.meta.url), 'utf8')
const purchaseSync = source.match(/<li>购买记录同步：([^<]*)<\/li>/)?.[1]

test('购买记录同步说明谨慎表达并指引用户联系支持', () => {
  assert.ok(purchaseSync, '应包含购买记录同步说明')
  assert.match(purchaseSync, /尝试保留待确认购买/)
  assert.match(purchaseSync, /同步受阻时.*保留当前设备.*联系.*支持/)
  assert.doesNotMatch(purchaseSync, /不会丢失|一定安全|自动重试|自动恢复|卸载|清理/)
})
