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
async function pickTokens(page:any,tokens:string[]){
  for(const token of tokens) await page.locator('.token-bank .token-button').filter({hasText:new RegExp(`^${token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}$`)}).first().click()
}
async function startLesson(page:any){
  await page.getByRole('button',{name:/学习第 1 课句型/}).click()
  for(let i=0;i<3;i++) await page.getByRole('button',{name:'下一个 →'}).click()
  await page.getByRole('button',{name:/开始整课练习|重新答题/}).click()
}

test.beforeEach(async({page})=>{
  await page.goto('/')
  await page.evaluate(()=>localStorage.clear())
  await page.reload()
})

test('首页入口会进入当前课程整课练习',async({page})=>{
  await expect(page.getByText('一课一练，',{exact:false})).toBeVisible()
  await expect(page.getByText('每课 20 道主动输出题：先看句型骨架，再练到能快速组织日语。')).toBeVisible()
  await startLesson(page)
  await passFirstChoice(page)
  await expect(page.getByText('第 1 课 · 练习')).toBeVisible()
  await expect(page.getByText('4 / 20')).toBeVisible()
})

test('首页当前课程卡片支持键盘打开',async({page})=>{
  const card=page.getByRole('button',{name:/打开第 1 课/})
  await expect(card).toBeVisible()
  await card.focus()
  await card.press('Enter')
  await expect(page.getByText('第 1 课 · 核心句型')).toBeVisible()
})

test('课程列表中的锁定课程不可操作',async({page})=>{
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await expect(page.getByRole('button',{name:/02 第 2 课已锁定/})).toBeDisabled()
})

test('候选词答案省略句末标点仍判定正确',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await pickTokens(page,['私','は','先生','ではありません'])
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
})

test('提交后保持当前题目，点击下一题才切换',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await expect(page.locator('.prompt')).toHaveText('我不是老师。')
  await pickTokens(page,['私','は','先生','ではありません'])
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.locator('.prompt')).toHaveText('我不是老师。')
  await expect(page.locator('.token-answer')).toHaveText('私は先生ではありません')
  await page.getByRole('button',{name:/下一题/}).click()
  await expect(page.locator('.prompt')).toContainText('田中先生')
  await expect(page.locator('.token-answer')).toContainText('点击下方词块组成答案')
})

test('候选词块可组成问句并提交判分',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await pickTokens(page,['私','は','先生','ではありません'])
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/下一题/}).click()
  await pickTokens(page,['田中さん','は','学生','ですか'])
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
})

test('候选词块不显示句末标点，触控后不会把相邻词显示为已选',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await expect(page.locator('.token-bank .token-button',{hasText:'。'})).toHaveCount(0)
  await page.locator('.token-bank .token-button',{hasText:'私'}).click()
  await expect(page.locator('.token-answer .token-selected')).toHaveText('私')
  await expect(page.locator('.token-bank .token-selected')).toHaveCount(0)
})

test('选择候选词后提交答案按钮保持原位',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  const submit=page.getByRole('button',{name:/^提交答案/})
  const before=await submit.boundingBox()
  await page.locator('.token-bank').getByRole('button',{name:'私',exact:true}).click()
  await page.locator('.token-bank').getByRole('button',{name:'は',exact:true}).click()
  const after=await submit.boundingBox()
  expect(before?.y).toBeDefined()
  expect(after?.y).toBe(before?.y)
  await expect(page.locator('.token-bank .token-slot')).toHaveCount(2)
})

test('助词选择题按选项内容判分',async({page})=>{
  await startLesson(page)
  for(let i=0;i<3;i++){
    const choices=page.locator('.choice-list button')
    await choices.nth(i===0?0:1).click()
    await page.getByRole('button',{name:/^提交答案/}).click()
    if(i<2) await page.getByRole('button',{name:/下一题/}).click()
  }
  await expect(page.getByText('✓ 很好，句型正确')).toBeVisible()
})

test('答错后进入错题本并可独立练习',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await page.locator('.token-bank .token-button').first().click()
  await page.getByRole('button',{name:/^提交答案/}).click()
  await expect(page.getByText('△ 句型或词语还需要调整')).toBeVisible()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByText('我不是老师。')).toBeVisible()
  await page.getByRole('button',{name:/开始错题练习/}).click()
  await passFirstChoice(page)
  await pickTokens(page,['私','は','先生','ではありません'])
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/完成训练/}).click()
  await page.getByRole('button',{name:/错题本/}).click()
  await expect(page.getByRole('heading',{name:'错题本'})).toBeVisible()
})

test('未完成整课 20 题不会解锁下一课',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  for(let i=0;i<6;i++){
    await page.locator('.token-bank .token-button').first().click()
    await page.getByRole('button',{name:/^提交答案/}).click()
    await page.getByRole('button',{name:/下一题/}).click()
  }
  await page.getByRole('button',{name:'▤ 课程'}).click()
  const lesson2=page.getByRole('button',{name:/02 第 2 课/})
  await expect(lesson2).toBeVisible()
  await expect(lesson2).toContainText('🔒')
})

test('完成部分整课练习后刷新仍保留课程进度',async({page})=>{
  await startLesson(page)
  await passFirstChoice(page)
  await page.locator('.token-bank .token-button').first().click()
  await page.getByRole('button',{name:/^提交答案/}).click()
  await page.getByRole('button',{name:/下一题/}).click()
  await page.reload()
  await expect(page.getByText('一课一练，',{exact:false})).toBeVisible()
  await expect(page.getByText('第 1 课', {exact:false}).first()).toBeVisible()
})

test('未完成课程再次进入时从已答题数继续，不重复第一题',async({page})=>{
  await page.evaluate(()=>localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:3})))
  await page.reload()
  await startLesson(page)
  await expect(page.getByText('第 1 课 · 练习')).toBeVisible()
  await expect(page.getByText('4 / 20')).toBeVisible()
  await expect(page.locator('.prompt')).not.toHaveText('“我是学生。”选择正确项。')
})

test('未来课程的陈旧完成标记不会把当前课程跳到第24课',async({page})=>{
  await page.evaluate(()=>localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify(Array.from({length:24},(_,index)=>index))))
  await page.reload()
  await expect(page.getByRole('button',{name:/学习第 1 课句型/})).toBeVisible()
  await expect(page.getByText('第 24 课 · 练习')).not.toBeVisible()
})

test('没有实际进度的云端完成标记不会解锁课程',async({page})=>{
  await page.evaluate(()=>{
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:0}))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify([0,23]))
  })
  await page.reload()
  await expect(page.getByRole('button',{name:/学习第 1 课句型/})).toBeVisible()
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await expect(page.getByRole('button',{name:/02 第 2 课/})).toContainText('🔒')
})

test('完成全部题目后不要求正确率即可解锁下一课',async({page})=>{
  await page.evaluate(()=>{
    const progress=Object.fromEntries(Array.from({length:24},(_,index)=>[index,index === 0 ? 20 : 0]))
    const correct=Object.fromEntries(Array.from({length:24},(_,index)=>[index,index === 0 ? 0 : 0]))
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify(progress))
    localStorage.setItem('syntax-coach-lesson-correct',JSON.stringify(correct))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify([]))
  })
  await page.reload()
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await expect(page.getByRole('button',{name:/02 第 2 课/})).toBeEnabled()
})

test('课程页不显示旧的答题统计和正确率解锁提示',async({page})=>{
  await page.addInitScript(()=>{
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:21}))
    localStorage.setItem('syntax-coach-lesson-correct',JSON.stringify({0:18}))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify([0]))
    localStorage.setItem('syntax-coach-mistakes',JSON.stringify([{id:'L01-Q001',lessonId:1,type:'翻译',prompt:'历史错题',answer:'私は先生です。',hint:'提示'}]))
  })
  await page.reload()
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await page.getByRole('button',{name:/01 第 1 课/}).click()
  await expect(page.getByText(/已作答 .*正确 .*题/)).not.toBeVisible()
  await expect(page.getByText(/正确率达到 90%|本课已达标/)).not.toBeVisible()
})

test('全部课程完成后首页仍允许重新答题',async({page})=>{
  await page.addInitScript(()=>{
    const progress=Object.fromEntries(Array.from({length:24},(_,index)=>[index,20]))
    const correct=Object.fromEntries(Array.from({length:24},(_,index)=>[index,20]))
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify(progress))
    localStorage.setItem('syntax-coach-lesson-correct',JSON.stringify(correct))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify(Array.from({length:24},(_,index)=>index)))
    localStorage.setItem('syntax-coach-mistakes','[]')
  })
  await page.reload()
  const start=page.getByRole('button',{name:/重新答题第 \d+ 课/})
  await expect(start).toBeVisible()
  await expect(start).toBeEnabled()
})

test('已完成课程可以从第一题重新答完整课',async({page})=>{
  await page.evaluate(()=>{
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:20}))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify([0]))
    localStorage.setItem('syntax-coach-mistakes','[]')
  })
  await page.reload()
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await page.getByRole('button',{name:/01 第 1 课/}).click()
  for(let i=0;i<3;i++) await page.getByRole('button',{name:'下一个 →'}).click()
  const practiceButton = page.getByRole('button',{name:/重新答题（20题）/})
  await expect(practiceButton).toBeEnabled()
  await practiceButton.click()
  await expect(page.getByText('1 / 20')).toBeVisible()
})

test('已完成课程重复答题加载完整课程而不是只加载错题',async({page})=>{
  await page.addInitScript(()=>{
    localStorage.setItem('syntax-coach-lesson-progress',JSON.stringify({0:20}))
    localStorage.setItem('syntax-coach-completed-lessons',JSON.stringify([0]))
    localStorage.setItem('syntax-coach-mistakes',JSON.stringify([{id:'L01-Q001',lessonId:1,type:'选择',prompt:'历史题目',answer:'A',hint:'提示',options:['A：正确','B：错误']}]))
  })
  await page.reload()
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await page.getByRole('button',{name:/01 第 1 课/}).click()
  for(let i=0;i<3;i++) await page.getByRole('button',{name:'下一个 →'}).click()
  await page.getByRole('button',{name:/重新答题（20题）/}).click()
  await expect(page.getByText('1 / 20')).toBeVisible()
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
  await page.getByRole('button',{name:'▤ 课程'}).click()
  await page.getByRole('button',{name:/01 第 1 课/}).click()
  await expect(page.getByText('N は N ですか。')).toBeVisible()
  await expect(page.getByText(/肯定：はい、そうです。/)).toBeVisible()
  await expect(page.getByText('N1 の N2')).toBeVisible()
  await expect(page.getByText(/所属、机构、国家或属性/)).toBeVisible()
})
