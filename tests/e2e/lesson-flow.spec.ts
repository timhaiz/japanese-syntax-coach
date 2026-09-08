import {test,expect} from '@playwright/test'

async function passFirstChoice(page:any){
  for(let i=0;i<5;i++){
    const choices=page.locator('.choice-list button')
    if(!(await choices.count())) break
    await choices.nth(i===0?0:1).click()
    await page.getByRole('button',{name:/^提交答案/}).click()
    await page.getByRole('button',{name:/下一题|完成训练/}).click()
  }
}

test.beforeEach(async({page})=>{
  await page.goto('/')
  await page.evaluate(()=>localStorage.clear())
  await page.reload()
})

test('首页入口会进入当前课程整课练习',async({page})=>{
  await expect(page.getByText('完成本课 20 道题，正确率达到 90% 后解锁下一课。')).toBeVisible()
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await expect(page.getByText('第 1 课 · 练习')).toBeVisible()
  await expect(page.getByText('4 / 20')).toBeVisible()
})

test('漏写句号仍判定正确并显示标点提醒',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await page.locator('textarea').fill('私は先生ではありません')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
  await expect(page.getByText('下次书写时不要忘记写标点符号。')).toBeVisible()
})

test('提交后保持当前题目，点击下一题才切换',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await expect(page.locator('.prompt')).toHaveText('我不是老师。')
  await page.locator('textarea').fill('私は先生ではありません。')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.locator('.prompt')).toHaveText('我不是老师。')
  await expect(page.locator('textarea')).toHaveValue('私は先生ではありません。')
  await page.getByRole('button',{name:/下一题/}).click()
  await expect(page.locator('.prompt')).toContainText('田中先生')
  await expect(page.locator('textarea')).toHaveValue('')
})

test('句尾假名错误会指出具体缺少的字',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await page.locator('textarea').fill('私は先生ではありません。')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/下一题/}).click()
  await page.locator('textarea').fill('田中さんは学生でか。')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText(/句尾疑问形式错误.*でか.*ですか.*缺少.*す/)).toBeVisible()
})

test('助词选择题按选项内容判分',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  for(let i=0;i<3;i++){
    const choices=page.locator('.choice-list button')
    await choices.nth(i===0?0:1).click()
    await page.getByRole('button',{name:/^提交答案/}).click()
    if(i<2) await page.getByRole('button',{name:/下一题/}).click()
  }
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
})

test('答错后进入错题本并可独立练习',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await page.locator('textarea').fill('完全不同的答案')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('△ 句型或词语还需要调整')).toBeVisible()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByText('我不是老师。')).toBeVisible()
  await page.getByRole('button',{name:/开始错题练习/}).click()
  await passFirstChoice(page)
  await page.locator('textarea').fill('私は先生ではありません。')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/完成训练/}).click()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByText('目前没有错题')).toBeVisible()
})

test('未完成整课 20 题不会解锁下一课',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  for(let i=0;i<6;i++){
    await page.locator('textarea').fill(`答案 ${i}`)
    await page.getByRole('button',{name:/^提交答案/}).click()
    await page.getByRole('button',{name:/下一题/}).click()
  }
  await page.getByRole('button',{name:/课程/}).click()
  const lesson2=page.getByRole('button',{name:/02 第 2 课/})
  await expect(lesson2).toBeVisible()
  await expect(lesson2).toContainText('🔒')
})

test('完成部分整课练习后刷新仍保留课程进度',async({page})=>{
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await passFirstChoice(page)
  await page.locator('textarea').fill('答案')
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/下一题/}).click()
  await page.reload()
  await expect(page.getByText('一课一课练习，')).toBeVisible()
  await expect(page.getByText('第 1 课', {exact:false}).first()).toBeVisible()
})

test('未完成课程再次进入时从已答题数继续，不重复第一题',async({page})=>{
  await page.evaluate(()=>localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:3})))
  await page.reload()
  await page.getByRole('button',{name:/开始第 1 课/}).click()
  await expect(page.getByText('第 1 课 · 练习')).toBeVisible()
  await expect(page.getByText('4 / 20')).toBeVisible()
  await expect(page.locator('.prompt')).not.toHaveText('“我是学生。”选择正确项。')
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
  await expect(page.getByText('注册时间')).toBeVisible()
  await expect(page.getByText('登录后同步',{exact:true})).toBeVisible()
  await expect(page.getByText('学习记录已同步到云端。')).not.toBeVisible()
})

test('学习记录 API 拒绝未授权或未配置请求',async({page})=>{
  const state=await page.request.get('/api/study-state')
  const record=await page.request.post('/api/record-answer',{data:{questionId:'L01-Q001',lessonId:1,answer:'私は学生です。',correct:true,mode:'new'}})
  expect([401,503]).toContain(state.status())
  expect([401,503]).toContain(record.status())
})

test('服务端判分接受等价答案且规则正确结果优先',async({page})=>{
  const response=await page.request.post('/api/grade-answer',{data:{answer:'私は先生じゃありません',standardAnswer:'私は先生ではありません。',acceptedAnswers:['私は先生じゃありません。']}})
  expect(response.ok()).toBeTruthy()
  const result=await response.json()
  expect(result.verdict).toBe('correct')
  expect(result.source).toBe('rule')
})

test('第 1 课展示判断、疑问应答和名词所属说明',async({page})=>{
  await page.getByRole('button',{name:/课程/}).click()
  await page.getByRole('button',{name:/01 第 1 课/}).click()
  await expect(page.getByText('N は N ですか。')).toBeVisible()
  await expect(page.getByText(/肯定：はい、そうです。/)).toBeVisible()
  await expect(page.getByText('N1 の N2')).toBeVisible()
  await expect(page.getByText(/所属、机构、国家或属性/)).toBeVisible()
})
