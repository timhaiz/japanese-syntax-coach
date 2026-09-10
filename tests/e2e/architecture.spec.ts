import {test, expect} from '@playwright/test'
import {readFileSync, existsSync} from 'node:fs'
import {resolve} from 'node:path'

test('题库与整课架构不会回退到页面硬编码或随机 ID',()=>{
  const pageSource=readFileSync(resolve(process.cwd(),'app/page.tsx'),'utf8')
  expect(pageSource).not.toMatch(/const\s+exercises\s*=\s*\[/)
  expect(pageSource).not.toContain('Math.random()')
  expect(existsSync(resolve(process.cwd(),'lib/question-bank.ts'))).toBeTruthy()
  expect(existsSync(resolve(process.cwd(),'app/api/update-daily/route.ts'))).toBeFalsy()
  expect(pageSource).toMatch(/question\.type\s*===\s*['"]翻译['"]\s*\|\|\s*question\.type\s*===\s*['"]问答['"]\s*\?\s*tokenAnswer/)
  expect(pageSource).toMatch(/answer\s*:\s*submittedAnswer/)
  expect(pageSource).toMatch(/const\s+expectedAnswerText\s*=\s*presentedQuestion\.options/)
  expect(pageSource).toMatch(/const\s+practiceInstruction\s*=\s*presentedQuestion\.type/)
  expect(pageSource).toMatch(/setReplayMode\(existingAnswered\s*>=\s*LESSON_QUESTION_LIMIT\)/)
  expect(pageSource).toContain('if(!replayMode)')
  expect(pageSource).toContain('createWordTokens')
  expect(pageSource).toContain('tokenQuestion')
  expect(pageSource).toContain("tokenParticles=['から','まで'")
})

test('AI 接口包含严格的响应结构校验',()=>{
  const analyzeSource=readFileSync(resolve(process.cwd(),'app/api/analyze-answer/route.ts'),'utf8')
  const aiSource=readFileSync(resolve(process.cwd(),'lib/ai.ts'),'utf8')
  expect(analyzeSource).toContain('isAnalysisResult')
  expect(analyzeSource).toContain('invalid-response-shape')
  expect(aiSource).toContain('isGradeResult')
})
