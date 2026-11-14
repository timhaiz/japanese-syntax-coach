import {test, expect} from '@playwright/test'
import {createElement} from 'react'
import {renderToString} from 'react-dom/server'
import {answerRecordMode, useAnswerSubmission} from '../../lib/hooks/useAnswerSubmission'
import {questionBank} from '../../lib/question-bank'

test('answer records preserve mistake practice so a correct answer can clear the mistake', () => {
  expect(answerRecordMode('mistakes', false)).toBe('mistakes')
})

test('lesson replay and ordinary lesson or mixed practice keep distinct recording modes', () => {
  expect(answerRecordMode('lesson', true)).toBe('lesson_replay')
  expect(answerRecordMode('lesson', false)).toBe('lesson')
  expect(answerRecordMode('mixed', false)).toBe('review')
})

test('submitting a correct mistake sends the mistake mode and removes it locally', async () => {
  let hook!: ReturnType<typeof useAnswerSubmission>
  function Harness() {
    hook = useAnswerSubmission()
    return null
  }
  renderToString(createElement(Harness))
  const question = questionBank[1][0]
  const originalFetch = globalThis.fetch
  let requestBody: Record<string, unknown> | undefined
  globalThis.fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body))
    return new Response('{}', {status: 200})
  }
  try {
    const result = await hook.submitAnswer({
      question, answer: question.answer, practiceMode: 'mistakes', replayMode: false,
      currentLesson: 0, userId: 'fixture-user', textbookId: 'builtin-japanese-syntax',
      membershipStatus: 'free',
    }, {lessonDone: {}, lessonCorrect: {}, completedLessons: [], mistakes: [question]})
    expect(result.gradeResult.correct).toBe(true)
    expect(result.persistence).toBe('saved')
    expect(result.progressUpdates.mistakes).toEqual([])
    expect(requestBody?.mode).toBe('mistakes')
    expect(requestBody?.questionId).toBe(question.id)
    expect(requestBody?.correct).toBe(true)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('atomic submit reports persistence failure when the local queue cannot be created', async () => {
  let hook!: ReturnType<typeof useAnswerSubmission>
  function Harness() {
    hook = useAnswerSubmission('fixture-user', 'builtin-japanese-syntax')
    return null
  }
  renderToString(createElement(Harness))
  const question = questionBank[1][0]
  const originalFetch = globalThis.fetch
  let requests = 0
  globalThis.fetch = async () => { requests += 1; return new Response('{}', {status: 200}) }
  const notices: string[] = []
  try {
    const result = await hook.submitAnswer({
      question, answer: question.answer, practiceMode: 'lesson', replayMode: false,
      currentLesson: 0, userId: 'fixture-user', textbookId: 'builtin-japanese-syntax',
      atomicMistakeStateAvailable: true,
      onMistakeQueueChange: (notice) => notices.push(notice),
    }, {lessonDone: {}, lessonCorrect: {}, completedLessons: [], mistakes: []})
    expect(result.persistence).toBe('failed')
    expect(requests).toBe(0)
    expect(notices.join(' ')).toContain('当前输入')
  } finally {
    globalThis.fetch = originalFetch
  }
})
