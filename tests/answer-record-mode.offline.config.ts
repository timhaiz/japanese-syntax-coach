import {defineConfig} from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  testMatch: 'answer-record-mode.spec.ts',
  reporter: 'list',
  outputDir: `../build/answer-record-mode-${process.pid}`,
})
