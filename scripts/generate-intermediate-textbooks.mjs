import { mkdir, readFile, writeFile } from 'node:fs/promises'

const upperModules = ['01-04', '05-08', '09-12', '13-16'].map(
  (range) => `scripts/intermediate-upper-data/lessons-${range}.json`,
)
const lowerModules = ['17-20', '21-24', '25-28', '29-32'].map(
  (range) => `scripts/intermediate-lower-data/lessons-${range}.json`,
)

const loadParts = async (paths) =>
  Promise.all(paths.map(async (path) => JSON.parse(await readFile(path, 'utf8'))))

const upperParts = await loadParts(upperModules)
const upperOutput = {
  schemaVersion: 1,
  textbook: {
    id: 'shin-standard-japanese-intermediate-upper',
    title: '新版标准日本语 中级上册',
    shortTitle: '新标日 中级上',
    cover: '/textbooks/shin-standard-japanese-intermediate-upper.jpg',
    description: '第1～16课（会话与课文）核心句型与20题四题型主动输出练习。',
    lessons: upperParts.flatMap((part) => part.lessons),
    questions: upperParts.flatMap((part) => part.questions),
  },
}

const lowerParts = await loadParts(lowerModules)
const lowerOutput = {
  schemaVersion: 1,
  textbook: {
    id: 'shin-standard-japanese-intermediate-lower',
    title: '新版标准日本语 中级下册',
    shortTitle: '新标日 中级下',
    cover: '/textbooks/shin-standard-japanese-intermediate-lower.jpg',
    description: '第17～32课（会话与课文）核心句型与20题四题型主动输出练习。',
    lessons: lowerParts.flatMap((part) => part.lessons),
    questions: lowerParts.flatMap((part) => part.questions),
  },
}

await mkdir('docs/textbooks', { recursive: true })
await writeFile(
  'docs/textbooks/shin-standard-japanese-intermediate-upper.json',
  `${JSON.stringify(upperOutput, null, 2)}\n`,
  'utf8',
)
await writeFile(
  'docs/textbooks/shin-standard-japanese-intermediate-lower.json',
  `${JSON.stringify(lowerOutput, null, 2)}\n`,
  'utf8',
)

console.log(
  `generated Intermediate Upper (${upperOutput.textbook.lessons.length} lessons, ${upperOutput.textbook.questions.length} questions) and Intermediate Lower (${lowerOutput.textbook.lessons.length} lessons, ${lowerOutput.textbook.questions.length} questions)`,
)
