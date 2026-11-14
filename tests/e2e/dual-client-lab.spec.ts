import {writeFileSync} from 'node:fs'
import {expect, test} from '@playwright/test'

test('authenticated learning UI loads atomic mistake state and opens its view', async ({page}) => {
  const email = process.env.LOCAL_DUAL_EMAIL
  const password = process.env.LOCAL_DUAL_PASSWORD
  if (!email || !password) throw new Error('isolated test credentials are missing')
  await page.goto('/login')
  await page.getByPlaceholder('邮箱').fill(email)
  await page.getByPlaceholder('密码').fill(password)
  const authResponse = page.waitForResponse(response => response.url().includes('/auth/v1/token'))
  await page.getByRole('button', {name: '登录 →', exact: true}).click()
  expect((await authResponse).status()).toBe(200)
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole('navigation', {name: '主导航'})).toBeVisible()
  await page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: /错题本/}).click()
  await expect(page.getByRole('heading', {name: '错题本'})).toBeVisible()
  await expect(page.getByText('目前没有错题')).toBeVisible()
})

test('authenticated learner submits an incorrect answer through the UI', async ({page}) => {
  const email = process.env.LOCAL_DUAL_EMAIL
  const password = process.env.LOCAL_DUAL_PASSWORD
  if (!email || !password) throw new Error('isolated test credentials are missing')
  await page.goto('/login')
  await page.getByPlaceholder('邮箱').fill(email)
  await page.getByPlaceholder('密码').fill(password)
  const authResponse = page.waitForResponse(response => response.url().includes('/auth/v1/token'))
  await page.getByRole('button', {name: '登录 →', exact: true}).click()
  expect((await authResponse).status()).toBe(200)
  await expect(page).toHaveURL(/\/$/)
  await page.getByRole('button', {name: /打开第 1 课/}).click()
  while (await page.getByRole('button', {name: /下一个/}).isVisible()) {
    await page.getByRole('button', {name: /下一个/}).click()
  }
  await page.getByRole('button', {name: /开始整课练习/}).click()
  const choices = page.getByRole('group', {name: '答案选项'})
  if (await choices.isVisible()) {
    await expect(choices.getByRole('button', {name: /^B：の/})).toBeVisible()
    await choices.getByRole('button', {name: /^A：は/}).click()
  } else {
    await page.locator('.token-bank button').first().click()
  }
  const recorded = page.waitForResponse(response => response.url().includes('/api/record-answer') && response.request().method() === 'POST')
  await page.getByRole('button', {name: /提交答案/}).click()
  const response = await recorded
  expect(response.ok()).toBeTruthy()
  expect(response.request().postDataJSON().correct).toBe(false)
  const questionId = response.request().postDataJSON().questionId
  expect(questionId).toMatch(/^L01-Q\d{3}$/)
  const markerPath = process.env.LOCAL_DUAL_QUESTION_MARKER
  if (markerPath) writeFileSync(markerPath, questionId, {mode: 0o600})
  await page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: /错题本/}).click()
  await expect(page.getByRole('button', {name: /开始错题练习/})).toBeVisible()
})

test('browser Cookie request races LearningStore Bearer request at the shared gate', async ({page}) => {
  test.setTimeout(300_000)
  const email = process.env.LOCAL_DUAL_EMAIL
  const password = process.env.LOCAL_DUAL_PASSWORD
  const resultPath = process.env.LOCAL_DUAL_WEB_RACE_RESULT
  if (!email || !password || !resultPath) throw new Error('isolated race settings are missing')
  await page.goto('/login')
  await page.getByPlaceholder('邮箱').fill(email)
  await page.getByPlaceholder('密码').fill(password)
  const authResponse = page.waitForResponse(response => response.url().includes('/auth/v1/token'))
  await page.getByRole('button', {name: '登录 →', exact: true}).click()
  expect((await authResponse).status()).toBe(200)
  await expect(page).toHaveURL(/\/$/)
  const gate = await page.evaluate(async () => {
    const response = await fetch('http://127.0.0.1:3220/ready/web', {method: 'POST'})
    return response.status
  })
  expect(gate).toBe(204)
  const response = await page.evaluate(async () => {
    const start = Date.now()
    const result = await fetch('/api/record-answer', {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify({textbookId:'builtin-japanese-syntax',questionId:'L01-Q008',lessonId:1,questionLimit:20,answer:'web concurrent answer',correct:false,mode:'new',errorTags:['lab-race'],knowledgeTags:[],clientRequestId:'dual-race-web',expectedMistakeVersion:0}),
    })
    return {status: result.status, start, end: Date.now()}
  })
  expect([200,409]).toContain(response.status)
  writeFileSync(resultPath, JSON.stringify(response), {mode: 0o600})
})

test('browser refresh confirms the iOS LearningStore cleared its mistake', async ({page}) => {
  const email = process.env.LOCAL_DUAL_EMAIL
  const password = process.env.LOCAL_DUAL_PASSWORD
  if (!email || !password) throw new Error('isolated test credentials are missing')
  await page.goto('/login')
  await page.getByPlaceholder('邮箱').fill(email)
  await page.getByPlaceholder('密码').fill(password)
  await page.getByRole('button', {name: '登录 →', exact: true}).click()
  await expect(page).toHaveURL(/\/$/)
  await page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: /错题本/}).click()
  await page.reload()
  await page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: /错题本/}).click()
  await expect(page.getByText('目前没有错题')).toBeVisible()
})
