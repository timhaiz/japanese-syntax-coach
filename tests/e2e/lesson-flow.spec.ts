import {test,expect} from '@playwright/test'

test.beforeEach(async({page})=>{
  await page.goto('/')
  await page.evaluate(()=>localStorage.clear())
  await page.reload()
})

test('首页入口会进入今日新题模式',async({page})=>{
  await expect(page.getByText('今天完成 10 道主动输出练习，约需 20 分钟。')).toBeVisible()
  await page.getByRole('button',{name:/开始今日训练/}).click()
  await expect(page.getByText('第 1 课 · 练习')).toBeVisible()
  await expect(page.getByText('1 / 10')).toBeVisible()
})

test('漏写句号仍判定正确并显示标点提醒',async({page})=>{
  await page.getByRole('button',{name:/开始今日训练/}).click()
  await page.locator('textarea').fill('私は学生です')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
  await expect(page.getByText('下次书写时不要忘记写标点符号。')).toBeVisible()
})

test('答错后进入错题本并可独立练习',async({page})=>{
  await page.getByRole('button',{name:/开始今日训练/}).click()
  await page.locator('textarea').fill('完全不同的答案')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('△ 句型或词语还需要调整')).toBeVisible()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByText('我是学生。')).toBeVisible()
  await page.getByRole('button',{name:/开始错题练习/}).click()
  await page.locator('textarea').fill('私は学生です。')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/完成训练/}).click()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByText('目前没有错题')).toBeVisible()
})

test('完成第 1 课 10 题后才解锁第 2 课',async({page})=>{
  await page.getByRole('button',{name:/开始今日训练/}).click()
  for(let i=0;i<10;i++){
    await page.locator('textarea').fill(`答案 ${i}`)
    await page.getByRole('button',{name:/^提交答案/}).click()
    await page.getByRole('button',{name:i===9?/完成训练/:/下一题/}).click()
  }
  await page.getByRole('button',{name:/课程/}).click()
  const lesson2=page.getByRole('button',{name:/02 第 2 课/})
  await expect(lesson2).toBeVisible()
  await expect(lesson2).not.toContainText('🔒')
})

test('刷新后保留当日训练进度',async({page})=>{
  await page.getByRole('button',{name:/开始今日训练/}).click()
  await page.locator('textarea').fill('答案')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/下一题/}).click()
  await page.reload()
  await expect(page.getByText('今日 1 / 10')).toBeVisible()
})

test('注册表单要求邮箱和匹配的密码',async({page})=>{
  await page.goto('/login')
  await page.getByRole('button',{name:'注册'}).first().click()
  await page.getByPlaceholder('邮箱').fill('new-user@example.com')
  await page.getByPlaceholder('设置密码（至少 6 位）').fill('123456')
  await page.getByPlaceholder('再次输入密码').fill('654321')
  await page.locator('button.primary').click()
  await expect(page.getByText('两次输入的密码不一致。')).toBeVisible()
})

test('旧账号可以进入设置密码邮件流程',async({page})=>{
  await page.goto('/login')
  await page.getByRole('button',{name:'忘记密码'}).click()
  await expect(page.getByText('旧账号没有密码？输入注册邮箱，我们会发送一封仅用于设置密码的邮件。')).toBeVisible()
  await page.getByRole('button',{name:/发送设置密码邮件/}).click()
  await expect(page.getByText('请输入需要设置密码的邮箱。')).toBeVisible()
})

test('未登录时个人页不会显示已同步',async({page})=>{
  await page.getByRole('button',{name:/我的/}).click()
  await expect(page.getByText('尚未登录')).toBeVisible()
  await expect(page.getByText('登录后同步',{exact:true})).toBeVisible()
  await expect(page.getByText('学习记录已同步到云端。')).not.toBeVisible()
})
