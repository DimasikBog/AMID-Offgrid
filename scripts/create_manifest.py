#!/usr/bin/env python3
"""Record artifact provenance without inventing signing or device-test results."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from check_project import project_version


def create_manifest(artifacts, *, commit, platform, signing, run_url, quality='not_recorded'):
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('An exact source commit is required')
    if platform not in {'android', 'ios'} or signing not in {'development', 'distribution', 'unsigned'}:
        raise ValueError('Invalid platform or signing state')
    if (platform == 'android' and signing == 'unsigned') or (platform == 'ios' and signing == 'development'):
        raise ValueError('Unsupported signing state for this pipeline')
    if run_url and not re.fullmatch(r'https://github\.com/[^/]+/[^/]+/actions/runs/\d+', run_url):
        raise ValueError('Expected a canonical GitHub Actions run URL')
    if quality not in {'success', 'not_recorded'}:
        raise ValueError('Invalid quality result')
    version, build = project_version()
    files = []
    for artifact in artifacts:
        path = Path(artifact)
        if path.suffix not in ({'.apk', '.aab'} if platform == 'android' else {'.ipa', '.zip'}):
            raise ValueError('Artifact extension does not match its platform')
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        files.append({'file': path.name, 'bytes': path.stat().st_size, 'sha256': digest,
                      'kind': path.suffix[1:], 'signing': signing,
                      'physicalDeviceTested': False})
    if not files or len({f['file'] for f in files}) != len(files):
        raise ValueError('At least one uniquely named artifact is required')
    return {'schemaVersion': 1, 'product': 'AMID Offgrid', 'version': version, 'build': build,
            'platform': platform, 'sourceCommit': commit, 'githubRunUrl': run_url,
            'quality': quality, 'deviceTesting': 'not_run', 'storeSubmission': 'not_run',
            'artifacts': files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', action='append', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--platform', required=True, choices=['android', 'ios'])
    parser.add_argument('--signing', required=True, choices=['development', 'distribution', 'unsigned'])
    parser.add_argument('--run-url', default='')
    parser.add_argument('--quality', default='not_recorded', choices=['success', 'not_recorded'])
    parser.add_argument('--output', type=Path, default=Path('dist/release-manifest.json'))
    args = parser.parse_args()
    manifest = create_manifest(args.artifact, commit=args.commit, platform=args.platform,
                               signing=args.signing, run_url=args.run_url, quality=args.quality)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (args.output.parent / 'SHA256SUMS.txt').write_text(''.join(
        f'{entry["sha256"]}  {entry["file"]}\n' for entry in manifest['artifacts']))
    print(f'Recorded {len(manifest["artifacts"])} artifacts for {manifest["sourceCommit"]}; devices and stores: not run')


if __name__ == '__main__':
    main()
