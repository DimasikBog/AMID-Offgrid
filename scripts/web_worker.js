/* Generated into amid-sw.js; cache only verified static build files. */
const VERSION = __VERSION__;
const FILES = __FILES__;
const PREFIX = 'amid-offgrid:' + self.registration.scope + ':';
const NAME = PREFIX + VERSION;
const scoped = client => client.url.startsWith(self.registration.scope);
const urlFor = file => new URL(file.path, self.registration.scope).href;
let repair, preparingFile = '';
async function failed(error) {
  await broadcast({type: 'FAILED', file: preparingFile, reason: error.name + ': ' + error.message});
}
async function broadcast(data) {
  const clients = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
  for (const client of clients.filter(scoped)) client.postMessage(data);
}
async function ready() {
  if (!await caches.has(NAME)) return false;
  const cache = await caches.open(NAME);
  const urls = new Set((await cache.keys()).map(request => request.url));
  return FILES.every(file => urls.has(urlFor(file)));
}
async function populate(missingOnly) {
  const cache = await caches.open(NAME);
  let done = 0;
  for (const file of FILES) {
    const url = urlFor(file);
    preparingFile = file.path;
    if (!missingOnly || !await cache.match(url)) {
      const response = await fetch(url, {cache: 'no-store', credentials: 'same-origin', redirect: 'error'});
      if (!response.ok || response.type === 'opaque') throw new Error('Asset unavailable');
      const saved = response.clone();
      const bytes = await response.arrayBuffer();
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)))
        .map(value => value.toString(16).padStart(2, '0')).join('');
      if (bytes.byteLength !== file.bytes || hash !== file.sha256) throw new Error('Asset integrity mismatch');
      await cache.put(url, saved);
    }
    await broadcast({type: 'PROGRESS', done: ++done, total: FILES.length});
  }
  await broadcast({type: 'READY'});
}
self.addEventListener('install', event => {
  event.waitUntil(populate(false).catch(async error => {
    // A failed replacement never destroys the previous version's cache.
    await caches.delete(NAME);
    await failed(error);
    throw error;
  }));
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    if (!await ready()) throw new Error('Incomplete static cache');
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith(PREFIX) && key !== NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('message', event => {
  if (!event.source?.id || !scoped(event.source)) return;
  const reply = value => event.ports?.[0]?.postMessage(value);
  if (event.data?.type === 'STATUS') {
    event.waitUntil(ready().then(value => reply({ready: value, files: FILES.length})));
  } else if (event.data?.type === 'ACTIVATE') {
    event.waitUntil((async () => {
      const others = (await self.clients.matchAll({type: 'window', includeUncontrolled: true}))
        .filter(client => scoped(client) && client.id !== event.source.id);
      if (others.length || !await ready()) { reply({accepted: false}); return; }
      reply({accepted: true});
      await self.skipWaiting();
    })());
  } else if (event.data?.type === 'REPAIR') {
    if (!repair) {
      repair = populate(true).catch(error => failed(error)).finally(() => { repair = null; });
    }
    event.waitUntil(repair);
  }
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(self.registration.scope)) return;
  event.respondWith((async () => {
    const cache = await caches.open(NAME);
    // Keep HTML and runtime from the same installed build, including root/deep links.
    if (request.mode === 'navigate') {
      const page = await cache.match(new URL('index.html', self.registration.scope).href);
      if (page) return page;
    }
    const saved = await cache.match(request, {ignoreSearch: true});
    return saved || fetch(request);
  })());
});
