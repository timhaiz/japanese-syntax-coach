import {test, expect} from '@playwright/test'
import {readFileSync, existsSync} from 'node:fs'
import {resolve} from 'node:path'

test('题库与整课架构不会回退到页面硬编码或随机 ID',()=>{
  const pageSource=readFileSync(resolve(process.cwd(),'app/page.tsx'),'utf8')
  expect(pageSource).not.toMatch(/const\s+exercises\s*=\s*\[/)
  expect(pageSource).not.toContain('Math.random()')
  expect(existsSync(resolve(process.cwd(),'lib/question-bank.ts'))).toBeTruthy()
  expect(existsSync(resolve(process.cwd(),'app/api/update-daily/route.ts'))).toBeFalsy()
  expect(pageSource).toContain('const submittedAnswer=selectedChoiceText||input')
  expect(pageSource).toContain('answer:submittedAnswer')
})
