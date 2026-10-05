import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

const engineUrl = (process.env.VOICEVOX_URL || 'http://127.0.0.1:50021').replace(/\/$/, '')
const speaker = Number(process.env.VOICEVOX_SPEAKER || 3)
const textbookPath = process.argv[2] || 'docs/textbooks/shin-standard-japanese-beginner-lower.json'
const textbook = JSON.parse(await readFile(textbookPath, 'utf8')).textbook
const outputRoot = path.resolve('public/audio/grammar', textbook.id)
const manifest = { provider: 'voicevox', speaker, sentences: {} }

const uniqueExamples = [...new Set(textbook.lessons.flatMap((lesson) =>
  lesson.grammar.map((point) => point.example).filter((value) => typeof value === 'string' && value.trim()),
))]

await mkdir(outputRoot, { recursive: true })

try {
  const health = await fetch(`${engineUrl}/version`)
  if (!health.ok) throw new Error(`HTTP ${health.status}`)
} catch (error) {
  const detail = error instanceof Error ? error.message : String(error)
  throw new Error(`无法连接 VOICEVOX Engine（${engineUrl}）。请先启动引擎后再运行此脚本。${detail ? ` ${detail}` : ''}`)
}

for (const sentence of uniqueExamples) {
  const hash = createHash('sha256').update(sentence).digest('hex').slice(0, 16)
  const filename = `${hash}.wav`
  const target = path.join(outputRoot, filename)
  const queryUrl = new URL(`${engineUrl}/audio_query`)
  queryUrl.searchParams.set('text', sentence)
  queryUrl.searchParams.set('speaker', String(speaker))

  const queryResponse = await fetch(queryUrl, { method: 'POST' })
  if (!queryResponse.ok) throw new Error(`VOICEVOX audio_query failed (${queryResponse.status}) for: ${sentence}`)
  const synthesisResponse = await fetch(`${engineUrl}/synthesis?speaker=${speaker}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: await queryResponse.text(),
  })
  if (!synthesisResponse.ok) throw new Error(`VOICEVOX synthesis failed (${synthesisResponse.status}) for: ${sentence}`)
  await writeFile(target, Buffer.from(await synthesisResponse.arrayBuffer()))
  manifest.sentences[sentence.trim()] = `/audio/grammar/${textbook.id}/${filename}`
  console.log(`generated ${sentence} -> ${filename}`)
}

await writeFile(path.join(outputRoot, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
console.log(`generated ${uniqueExamples.length} sentence audio files for ${textbook.title}`)
