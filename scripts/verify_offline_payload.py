#!/usr/bin/env python3
"""Verify the actual model bytes inside a built native bundle/APK/IPA/ZIP."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from prepare_offline_payload import catalog, verify_parts


def verify(path, data):
    suffix = 'flutter_assets/assets/offline_model/bundle.json'
    if path.is_dir():
        candidates = [p for p in path.rglob('bundle.json') if p.as_posix().endswith(suffix)]
        if len(candidates) != 1:
            raise ValueError('Expected exactly one native Flutter payload')
        folder = candidates[0].parent
        return verify_content(lambda name: (folder / name).open('rb'),
                              lambda name: (folder.parent.parent / name).open('rb'), data)
    with zipfile.ZipFile(path) as archive:
        candidates = [name for name in archive.namelist() if name.endswith(suffix)]
        if len(candidates) != 1:
            raise ValueError('Expected exactly one native Flutter payload in archive')
        prefix = candidates[0][:-len('bundle.json')]
        assets = candidates[0][:-len('assets/offline_model/bundle.json')]
        if path.suffix == '.aab':
            expected_base = 'base/assets/flutter_assets/assets/offline_model/'
            pack = 'offline_model/assets/flutter_assets/assets/offline_model/'
            if prefix != expected_base:
                raise ValueError('Unexpected Play base payload location')
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError('Duplicate bundle entries')
            with archive.open(prefix + 'bundle.json') as source:
                record = json.load(source)
            if not isinstance(record.get('parts'), int) or not 0 < record['parts'] <= 4096:
                raise ValueError('Invalid Play part count')
            expected_parts = {pack + f'model-{i:03d}.part' for i in range(record['parts'])}
            actual_parts = {name for name in names if name.startswith('offline_model/assets/') and not name.endswith('/')}
            if actual_parts != expected_parts:
                raise ValueError('AI pack must contain exactly the declared model parts')
            if any(name.startswith('base/') and (name.endswith('.part') or name.endswith('.gguf')) for name in names):
                raise ValueError('Model bytes must not be duplicated in base')
            if any(name.startswith('offline_model/') and not name.endswith('/') and
                   not (name in expected_parts or name == 'offline_model/manifest/AndroidManifest.xml') for name in names):
                raise ValueError('Unexpected code or metadata in AI pack')
            read_model = lambda name: archive.open((pack if name.endswith('.part') else prefix) + name)
        else:
            read_model = lambda name: archive.open(prefix + name)
        return verify_content(read_model,
                              lambda name: archive.open(assets + name), data)


def verify_content(read_model, read_asset, data):
    with read_model('catalog.json') as source:
        if json.load(source) != data:
            raise ValueError('The packaged catalog differs from the source catalog')
    for key in ['map', 'knowledge']:
        entry = data[key]
        with read_asset(entry['asset']) as source:
            raw = source.read(entry['bytes'] + 1)
        if len(raw) != entry['bytes'] or hashlib.sha256(raw).hexdigest() != entry['sha256']:
            raise ValueError('Packaged map/knowledge mismatch')
    return verify_parts(read_model, data['model'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    args = parser.parse_args()
    record = verify(args.artifact, catalog())
    print(f'AMID_PACKAGED_STARTER_OK: {args.artifact.name}, {record["bytes"]} model bytes, SHA-256 verified')


if __name__ == '__main__':
    main()
