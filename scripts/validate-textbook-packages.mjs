import { readFile } from 'node:fs/promises'
import { registerHooks } from 'node:module'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = process.cwd()
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('@/')) {
      return {
        url: pathToFileURL(resolve(root, `${specifier.slice(2)}.ts`)).href,
        shortCircuit: true,
      }
    }
    return nextResolve(specifier, context)
  },
})

const { validateTextbookPackage } = await import(
  pathToFileURL(resolve(root, 'lib/textbook-import.ts')).href
)

const packageFiles = [
  'shin-standard-japanese-beginner-lower.json',
  'shin-standard-japanese-intermediate-lower.json',
  'shin-standard-japanese-intermediate-upper.json',
]
const expectedPackages = new Map([
  [
    'shin-standard-japanese-beginner-lower.json',
    { textbookId: 'shin-standard-japanese-beginner-lower', lessons: 24, questions: 480 },
  ],
  [
    'shin-standard-japanese-intermediate-lower.json',
    { textbookId: 'shin-standard-japanese-intermediate-lower', lessons: 16, questions: 320 },
  ],
  [
    'shin-standard-japanese-intermediate-upper.json',
    { textbookId: 'shin-standard-japanese-intermediate-upper', lessons: 16, questions: 320 },
  ],
])
const expectedQuestionTypes = { 选择: 4, 助词: 3, 翻译: 9, 问答: 4 }
const failures = []

for (const file of packageFiles) {
  const path = resolve(root, 'docs/textbooks', file)
  const packageData = JSON.parse(await readFile(path, 'utf8'))
  const validation = validateTextbookPackage(packageData)
  if (!validation.success) failures.push(`${file}: schema invalid: ${validation.errors.join(' ')}`)

  const textbook = packageData.textbook
  const expected = expectedPackages.get(file)
  if (textbook.id !== expected.textbookId) {
    failures.push(`${file}: expected textbook id ${expected.textbookId}, got ${textbook.id}`)
  }
  if (textbook.lessons.length !== expected.lessons) {
    failures.push(`${file}: expected ${expected.lessons} lessons, got ${textbook.lessons.length}`)
  }
  if (textbook.questions.length !== expected.questions) {
    failures.push(
      `${file}: expected ${expected.questions} questions, got ${textbook.questions.length}`,
    )
  }

  for (const lesson of textbook.lessons) {
    if (lesson.grammar.length < 5 || lesson.grammar.length > 7) {
      failures.push(
        `${file}: lesson ${lesson.id} has ${lesson.grammar.length} grammar points; expected 5-7`,
      )
    }
    const questionCounts = Object.fromEntries(
      Object.keys(expectedQuestionTypes).map((type) => [type, 0]),
    )
    for (const question of textbook.questions.filter((item) => item.lessonId === lesson.id)) {
      if (Object.hasOwn(questionCounts, question.type)) questionCounts[question.type] += 1
    }
    for (const [type, count] of Object.entries(expectedQuestionTypes)) {
      if (questionCounts[type] !== count) {
        failures.push(
          `${file}: lesson ${lesson.id} has ${questionCounts[type]} ${type} questions; expected ${count}`,
        )
      }
    }
  }

  console.log(
    `${file}: ${validation.success ? 'schema OK' : 'schema failed'}, ${textbook.lessons.length} lessons, ${textbook.questions.length} questions, grammar 5-7 and question quota 4/3/9/4 ${failures.some((failure) => failure.startsWith(`${file}:`)) ? 'FAILED' : 'OK'}`,
  )
}

if (failures.length) {
  console.error(failures.join('\n'))
  process.exitCode = 1
} else {
  console.log(`Validated ${packageFiles.length} free Web textbook packages.`)
}
