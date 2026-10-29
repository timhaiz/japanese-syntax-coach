import {test, expect} from '@playwright/test'
import {execFileSync} from 'node:child_process'
import {mkdtempSync, readFileSync, existsSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {resolve} from 'node:path'
import {createHash} from 'node:crypto'

test('versioned textbook iOS export has a stable package contract',()=>{
  const root=process.cwd()
  const exporter=resolve(root,'scripts/textbook/export-ios-package.mjs')
  expect(existsSync(exporter)).toBeTruthy()
  const outputDir=mkdtempSync(resolve(tmpdir(),'ios-textbook-'))
  const output=resolve(outputDir,'package.json')
  try {
    execFileSync(process.execPath,[exporter,'--output',output],{cwd:root,stdio:'pipe'})
    const packageJson=JSON.parse(readFileSync(output,'utf8'))
    const authoritative=JSON.parse(execFileSync(process.execPath,['--input-type=module','-e',`
      import { registerHooks } from 'node:module'
      import { pathToFileURL } from 'node:url'
      registerHooks({ resolve(specifier, context, nextResolve) {
        if (specifier.startsWith('@/')) return { url: pathToFileURL(${JSON.stringify(root)} + '/' + specifier.slice(2) + '.ts').href, shortCircuit: true }
        return nextResolve(specifier, context)
      }})
      const { builtInTextbookPackage } = await import(pathToFileURL(${JSON.stringify(resolve(root,'lib/textbooks.ts'))}).href)
      process.stdout.write(JSON.stringify(builtInTextbookPackage.textbook))
    `],{cwd:root,stdio:['ignore','pipe','pipe']}).toString())
    const sortKeys=(value:unknown):unknown=>Array.isArray(value)?value.map(sortKeys):value&&typeof value==='object'?Object.fromEntries(Object.entries(value as Record<string,unknown>).sort(([a],[b])=>a.localeCompare(b)).map(([key,item])=>[key,sortKeys(item)])):value
    const canonical=JSON.stringify(sortKeys(authoritative))
    const expectedHash=createHash('sha256').update(canonical,'utf8').digest('hex')
    expect(packageJson).toEqual({schemaVersion:1,contentHash:expectedHash,textbook:authoritative})
    expect(packageJson.textbook.lessons.map((lesson:{id:number})=>lesson.id)).toEqual(authoritative.lessons.map((lesson:{id:number})=>lesson.id))
    expect(packageJson.textbook.questions.map((question:{id:string})=>question.id)).toEqual(authoritative.questions.map((question:{id:string})=>question.id))
  } finally {
    rmSync(outputDir,{recursive:true,force:true})
  }
})

test('题库与整课架构不会回退到页面硬编码或随机 ID',()=>{
  const pageSource=readFileSync(resolve(process.cwd(),'app/page.tsx'),'utf8')
  expect(pageSource).not.toMatch(/const\s+exercises\s*=\s*\[/)
  expect(pageSource).not.toContain('Math.random()')
  expect(existsSync(resolve(process.cwd(),'lib/question-bank.ts'))).toBeTruthy()
  expect(existsSync(resolve(process.cwd(),'app/api/update-daily/route.ts'))).toBeFalsy()
  expect(pageSource).toMatch(/question\.type\s*===\s*['"]翻译['"]\s*\|\|\s*question\.type\s*===\s*['"]问答['"]\s*\?\s*tokenAnswer/)
  expect(pageSource).toMatch(/answer\s*:\s*submittedAnswer/)
  expect(pageSource).toContain('const expectedAnswerText = useMemo')
  expect(pageSource).toContain('presentedQuestion.options')
  expect(pageSource).toContain('const practiceInstruction = useMemo')
  expect(pageSource).toContain('presentedQuestion.type')
  expect(pageSource).toContain('setReplayMode(false)')
  expect(pageSource).toContain('practiceState.isReplay')
  expect(pageSource).toContain('useTextbookCatalog')
  expect(pageSource).toContain('lessonQuestionsList')
  expect(pageSource).toContain('createWordTokens')
  expect(pageSource).toContain('tokenQuestion')
  const submissionSource=readFileSync(resolve(process.cwd(),'lib/hooks/useAnswerSubmission.ts'),'utf8')
  expect(submissionSource).toContain("'lesson_replay'")
  expect(pageSource).toContain('practiceState.mode === \'mixed\'')
  expect(pageSource).toContain("setDueQuestionIds((value) => value.filter((id) => id !== question.id))")
  expect(pageSource).toContain("initializePractice({ mode: 'lesson', isFullLesson: true })")
  expect(pageSource).not.toContain('书写时不要忘记写标点符号，标点不影响判分。')
  const recordSource=readFileSync(resolve(process.cwd(),'app/api/record-answer/route.ts'),'utf8')
  const migrationSource=readFileSync(resolve(process.cwd(),'supabase/migrations/202609120003_lesson_replay_accuracy.sql'),'utf8')
  expect(recordSource).toContain("'lesson_replay'")
  expect(recordSource).toContain('p_knowledge_tags')
  expect(recordSource).toContain('p_verdict')
  expect(recordSource).toContain('clientRequestId')
  expect(recordSource).toContain('duplicate')
  expect(recordSource).toContain('record_textbook_learning_attempt_idempotent')
  expect(recordSource).toContain('p_user_id: user.id')
  expect(recordSource).toContain('legacy')
  const studySource=readFileSync(resolve(process.cwd(),'app/api/study-state/route.ts'),'utf8')
  expect(studySource).toContain("select('exercise_id,verdict,error_tags,created_at')")
  expect(studySource).toContain('forgotten++')
  const masteryMigration=readFileSync(resolve(process.cwd(),'supabase/migrations/202609130005_knowledge_mastery_tags.sql'),'utf8')
  expect(masteryMigration).toContain('p_knowledge_tags')
  expect(migrationSource).toContain("elsif p_mode = 'lesson_replay'")
})

test('idempotency: record-answer uses a user-scoped durable request key',()=>{
  const recordSource=readFileSync(resolve(process.cwd(),'app/api/record-answer/route.ts'),'utf8')
  const migrationSource=readFileSync(resolve(process.cwd(),'supabase/migrations/202610291400_native_answer_idempotency.sql'),'utf8')
  expect(recordSource).toContain('clientRequestId')
  expect(recordSource).toContain('duplicate')
  expect(recordSource).toContain('record_textbook_learning_attempt_idempotent')
  expect(migrationSource).toMatch(/primary key\s*\(user_id, client_request_id\)|unique\s*\(user_id, client_request_id\)/i)
})

test('服务端 API 支持 Bearer/Cookie 双认证且路由不信任客户端 user ID',()=>{
  const source=readFileSync(resolve(process.cwd(),'lib/supabase-server.ts'),'utf8')
  expect(source).toContain('Authorization')
  expect(source).toContain('Bearer')
  const helper=readFileSync(resolve(process.cwd(),'lib/auth/request-supabase.ts'),'utf8')
  expect(helper).toContain('getAuthenticatedSupabase')
  expect(helper).toContain('getSupabaseServer(request)')
  expect(helper).toMatch(/supabase\.auth\.getUser\(\s*token\s*\)/)
  expect(helper).toMatch(/supabase\.auth\.getUser\(\s*\)/)
  for(const route of ['study-state','record-answer','membership','review']){
    const routeSource=readFileSync(resolve(process.cwd(),`app/api/${route}/route.ts`),'utf8')
    expect(routeSource).not.toMatch(/body\.userId|searchParams\.get\(['"]userId/)
  }
  for(const route of ['study-state','record-answer','apple/entitlements','account/delete','tts/generate','tts/audio','tts/manifest','review']){
    const routeSource=readFileSync(resolve(process.cwd(),`app/api/${route}/route.ts`),'utf8')
    expect(routeSource).toContain('getAuthenticatedSupabase')
  }
  const reviewSource=readFileSync(resolve(process.cwd(),'app/api/review/route.ts'),'utf8')
  expect(reviewSource).toContain("'userId' in body")
  expect(reviewSource).toContain('userId: user.id')
})

test('AI 接口包含严格的响应结构校验',()=>{
  const analyzeSource=readFileSync(resolve(process.cwd(),'app/api/analyze-answer/route.ts'),'utf8')
  const aiSource=readFileSync(resolve(process.cwd(),'lib/ai.ts'),'utf8')
  expect(analyzeSource).toContain('isAnalysisResult')
  expect(analyzeSource).toContain('invalid-json')
  expect(analyzeSource).toContain('invalid-response-shape')
  expect(aiSource).toContain('isGradeResult')
})
