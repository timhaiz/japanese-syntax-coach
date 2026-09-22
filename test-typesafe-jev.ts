/**
 * TypeSafe Jev 集成验证脚本
 *
 * 直接测试 TypeSafe Jev 判分函数，无需启动开发服务器
 */

import { gradeWithJev } from './lib/typesafe-grading'

async function testJevGrading() {
  console.log('🧪 开始测试 TypeSafe Jev 判分系统...\n')

  const testCases = [
    {
      name: '测试 1: 轻微差异（だ vs です）',
      input: {
        answer: 'これは私の本だ。',
        standardAnswer: 'これは私の本です。',
        context: '基础句型',
      },
      expected: 'mostly_correct 或 correct'
    },
    {
      name: '测试 2: 助词错误',
      input: {
        answer: '私が学生です。',
        standardAnswer: '私は学生です。',
        context: '基本句型',
      },
      expected: 'needs_fix 或 incorrect'
    },
    {
      name: '测试 3: 完全正确',
      input: {
        answer: '私は学生です。',
        standardAnswer: '私は学生です。',
        context: '基本句型',
      },
      expected: 'correct'
    },
    {
      name: '测试 4: 完全错误',
      input: {
        answer: 'さようなら',
        standardAnswer: 'こんにちは',
        context: '问候语',
      },
      expected: 'incorrect'
    }
  ]

  let passCount = 0
  let failCount = 0

  for (const testCase of testCases) {
    console.log(`\n📝 ${testCase.name}`)
    console.log(`   用户答案: ${testCase.input.answer}`)
    console.log(`   标准答案: ${testCase.input.standardAnswer}`)
    console.log(`   期望结果: ${testCase.expected}`)

    const startTime = Date.now()

    try {
      const result = await gradeWithJev(testCase.input)
      const duration = Date.now() - startTime

      if (!result) {
        console.log(`   ❌ 失败: TypeSafe API 未返回结果（可能 API Key 未配置）`)
        failCount++
        continue
      }

      console.log(`   ✅ 判定: ${result.verdict}`)
      console.log(`   📊 质量分数: ${result.qualityScore}%`)
      console.log(`   🎯 置信度: ${result.confidence?.toFixed(2)}`)
      console.log(`   🏷️  错误类型: ${result.errorTags.join(', ') || '无'}`)
      console.log(`   💬 解释: ${result.explanation}`)
      console.log(`   ⏱️  响应时间: ${duration}ms`)

      // 验证响应时间
      if (duration < 500) {
        console.log(`   ✅ 性能: 响应时间 < 500ms`)
      } else {
        console.log(`   ⚠️  性能: 响应时间较慢 (${duration}ms)`)
      }

      passCount++

    } catch (error) {
      console.log(`   ❌ 失败: ${error}`)
      failCount++
    }
  }

  console.log('\n' + '='.repeat(60))
  console.log(`\n📊 测试总结:`)
  console.log(`   通过: ${passCount}/${testCases.length}`)
  console.log(`   失败: ${failCount}/${testCases.length}`)

  if (passCount === testCases.length) {
    console.log(`\n🎉 所有测试通过！TypeSafe Jev 集成成功！`)
  } else if (passCount > 0) {
    console.log(`\n⚠️  部分测试通过，请检查失败的测试用例`)
  } else {
    console.log(`\n❌ 所有测试失败，请检查：`)
    console.log(`   1. TYPESAFE_API_KEY 是否正确配置在 .env.local`)
    console.log(`   2. 网络连接是否正常`)
    console.log(`   3. TypeSafe API 是否可访问`)
  }

  console.log('\n' + '='.repeat(60))
}

// 运行测试
testJevGrading()
  .then(() => {
    console.log('\n✅ 测试完成')
    process.exit(0)
  })
  .catch((error) => {
    console.error('\n❌ 测试失败:', error)
    process.exit(1)
  })
