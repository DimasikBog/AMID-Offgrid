#!/usr/bin/env python3
"""Validate a real AAB, its install-time manifest and its actual model bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

from prepare_offline_payload import ROOT, catalog
from verify_offline_payload import verify

BUNDLETOOL_VERSION = '1.18.3'
BUNDLETOOL_SHA256 = 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29'
BUNDLETOOL_BYTES = 32520401
DIST = '{http://schemas.android.com/apk/distribution}'


def bundletool():
    path = ROOT / f'build/tools/bundletool-all-{BUNDLETOOL_VERSION}.jar'
    def matches():
        if not path.is_file() or path.stat().st_size != BUNDLETOOL_BYTES:
            return False
        with path.open('rb') as source:
            return hashlib.file_digest(source, 'sha256').hexdigest() == BUNDLETOOL_SHA256
    if not matches():
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_suffix('.partial')
        try:
            url = f'https://github.com/google/bundletool/releases/download/{BUNDLETOOL_VERSION}/{path.name}'
            with urllib.request.urlopen(url, timeout=60) as response, partial.open('wb') as output:
                size = 0
                while block := response.read(1024 * 1024):
                    size += len(block)
                    if size > BUNDLETOOL_BYTES:
                        raise ValueError('Unexpected bundletool download size')
                    output.write(block)
            with partial.open('rb') as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            if size != BUNDLETOOL_BYTES or digest != BUNDLETOOL_SHA256:
                raise ValueError('Bundletool SHA-256 mismatch')
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    return path


def command(jar, *args):
    return subprocess.check_output(['java', '-jar', str(jar), *map(str, args)], text=True)


def verify_delivery(xml):
    manifest = ET.fromstring(xml)
    if manifest.get('split') != 'offline_model':
        raise ValueError('Unexpected AI pack name')
    module = manifest.find(DIST + 'module')
    if module is None or module.get(DIST + 'type') != 'ai-pack':
        raise ValueError('Expected an AI pack module')
    delivery = module.find(DIST + 'delivery')
    if delivery is None or len(delivery) != 1 or delivery[0].tag != DIST + 'install-time':
        raise ValueError('Model must arrive at install time')
    if len(delivery[0]) or delivery[0].get(DIST + 'removable') == 'true':
        raise ValueError('The starter must be unconditional and non-removable')


def inspect(path, evidence):
    record = verify(path, catalog())
    jar = bundletool()
    validation = command(jar, 'validate', f'--bundle={path}')
    manifest = command(jar, 'dump', 'manifest', f'--bundle={path}', '--module=offline_model')
    verify_delivery(manifest)
    with zipfile.ZipFile(path) as archive:
        sizes = {module: sum(i.compress_size for i in archive.infolist()
                            if i.filename.startswith(module + '/'))
                 for module in ['base', 'offline_model']}
    # Conservative ZIP-content guard. Actual Play delivery size/acceptance must
    # still be checked in Play Console; do not label this a store approval.
    if sizes['base'] >= 500_000_000 or sizes['offline_model'] >= 1_500_000_000:
        raise ValueError('Module ZIP content exceeds the configured Play size guard')
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / 'ai-pack-manifest.xml').write_text(manifest, encoding='utf-8')
    (evidence / 'bundle-validation.txt').write_text(validation, encoding='utf-8')
    with path.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    result = {'artifact': path.name, 'sha256': digest, 'bytes': path.stat().st_size,
              'bundletoolVersion': BUNDLETOOL_VERSION, 'bundletoolSha256': BUNDLETOOL_SHA256,
              'delivery': 'install-time', 'modelBytes': record['bytes'],
              'modelSha256': record['sha256'], 'moduleZipCompressedBytes': sizes,
              'physicalDeviceTesting': 'not_run', 'googlePlayTesting': 'not_run'}
    (evidence / 'play-bundle.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('AMID_PLAY_BUNDLE_OK:', json.dumps(result))
    return jar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--evidence', type=Path, default=ROOT / 'build/play-evidence')
    args = parser.parse_args()
    inspect(args.artifact.resolve(), args.evidence)


if __name__ == '__main__':
    main()
