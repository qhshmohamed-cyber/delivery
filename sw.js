
const CACHE_PREFIX = 'yourstaff-static-';
const LEGACY_CACHE_PREFIX = 'wahat-delivery-static-';
const CACHE_NAME = CACHE_PREFIX + 'v7';
const STATIC_FILES = [
  './manifest.webmanifest',
  './yourstaff-icon.svg',
  './yourstaff-app-192.png',
  './yourstaff-app-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(STATIC_FILES);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(key => (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) || key.startsWith(LEGACY_CACHE_PREFIX))
        .map(key => caches.delete(key))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // Customer forms must never be cached as the employee application's index.
    const scopePath = new URL('./', self.location.href).pathname;
    if (url.pathname !== scopePath && url.pathname !== scopePath + 'index.html') return;
    event.respondWith((async () => {
      try {
        const fresh = await fetch(request, {cache: 'no-store'});
        if (fresh && fresh.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put('./index.html', fresh.clone());
        }
        return fresh;
      } catch (_) {
        return (await caches.match('./index.html')) ||
          Response.error();
      }
    })());
    return;
  }

  if (STATIC_FILES.some(path =>
    new URL(path, self.location.href).pathname === url.pathname
  )) {
    event.respondWith((async () => {
      const cached = await caches.match(request);
      if (cached) return cached;

      try {
        const fresh = await fetch(request);
        if (fresh && fresh.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, fresh.clone());
        }
        return fresh;
      } catch (_) {
        return Response.error();
      }
    })());
  }
});

