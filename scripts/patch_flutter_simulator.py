#!/usr/bin/env python3
"""Backport Flutter #193142 only into the pinned ephemeral iOS CI toolchain.

The engine, Dart SDK, application and release builds are unchanged. Both complete
source hashes are checked. Remove this backport when upgrading Flutter.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

DATA = Path(__file__).with_name('flutter_ios_log_ready_patch.json')


def patch_sdk(sdk, *, verify_only=False):
    data = json.loads(DATA.read_text(encoding='utf-8'))
    target = sdk / data['path']
    raw = target.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest == data['afterSha256']:
        print('AMID_IOS_TOOL_PATCH_OK: already applied')
        return
    if digest != data['beforeSha256']:
        raise ValueError('Unsupported Flutter tool source. Review/remove the pinned iOS backport when upgrading SDK.')
    text = raw.decode('utf-8')
    for change in data['changes']:
        if text.count(change['old']) != 1:
            raise ValueError('Upstream patch context is not unique')
        text = text.replace(change['old'], change['new'], 1)
    result = text.encode('utf-8')
    if hashlib.sha256(result).hexdigest() != data['afterSha256']:
        raise ValueError('Patched Flutter source hash mismatch')
    if not verify_only:
        temporary = target.with_suffix('.amid.tmp')
        temporary.write_bytes(result)
        temporary.replace(target)
        # The next Flutter command must compile the patched tool, not a cached snapshot.
        for name in ['flutter_tools.snapshot', 'flutter_tools.stamp']:
            (sdk / 'bin/cache' / name).unlink(missing_ok=True)
    print('AMID_IOS_TOOL_PATCH_OK: ' + ('verified only; ' if verify_only else 'applied; ') + data['upstreamCommit'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=os.environ.get('FLUTTER_ROOT'))
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if args.sdk is None:
        parser.error('FLUTTER_ROOT or --sdk is required')
    patch_sdk(args.sdk.resolve(), verify_only=args.verify_only)


if __name__ == '__main__':
    main()
