import { mkdir, readFile, writeFile } from 'node:fs/promises'

const modules = [25, 31, 37, 43].map(
  (start) => `scripts/lower-textbook-data/lessons-${start}-${Math.min(start + 5, 48)}.json`,
)
const parts = await Promise.all(modules.map(async (path) => JSON.parse(await readFile(path, 'utf8'))))
const lessons = parts.flatMap((part) => part.lessons)
const questions = parts.flatMap((part) => part.questions)

const output = {
  schemaVersion: 1,
  textbook: {
    id: 'shin-standard-japanese-beginner-lower',
    title: '新版标准日本语 初级下册',
    shortTitle: '新标日 初级下',
    cover: '/textbooks/shin-standard-japanese-beginner-lower.jpg',
    description: '第25～48课句型与原创练习。语法范围参考公开课程目录，题目由本项目重新编写。',
    lessons,
    questions,
  },
}

await mkdir('docs/textbooks', { recursive: true })
await writeFile(
  'docs/textbooks/shin-standard-japanese-beginner-lower.json',
  `${JSON.stringify(output, null, 2)}\n`,
  'utf8',
)
console.log(`generated ${lessons.length} lessons and ${questions.length} original questions`)
