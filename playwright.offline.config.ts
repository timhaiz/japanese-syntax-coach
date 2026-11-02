import {defineConfig} from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  testMatch: [
    'apple-entitlements-errors.spec.ts',
    'auth-contract.spec.ts',
    'architecture.spec.ts',
  ],
  fullyParallel: false,
  workers: 1,
  reporter: 'list',
})
