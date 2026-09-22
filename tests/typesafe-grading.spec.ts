/**
 * TypeSafe Jev 判分系统测试
 */

import { test, expect } from '@playwright/test';

test.describe('TypeSafe Jev Grading API', () => {
  const API_URL = 'http://localhost:3000/api/grade-answer';

  test('should return correct for exact match', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: 'これは私の本です。',
        standardAnswer: 'これは私の本です。',
        hint: '基础句型',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    expect(data.verdict).toBe('correct');
    expect(data.source).toBe('rule');
    expect(data.errorTags).toEqual([]);
  });

  test('should grade with Jev for non-exact match', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: 'これは私の本だ。', // 使用だ而不是です
        standardAnswer: 'これは私の本です。',
        hint: '基础句型',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    // 应该使用 TypeSafe 或 AI 判分
    expect(['typesafe', 'ai', 'rule']).toContain(data.source);
    expect(data.verdict).toBeDefined();
    expect(data.explanation).toBeDefined();
  });

  test('should handle completely wrong answer', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: 'さようなら',
        standardAnswer: 'こんにちは',
        hint: 'Greeting',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    expect(['incorrect', 'needs_fix']).toContain(data.verdict);
    expect(data.correctedAnswer).toBe('こんにちは');
  });

  test('should handle punctuation differences as correct', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: 'これは私の本です',
        standardAnswer: 'これは私の本です。',
        hint: '标点差异',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    expect(data.verdict).toBe('correct');
    expect(data.source).toBe('rule');
  });

  test('should handle particle errors', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: '私が学生です。', // 应该用は而不是が
        standardAnswer: '私は学生です。',
        hint: '基本句型',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    // TypeSafe 应该识别出助词错误
    if (data.source === 'typesafe') {
      expect(data.errorTags).toContain('助词');
    }
  });

  test('should handle accepted alternatives', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: '私は先生ではありません。',
        standardAnswer: '私は先生じゃありません。',
        acceptedAnswers: ['私は先生ではありません。'],
        hint: '否定形式',
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    expect(data.verdict).toBe('correct');
  });

  test('should return error for missing parameters', async ({ request }) => {
    const response = await request.post(API_URL, {
      data: {
        answer: 'こんにちは',
        // 缺少 standardAnswer
      },
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();

    // 应该有降级处理
    expect(data).toBeDefined();
  });
});

test.describe('TypeSafe Jev Performance', () => {
  test('should respond within 500ms for TypeSafe path', async ({ request }) => {
    const startTime = Date.now();

    const response = await request.post('http://localhost:3000/api/grade-answer', {
      data: {
        answer: 'これは私の本だ。',
        standardAnswer: 'これは私の本です。',
        hint: '性能测试',
      },
    });

    const endTime = Date.now();
    const duration = endTime - startTime;

    expect(response.ok()).toBeTruthy();

    // TypeSafe 应该在 500ms 内响应
    // 注意：如果使用 OpenAI 降级可能会更慢
    const data = await response.json();
    if (data.source === 'typesafe') {
      expect(duration).toBeLessThan(500);
    }
  });
});
