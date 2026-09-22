import type { Question } from '@/lib/question-bank'

export type WordToken = { id: string; text: string }

export const tokenPatterns = [
  'なければなりません',
  'なくてもいいです',
  'ないでください',
  'ではありません',
  'ませんでした',
  'かもしれません',
  'と思います',
  'ましょうか',
  'ています',
  'ください',
  'ましょう',
  'でしょう',
  'ですか',
  'ました',
  'ません',
  'です',
]

export const tokenParticles = ['から', 'まで', 'は', 'が', 'を', 'に', 'で', 'と', 'の', 'も', 'へ', 'か']

export const tokenWords = ['かばん', '売り場', '銀行', '郵便局', 'デパート', '会社', '学校', '駅']

export const tokenizeAnswer = (answer: string): string[] => {
  const tokens: string[] = []
  let index = 0
  while (index < answer.length) {
    const rest = answer.slice(index)
    const punctuation = rest.match(/^[。！？!?、，．.]/)
    // 标点保留在标准答案中用于展示和漏写提醒，但不作为可点击词块。
    if (punctuation) {
      index += punctuation[0].length
      continue
    }
    const word = tokenWords.find((value) => rest.startsWith(value))
    if (word) {
      tokens.push(word)
      index += word.length
      continue
    }
    const pattern = tokenPatterns.find((value) => rest.startsWith(value))
    if (pattern) {
      tokens.push(pattern)
      index += pattern.length
      continue
    }
    const particle = tokenParticles.find((value) => rest.startsWith(value))
    if (particle) {
      tokens.push(particle)
      index += particle.length
      continue
    }
    let end = index + 1
    while (
      end < answer.length &&
      !tokenParticles.some((value) => answer.slice(end).startsWith(value)) &&
      !/[。！？!?、，．.]/.test(answer[end]) &&
      !tokenPatterns.some((value) => answer.slice(end).startsWith(value))
    )
      end += 1
    tokens.push(answer.slice(index, end))
    index = end
  }
  return tokens.filter(Boolean)
}

export const tokenOrder = (id: string) => {
  let hash = 2166136261
  for (let index = 0; index < id.length; index++) {
    hash ^= id.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

export const createWordTokens = (question: Question): WordToken[] =>
  tokenizeAnswer(question.answer)
    .map((text, index) => ({ id: `${question.id}-T${String(index + 1).padStart(2, '0')}`, text }))
    .sort((a, b) => tokenOrder(a.id) - tokenOrder(b.id))
