import {defineConfig,devices} from '@playwright/test'

export default defineConfig({
  testDir:'./tests/e2e',
  timeout:30_000,
  expect:{timeout:5_000},
  fullyParallel:true,
  forbidOnly:!!process.env.CI,
  retries:process.env.CI?2:0,
  reporter:process.env.CI?[['github'],['html',{open:'never'}]]:[['list']],
  use:{baseURL:'http://127.0.0.1:3100',trace:'retain-on-failure',...devices['Desktop Chrome']},
  webServer:{command:'npm run dev -- --hostname 127.0.0.1 --port 3100',url:'http://127.0.0.1:3100',reuseExistingServer:!process.env.CI,timeout:120_000}
})
