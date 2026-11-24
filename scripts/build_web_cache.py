#!/usr/bin/env python3
"""Create an offline cache from the final local web build, including its renderer."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import quote


def generate(root):
    root = Path(root)
    if not (root / 'index.html').is_file() or not (root / 'flutter_bootstrap.js').is_file():
        raise ValueError('Expected a complete Flutter web build')
    files = sorted(p for p in root.rglob('*') if p.is_file()
                   and p.name not in {'amid-sw.js', 'flutter_service_worker.js'}
                   and p.suffix != '.map')
    digest = hashlib.sha256()
    paths = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode())
        with path.open('rb') as source:
            digest.update(hashlib.file_digest(source, 'sha256').digest())
        paths.append(quote(relative, safe='/'))
    worker = '''const VERSION = __VERSION__;
const FILES = __FILES__;
const PREFIX = 'amid-offgrid:' + self.registration.scope + ':';
const NAME = PREFIX + VERSION;
self.addEventListener('install', event => {
  event.waitUntil(caches.open(NAME).then(cache =>
    cache.addAll(FILES.map(path => new URL(path, self.registration.scope).href))));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key.startsWith(PREFIX) && key !== NAME).map(key => caches.delete(key)))));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(self.registration.scope)) return;
  event.respondWith(caches.open(NAME).then(async cache => {
    const saved = await cache.match(request, {ignoreSearch: true});
    if (saved) return saved;
    try { return await fetch(request); }
    catch (error) {
      if (request.mode === 'navigate') {
        const page = await cache.match(new URL('index.html', self.registration.scope).href);
        if (page) return page;
      }
      throw error;
    }
  }));
});
'''
    worker = worker.replace('__VERSION__', json.dumps(digest.hexdigest()))
    worker = worker.replace('__FILES__', json.dumps(paths))
    (root / 'amid-sw.js').write_text(worker)
    return {'files': len(files), 'version': digest.hexdigest()}


if __name__ == '__main__':
    print(json.dumps(generate(sys.argv[1])))
