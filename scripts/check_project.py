#!/usr/bin/env python3
"""Small offline checks for release identity and private-file exclusions."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def project_version(root=ROOT):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
                      (root / 'pubspec.yaml').read_text(), re.MULTILINE)
    if not match:
        raise ValueError('pubspec.yaml must have a version and build number')
    return match.group(1), int(match.group(2))


def main():
    version, build = project_version()
    dart = (ROOT / 'lib/version.dart').read_text()
    if f"const appVersion = '{version}';" not in dart:
        raise ValueError('Update lib/version.dart to match pubspec.yaml')
    seed = json.loads((ROOT / 'assets/starter.json').read_text())
    if seed['format'] != 'AMID_OFFGRID_PACK' or seed['version'] != 1:
        raise ValueError('Invalid starter pack')
    if len({a['id'] for a in seed['articles']}) != len(seed['articles']):
        raise ValueError('Duplicate starter article IDs')
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    forbidden = [name for name in tracked if name and (
        Path(name).suffix.lower() in {'.p12', '.p8', '.jks', '.keystore', '.mobileprovision'}
        or name in {'android/key.properties', 'android/productos-debug-keystore.b64'})]
    if forbidden:
        raise ValueError('Private signing files must not be committed: ' + ', '.join(forbidden))
    print(f'Project identity: {version}+{build}; starter data and signing exclusions valid')


if __name__ == '__main__':
    main()
