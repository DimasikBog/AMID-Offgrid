#!/usr/bin/env python3
"""Create an offline cache from the final local web build, including its renderer."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import quote


def generate(root, template_path=None):
    root = Path(root)
    if not (root / 'index.html').is_file() or not (root / 'flutter_bootstrap.js').is_file():
        raise ValueError('Expected a complete Flutter web build')
    # A distinct bootstrap URL lets the pre-0.5 web worker fetch the new host
    # configuration instead of serving its cached full-page bootstrap.
    index = root / 'index.html'
    html = index.read_text()
    if 'src="flutter_bootstrap.js"' in html or 'src="amid-bootstrap.js"' in html:
        (root / 'amid-bootstrap.js').write_bytes((root / 'flutter_bootstrap.js').read_bytes())
        index.write_text(html.replace('src="flutter_bootstrap.js"', 'src="amid-bootstrap.js"'))
    files = sorted(p for p in root.rglob('*') if p.is_file()
                   and p.name not in {'amid-sw.js', 'flutter_service_worker.js'}
                   and p.suffix != '.map')
    template = Path(template_path or Path(__file__).with_name('web_worker.js')).read_text()
    digest = hashlib.sha256(template.encode())
    records = []
    for path in files:
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Static asset escapes the build directory')
        relative = path.relative_to(root).as_posix()
        with path.open('rb') as source:
            sha = hashlib.file_digest(source, 'sha256').hexdigest()
        record = {'path': quote(relative, safe='/'), 'bytes': path.stat().st_size, 'sha256': sha}
        records.append(record)
        digest.update(json.dumps(record, sort_keys=True).encode())
    worker = template.replace('__VERSION__', json.dumps(digest.hexdigest()))
    worker = worker.replace('__FILES__', json.dumps(records))
    (root / 'amid-sw.js').write_text(worker)
    return {'files': len(files), 'version': digest.hexdigest()}


if __name__ == '__main__':
    print(json.dumps(generate(sys.argv[1])))
