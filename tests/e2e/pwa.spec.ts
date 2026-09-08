import {test, expect} from '@playwright/test'

test('PWA manifest、图标和 Service Worker 资源可用', async ({request})=>{
  const manifestResponse=await request.get('/manifest.webmanifest')
  expect(manifestResponse.ok()).toBeTruthy()
  const manifest=await manifestResponse.json()
  expect(manifest.name).toBe('句型教练')
  expect(manifest.display).toBe('standalone')
  expect(manifest.icons).toEqual(expect.arrayContaining([
    expect.objectContaining({src:'/icon.svg',type:'image/svg+xml'})
  ]))

  const iconResponse=await request.get('/icon.svg')
  expect(iconResponse.ok()).toBeTruthy()
  expect(await iconResponse.text()).toContain('<svg')

  const workerResponse=await request.get('/sw.js')
  expect(workerResponse.ok()).toBeTruthy()
  const worker=await workerResponse.text()
  expect(worker).toContain("self.addEventListener('install'")
  expect(worker).toContain("self.addEventListener('fetch'")
})

test('手机窄屏首页不产生横向滚动', async ({page})=>{
  await page.setViewportSize({width:390,height:844})
  await page.goto('/')
  const widths=await page.evaluate(()=>({body:document.body.scrollWidth,viewport:window.innerWidth}))
  expect(widths.body).toBeLessThanOrEqual(widths.viewport)
})
