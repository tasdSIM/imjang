/* Imjang service worker — offline app shell + cached pet art.
   Bump VERSION whenever index.html or core files change so users get the update. */
const VERSION = 'imjang-v16';
const CORE = `${VERSION}-core`;
// Pet images are cached forever by name. Bump this when pictures are replaced
// under the same names, so installed apps drop the old ones.
const ART = 'imjang-art-v2';
const FONT = 'imjang-font';

const CORE_FILES = [
  './',
  'index.html',
  'manifest.webmanifest',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/apple-touch-icon.png',
  'icons/favicon-32.png',
  'pet/room.webp'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CORE).then(c => c.addAll(CORE_FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keep = new Set([CORE, ART, FONT]);
    for (const k of await caches.keys()) if (!keep.has(k)) await caches.delete(k);
    await self.clients.claim();
  })());
});

async function cacheFirst(req, name) {
  const c = await caches.open(name);
  const hit = await c.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res && (res.ok || res.type === 'opaque')) c.put(req, res.clone());
  return res;
}

async function networkFirst(req) {
  const c = await caches.open(CORE);
  try {
    const res = await fetch(req);
    if (res && res.ok) c.put(req, res.clone());
    return res;
  } catch (err) {
    return (await c.match(req)) || (await c.match('index.html')) || Response.error();
  }
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  if (url.origin === location.origin) {
    // the account server's answers are never cached (server/main.js)
    if (url.pathname.includes('/api/') || url.pathname.endsWith('/health')) return;
    if (req.mode === 'navigate' || url.pathname.endsWith('/index.html')) {
      e.respondWith(networkFirst(req));
    } else if (url.pathname.includes('/pet/')) {
      e.respondWith(cacheFirst(req, ART));
    } else {
      e.respondWith(cacheFirst(req, CORE));
    }
    return;
  }
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    e.respondWith(cacheFirst(req, FONT));
  }
});
