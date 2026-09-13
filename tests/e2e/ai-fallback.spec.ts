import {test, expect} from '@playwright/test'
import {POST} from '../../app/api/analyze-answer/route'

const request = () =>
  new Request('http://localhost/api/analyze-answer', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({
      prompt: 'これは何ですか。',
      answer: 'これは本です',
      standardAnswer: 'これは本ですか。',
      hint: 'ですか = 吗',
    }),
  })

test.describe.configure({mode: 'serial'})

test.describe('AI 分析接口降级', () => {
  const originalFetch = globalThis.fetch
  const originalKey = process.env.OPENAI_API_KEY
  const originalBaseUrl = process.env.OPENAI_BASE_URL

  test.afterEach(() => {
    globalThis.fetch = originalFetch
    if (originalKey === undefined) delete process.env.OPENAI_API_KEY
    else process.env.OPENAI_API_KEY = originalKey
    if (originalBaseUrl === undefined) delete process.env.OPENAI_BASE_URL
    else process.env.OPENAI_BASE_URL = originalBaseUrl
  })

  test('缺少 API Key 时返回可读降级结果', async () => {
    delete process.env.OPENAI_API_KEY
    const response = await POST(request())
    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toMatchObject({
      source: 'fallback',
      reason: 'missing-api-key',
    })
  })

  for (const [status, reason] of [
    [401, 'upstream-401'],
    [429, 'upstream-429'],
  ] as const) {
    test(`${status} 上游错误返回专门提示`, async () => {
      process.env.OPENAI_API_KEY = 'test-key'
      process.env.OPENAI_BASE_URL = 'https://mock.test/v1'
      globalThis.fetch = async () => new Response('', {status})
      const result = await (await POST(request())).json()
      expect(result).toMatchObject({source: 'fallback', reason})
      expect(result.analysis).toContain(status === 429 ? '额度不足' : '鉴权失败')
    })
  }

  test('非法 JSON 和非法结构不会冒泡为 500', async () => {
    process.env.OPENAI_API_KEY = 'test-key'
    process.env.OPENAI_BASE_URL = 'https://mock.test/v1'
    globalThis.fetch = async () =>
      new Response(JSON.stringify({output_text: '{not-json'}), {status: 200})
    const invalidJson = await (await POST(request())).json()
    expect(invalidJson).toMatchObject({source: 'fallback', reason: 'invalid-json'})

    globalThis.fetch = async () =>
      new Response(JSON.stringify({output_text: JSON.stringify({analysis: '不完整'})}), {
        status: 200,
      })
    const invalidShape = await (await POST(request())).json()
    expect(invalidShape).toMatchObject({source: 'fallback', reason: 'invalid-response-shape'})
  })

  test('超时返回降级提示', async () => {
    process.env.OPENAI_API_KEY = 'test-key'
    process.env.OPENAI_BASE_URL = 'https://mock.test/v1'
    globalThis.fetch = async () => {
      throw new DOMException('timed out', 'TimeoutError')
    }
    const result = await (await POST(request())).json()
    expect(result).toMatchObject({source: 'fallback', reason: 'timeout'})
  })
})
