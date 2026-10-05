import { expect, test } from '@playwright/test'
import { parseTextbookJson } from '../../lib/textbook-import'
import { builtInTextbookPackage } from '../../lib/textbooks'

const createPackage = (id: string, title: string) => ({
  schemaVersion: 1,
  textbook: {
    id,
    title,
    description: '导入隔离测试',
    lessons: [
      {
        id: 1,
        title: '判断句',
        goal: '练习简单判断句。',
        grammar: [
          {
            pattern: 'N は N です。',
            meaning: 'N 是 N。',
            example: '私は学生です。',
            connection: '名词 + は + 名词 + です。',
            explanation: '用来说明身份。',
          },
        ],
      },
    ],
    questions: [1, 2, 3].map((number) => ({
      id: `shared-question-${number}`,
      lessonId: 1,
      type: '选择',
      prompt: `第 ${number} 道测试题`,
      answer: 'A',
      hint: '选择正确选项。',
      options: ['A：正确答案', 'B：错误答案'],
    })),
  },
})

test('兼容计划格式：教材元数据与课内题目会归一化到运行格式', () => {
  const result = parseTextbookJson(JSON.stringify({
    schemaVersion: 1,
    textbook: {
      id: 'plan-format-book',
      title: '计划格式教材',
      shortTitle: '计划教材',
      description: '课程说明',
    },
    lessons: [{
      id: 1,
      title: '初次见面',
      description: '练习判断句。',
      questions: [{
        id: 'plan-q1',
        type: '翻译',
        prompt: '我是学生。',
        answer: '私は学生です。',
        hint: '名词句',
      }],
    }],
  }))

  expect(result.success).toBeTruthy()
  if (!result.success) return
  expect(result.data.textbook.lessons[0].goal).toBe('练习判断句。')
  expect(result.data.textbook.questions[0].lessonId).toBe(1)
})

test('拒绝不受支持的远程封面地址', () => {
  const result = parseTextbookJson(JSON.stringify({
    ...createPackage('remote-cover-book', '远程封面'),
    textbook: { ...createPackage('remote-cover-book', '远程封面').textbook, cover: 'https://example.com/book.png' },
  }))
  expect(result.success).toBeFalsy()
  if (!result.success) expect(result.errors.join(' ')).toContain('cover')
})

test('内置教材对应新版标准日本语初级上册', () => {
  expect(builtInTextbookPackage.textbook.title).toBe('新版标准日本语 初级上册')
  expect(builtInTextbookPackage.textbook.lessons).toHaveLength(24)
})

async function uploadPackage(
  page: import('@playwright/test').Page,
  id: string,
  title: string,
) {
  await page.goto('/textbooks')
  await page.locator('input[type="file"]').setInputFiles({
    name: `${id}.json`,
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(createPackage(id, title))),
  })
  await expect(page.getByText(title, { exact: true })).toBeVisible()
}

async function chooseTextbook(page: import('@playwright/test').Page, title: string) {
  const card = page.locator('.textbook-card').filter({ hasText: title })
  await expect(card).toBeVisible()
  await card.getByRole('button').click()
}

test('schemaVersion 1 教材导入后可选并显示真实题数', async ({ page }) => {
  await uploadPackage(page, 'test-imported-book', '导入测试教材')
  await page.goto('/')
  await page.goto('/textbooks')
  await chooseTextbook(page, '导入测试教材')
  await page.goto('/')
  await page.getByRole('navigation', { name: '主导航' }).getByRole('button', { name: /课程/ }).click()
  await page.getByRole('button', { name: /第 1 课：判断句/ }).click()
  await expect(page.getByRole('button', { name: /开始整课练习（3 题）/ })).toBeVisible()
})

test('拒绝非法版本的 JSON，且不加入教材列表', async ({ page }) => {
  await page.goto('/textbooks')
  await page.locator('input[type="file"]').setInputFiles({
    name: 'bad.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify({ schemaVersion: 9, textbook: {} })),
  })

  await expect(page.locator('.textbook-library-error')).toContainText('schemaVersion')
  await expect(page.getByText('新版标准日本语 初级上册', { exact: true })).toHaveCount(1)
})

test('切换教材隔离同 ID 题目的本地进度并恢复原教材', async ({ page }) => {
  await uploadPackage(page, 'test-book-a', '教材 A')
  await uploadPackage(page, 'test-book-b', '教材 B')
  await chooseTextbook(page, '教材 A')
  await page.goto('/')

  await page.getByRole('navigation', { name: '主导航' }).getByRole('button', { name: /课程/ }).click()
  await page.getByRole('button', { name: /第 1 课：判断句/ }).click()
  await page.getByRole('button', { name: /开始整课练习（3 题）/ }).click()
  await page.getByRole('button', { name: 'A：正确答案' }).click()
  await page.getByRole('button', { name: /提交答案/ }).click()
  await page.getByRole('button', { name: /下一题/ }).click()

  await page.goto('/textbooks')
  await chooseTextbook(page, '教材 B')
  await page.goto('/')
  await page.getByRole('navigation', { name: '主导航' }).getByRole('button', { name: /课程/ }).click()
  await page.getByRole('button', { name: /第 1 课：判断句/ }).click()
  await expect(page.getByText(/已作答 0 \/ 3/)).toBeVisible()

  await page.goto('/textbooks')
  await chooseTextbook(page, '教材 A')
  await page.goto('/')
  await page.getByRole('navigation', { name: '主导航' }).getByRole('button', { name: /课程/ }).click()
  await page.getByRole('button', { name: /第 1 课：判断句/ }).click()
  await expect(page.getByText(/已作答 1 \/ 3/)).toBeVisible()
})
