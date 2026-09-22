import type { Question } from '@/lib/question-bank'

export const explainAnswerDifference = (expected: string, actual: string) => {
  const clean = (value: string) => value.replace(/[。！？!?，,、．.\s]/g, '')
  const expectedClean = clean(expected)
  const actualClean = clean(actual)
  if (expectedClean === actualClean) return '句型和词语正确。'
  if (expected.includes('ですか') && actual.includes('でか'))
    return '句尾疑问形式错误：你写成了「でか」，应为完整的「ですか」（缺少「す」）。'
  if (expected.includes('ではありません') && actual.includes('でわありません'))
    return '否定形式的假名错误：「でわ」应写作「では」。'
  const limit = Math.min(expectedClean.length, actualClean.length)
  let index = 0
  while (index < limit && expectedClean[index] === actualClean[index]) index++
  if (index < limit)
    return `第 ${index + 1} 个字有误：你写的是「${actualClean[index]}」，应为「${expectedClean[index]}」。`
  if (actualClean.length < expectedClean.length)
    return `答案少了内容：第 ${actualClean.length + 1} 个字应为「${expectedClean[actualClean.length]}」，请检查是否漏写。`
  if (actualClean.length > expectedClean.length)
    return `答案多了内容：请检查第 ${expectedClean.length + 1} 个字「${actualClean[expectedClean.length]}」附近。`
  return '请逐字对照参考答案，检查助词、活用和句尾形式。'
}

export const errorTagsForAnswer = (question: Question, actual: string) => {
  if (question.type === '助词') return ['助词']
  const expected = question.answer
  if (expected.includes('ですか') && actual.includes('でか')) return ['假名']
  if (expected.includes('ではありません') && actual.includes('でわありません')) return ['假名']
  if (expected.includes('なければ') || expected.includes('なくても') || expected.includes('ないで'))
    return ['活用']
  if (expected.includes('ています') || expected.includes('ました') || expected.includes('ません'))
    return ['活用']
  if (actual.length !== expected.length) return ['词汇']
  return ['句型顺序']
}

export const knowledgeTagsForQuestion = (question: Question) => {
  const tags = new Set<string>()
  if (question.type === '助词' || /助词/.test(question.hint)) tags.add('助词')
  if (/活用|否定|过去|变化|ます形|て形/.test(question.hint)) tags.add('活用')
  if (/假名|拼写|词汇/.test(question.hint)) tags.add('词汇')
  if (!tags.size) tags.add('句型')
  return [...tags]
}
