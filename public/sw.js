// Bump this whenever the app shell changes so installed clients do not retain
// an older JavaScript bundle after a production deployment.
const CACHE_NAME = 'syntax-coach-shell-v3'
const APP_SHELL = ['/', '/manifest.webmanifest']

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)))
  self.skipWaiting()
})

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
  )
  self.clients.claim()
})

self.addEventListener('fetch', event => {
  const request = event.request
  if(request.method !== 'GET' || !request.url.startsWith(self.location.origin)) return
  const url = new URL(request.url)
  // Never cache authenticated or user-specific responses.
  if(url.pathname.startsWith('/api/') || url.pathname.startsWith('/auth/')) return
  // Navigation falls back to the cached shell; static assets use cache-first.
  if(request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match('/')))
    return
  }
  event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
    const copy = response.clone()
    caches.open(CACHE_NAME).then(cache => cache.put(request, copy))
    return response
  })))
})
