import {defineConfig} from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  testMatch: 'dual-client-lab.spec.ts',
  timeout: 60_000,
  retries: 0,
  outputDir: '../build/dual-client-playwright',
  reporter: 'line',
  use: {baseURL: 'http://127.0.0.1:3219', browserName: 'chromium', headless: true},
})
