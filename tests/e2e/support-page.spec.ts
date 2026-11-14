import {test,expect} from '@playwright/test'

const SUPPORT_EMAIL = 'service@niixmiro.com'

test('支持页面提供联系方式与账号注销入口',async({page})=>{
  await page.goto('/support')
  await expect(page.getByRole('heading',{name:'支持与帮助'})).toBeVisible()
  const mailto=page.locator(`a[href="mailto:${SUPPORT_EMAIL}"]`)
  await expect(mailto).toHaveCount(1)
  await expect(mailto).toHaveText(SUPPORT_EMAIL)
})

test('支持页面说明账号注销方式与恢复购买入口',async({page})=>{
  await page.goto('/support')
  await expect(page.getByText('账户 → 删除账号', { exact: false })).toBeVisible()
  await expect(page.getByText('恢复购买').first()).toBeVisible()
})

test('支持页面与隐私政策互相可达且说明注销方式',async({page})=>{
  await page.goto('/support')
  await expect(page.locator('a[href="/privacy"]')).not.toHaveCount(0)
  await expect(page.locator('a[href="/terms"]')).not.toHaveCount(0)

  await page.goto('/privacy')
  await expect(page.getByRole('heading',{name:'隐私政策'})).toBeVisible()
  await expect(page.getByText('账户 → 删除账号', { exact: false })).toBeVisible()
  await expect(page.locator('a[href="/support"]')).not.toHaveCount(0)
})
