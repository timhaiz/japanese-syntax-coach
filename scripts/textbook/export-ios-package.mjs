import { createHash } from 'node:crypto'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { registerHooks } from 'node:module'
import { pathToFileURL } from 'node:url'

const defaultOutput = 'ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json'
const outputFlag = process.argv.indexOf('--output')
const output = outputFlag >= 0 && process.argv[outputFlag + 1] ? process.argv[outputFlag + 1] : defaultOutput
const root = resolve(process.cwd())
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('@/')) {
      return { url: pathToFileURL(resolve(root, `${specifier.slice(2)}.ts`)).href, shortCircuit: true }
    }
    return nextResolve(specifier, context)
  },
})

const sortKeys = (value) => {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortKeys(value[key])]))
  }
  return value
}

const canonicalJson = (value) => JSON.stringify(sortKeys(value))

const { builtInTextbookPackage } = await import(pathToFileURL(resolve(root, 'lib/textbooks.ts')).href)
const textbook = builtInTextbookPackage.textbook
const contentHash = createHash('sha256').update(canonicalJson(textbook)).digest('hex')
const packageJson = { schemaVersion: 1, contentHash, textbook }
const destination = resolve(root, output)
await mkdir(dirname(destination), { recursive: true })
await writeFile(destination, `${JSON.stringify(sortKeys(packageJson), null, 2)}\n`, 'utf8')
