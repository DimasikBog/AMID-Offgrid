#!/usr/bin/env python3
"""Build a bounded-memory Flutter payload from a pinned, verified GGUF file."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CHUNK_BYTES = 8 * 1024 * 1024


def catalog(root=ROOT):
    data = json.loads((root / 'assets/offline_model/catalog.json').read_text())
    model = data['model']
    if data.get('format') != 'AMID_OFFLINE_STARTER' or data.get('version') != 1:
        raise ValueError('Invalid starter catalog')
    if model.get('id') != 'qwen3-06b-q8' or model.get('file') != 'qwen3-06b-q8.gguf':
        raise ValueError('Invalid model identity')
    if not re.fullmatch(r'https://huggingface.co/Qwen/Qwen3-0\.6B-GGUF/resolve/[a-f0-9]{40}/Qwen3-0\.6B-Q8_0\.gguf', model['url']):
        raise ValueError('Model source must use a pinned official revision')
    for key in ['model', 'map', 'knowledge']:
        entry = data[key]
        if not isinstance(entry['bytes'], int) or not 0 < entry['bytes'] <= 8 << 30:
            raise ValueError('Invalid size')
        if not re.fullmatch(r'[a-f0-9]{64}', entry['sha256']):
            raise ValueError('Invalid SHA-256')
    for key, path in [('map', 'assets/world.geojson'), ('knowledge', 'assets/starter.json')]:
        if data[key]['asset'] != path:
            raise ValueError('Unexpected bundled asset')
        content = (root / path).read_bytes()
        if len(content) != data[key]['bytes'] or hashlib.sha256(content).hexdigest() != data[key]['sha256']:
            raise ValueError('Bundled map/knowledge does not match its catalog')
    return data


def matches(path, model):
    return path.is_file() and path.stat().st_size == model['bytes'] and digest(path) == model['sha256']


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def download(model, target, opener=urllib.request.urlopen):
    target.parent.mkdir(parents=True, exist_ok=True)
    if matches(target, model):
        return
    partial = target.with_suffix(target.suffix + '.partial')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > model['bytes']:
        partial.unlink()
        offset = 0
    if offset < model['bytes']:
        headers = {'Accept-Encoding': 'identity'}
        if offset:
            headers['Range'] = f'bytes={offset}-'
        request = urllib.request.Request(model['url'], headers=headers)
        with opener(request, timeout=60) as response:
            if response.status == 200:
                offset = 0
            elif response.status == 206:
                expected = f'bytes {offset}-{model["bytes"]-1}/{model["bytes"]}'
                if response.headers.get('Content-Range') != expected:
                    raise ValueError('Invalid resume response')
            else:
                raise ValueError(f'HTTP {response.status}')
            with partial.open('ab' if offset else 'wb') as output:
                while block := response.read(1024 * 1024):
                    offset += len(block)
                    if offset > model['bytes']:
                        raise ValueError('Model exceeds its declared size')
                    output.write(block)
    if not matches(partial, model):
        if partial.exists() and partial.stat().st_size == model['bytes']:
            partial.unlink()
        raise ValueError('Incomplete/corrupt model; retry to resume an incomplete file')
    partial.replace(target)


def split_model(model, source, destination, chunk_bytes=CHUNK_BYTES):
    if not matches(source, model):
        raise ValueError('Only the verified model may enter a full build')
    if not 0 < chunk_bytes <= CHUNK_BYTES:
        raise ValueError('Chunk memory bound exceeded')
    count = (model['bytes'] + chunk_bytes - 1) // chunk_bytes
    with source.open('rb') as input_file:
        for index in range(count):
            block = input_file.read(chunk_bytes)
            part = destination / f'model-{index:03d}.part'
            temporary = part.with_suffix('.tmp')
            temporary.write_bytes(block)
            temporary.replace(part)
    for obsolete in destination.glob('model-*.part'):
        if obsolete.name not in {f'model-{i:03d}.part' for i in range(count)}:
            obsolete.unlink()
    record = {'format': 'AMID_BUNDLED_MODEL', 'version': 1, 'included': True,
              'bytes': model['bytes'], 'sha256': model['sha256'],
              'chunkBytes': chunk_bytes, 'parts': count}
    temporary = destination / 'bundle.tmp'
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(destination / 'bundle.json')
    return record


def verify_parts(read, model):
    """read(relative path) returns a binary stream from a directory or archive."""
    with read('bundle.json') as source:
        record = json.load(source)
    if record.get('format') != 'AMID_BUNDLED_MODEL' or record.get('version') != 1 or record.get('included') is not True:
        raise ValueError('A full native package must include its model')
    chunk = record['chunkBytes']
    if not isinstance(chunk, int) or not 0 < chunk <= CHUNK_BYTES:
        raise ValueError('Invalid chunk size')
    count = (model['bytes'] + chunk - 1) // chunk
    if record.get('parts') != count or record.get('bytes') != model['bytes'] or record.get('sha256') != model['sha256']:
        raise ValueError('Payload/catalog mismatch')
    hasher = hashlib.sha256()
    size = 0
    for index in range(count):
        part_size = 0
        with read(f'model-{index:03d}.part') as source:
            while block := source.read(1024 * 1024):
                part_size += len(block)
                if part_size > min(chunk, model['bytes'] - size):
                    raise ValueError('Payload part exceeds declared size')
                hasher.update(block)
        if part_size != min(chunk, model['bytes'] - size):
            raise ValueError('Incorrect payload part size')
        size += part_size
    if size != model['bytes'] or hasher.hexdigest() != model['sha256']:
        raise ValueError('Payload SHA-256 mismatch')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/offline-cache')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    model = catalog()['model']
    destination = ROOT / 'assets/offline_model'
    if not args.verify_only:
        source = args.cache / model['file']
        download(model, source)
        split_model(model, source, destination)
    record = verify_parts(lambda name: (destination / name).open('rb'), model)
    print(f'AMID_BUNDLED_MODEL_OK: {record["bytes"]} bytes, {record["parts"]} bounded parts, SHA-256 {model["sha256"]}')


if __name__ == '__main__':
    main()
