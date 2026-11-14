import {defineConfig} from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  testMatch: 'apple-entitlements-errors.spec.ts',
  reporter: 'list',
  outputDir: `../.build/apple-entitlements-offline-${process.pid}`,
})
