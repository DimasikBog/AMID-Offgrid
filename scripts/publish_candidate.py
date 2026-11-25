#!/usr/bin/env python3
"""Publish only complete, hash-verified outputs of this trusted workflow run."""
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request


def main():
    repo, commit = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA']
    token = os.environ['GH_TOKEN']
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid repository/source identity')
    if os.environ['GITHUB_EVENT_NAME'] not in {'push', 'workflow_dispatch'}:
        raise ValueError('Publishing is restricted to trusted push/manual runs')
    def request(path, data=None, method=None, binary=None):
        url = 'https://api.github.com/repos/' + repo + path
        payload = json.dumps(data).encode() if data is not None else binary
        headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                   'X-GitHub-Api-Version': '2022-11-28'}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        if binary is not None:
            url = 'https://uploads.github.com/repos/' + repo + path
            headers['Content-Type'] = 'application/octet-stream'
        req = urllib.request.Request(url, data=payload, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=300 if binary is not None else 60) as response:
            return json.load(response)
    metadata = request('')
    if metadata['private']:
        raise ValueError('Public release requires a public repository')
    manifests = []
    uploads = []
    for path in sorted(Path('downloaded').rglob('release-manifest.json')):
        record = json.loads(path.read_text())
        if record['sourceCommit'] != commit or record['quality'] != 'success':
            raise ValueError('Unverified or wrong-source artifact')
        if record['platform'] in {'android', 'ios', 'windows', 'linux', 'macos'} and not (record.get('offlineStarter') or {}).get('modelIncluded'):
            raise ValueError('The native release must include its verified offline starter')
        if record['deviceTesting'] != 'not_run' or record['storeSubmission'] != 'not_run':
            raise ValueError('Unexpected device/store claim')
        for artifact in record['artifacts']:
            name = artifact['file']
            if Path(name).name != name:
                raise ValueError('Invalid artifact path')
            data = path.parent / name
            with data.open('rb') as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            if data.stat().st_size != artifact['bytes'] or digest != artifact['sha256']:
                raise ValueError('Artifact size/hash mismatch')
            uploads.append((name, data))
        sidecar = path.with_name(record['platform'] + '-manifest.json')
        sidecar.write_text(json.dumps(record, indent=2) + '\n')
        uploads.append((sidecar.name, sidecar))
        manifests.append(record)
    platforms = {m['platform'] for m in manifests}
    if platforms != {'android','ios','windows','linux','macos','wearos','watchos','web'} or len(manifests) != 8:
        raise ValueError('All eight platform outputs are required')
    identities = {(m['version'], m['build']) for m in manifests}
    if len(identities) != 1:
        raise ValueError('Mixed artifact versions')
    version, build = identities.pop()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not isinstance(build, int):
        raise ValueError('Invalid release version')
    if len({name for name, _ in uploads}) != len(uploads):
        raise ValueError('Duplicate release asset names')
    tag = f'v{version}-beta.{build}'
    try:
        release = request('/releases/tags/' + tag)
        old = request('/git/commits/' + release['target_commitish'])
        current = request('/git/commits/' + commit)
        if old['tree']['sha'] != current['tree']['sha']:
            raise ValueError('Existing release belongs to different source')
        if not release['draft']:
            print('Existing verified release:', release['html_url'])
            return
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        release = request('/releases', {
            'tag_name': tag, 'target_commitish': commit, 'name': 'AMID Offgrid ' + tag,
            'prerelease': True, 'draft': True,
            'body': 'Повний офлайн-набір: нативні телефонні та комп’ютерні пакети містять Qwen3 0.6B, оглядову карту світу й довідник. Підготовка моделі автоматична; детальні карти вулиць додаються окремо. Web і годинники мають окремий обмежений набір.\n\nТестовий кандидат. Джерело: `' + commit + '`.\n\n'
                    'Android і Wear OS мають development-підпис. iOS, watchOS і macOS потребують перевірки особистого підписування/довіри. '
                    'Фізичні пристрої та магазини: не перевірені.\n\n'
                    'Завантаж відповідний пакет і маніфест своєї платформи. Інструкції: docs/INSTALL.md у репозиторії.'})
    # Drafts are not installation releases. Refuse ambiguous partial retries.
    if release.get('assets'):
        raise ValueError('Partial draft already contains assets; inspect before retry')
    for name, path in uploads:
        request('/releases/' + str(release['id']) + '/assets?name=' + urllib.parse.quote(name),
                binary=path.read_bytes(), method='POST')
    release = request('/releases/' + str(release['id']), {'draft': False}, method='PATCH')
    print('Published candidate:', release['html_url'])


if __name__ == '__main__':
    main()
