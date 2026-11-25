#!/usr/bin/env python3
"""Build an AAB with model bytes only in an install-time AI pack.

The standalone APK keeps its usual complete Flutter payload. During this build
only, move the untracked parts to the pack at the same AssetManager keys. Keep
catalog/bundle metadata and licenses in base. Always restore parts on failure.
Do not run another Flutter build concurrently in this checkout.
"""
import argparse
from contextlib import contextmanager
import os
from pathlib import Path
import subprocess

from prepare_offline_payload import ROOT, catalog, verify_parts

PACK = Path('android/offline_model/src/main/assets/flutter_assets/assets/offline_model')


@contextmanager
def staged_model(root, model):
    source = root / 'assets/offline_model'
    record = verify_parts(lambda name: (source / name).open('rb'), model)
    target = root / PACK
    # A nonempty folder indicates an interrupted or simultaneous build. Preserve
    # it for recovery instead of deleting possibly unique model bytes.
    target.mkdir(parents=True, exist_ok=False)
    moved = []
    try:
        for index in range(record['parts']):
            name = f'model-{index:03d}.part'
            (source / name).rename(target / name)
            moved.append(name)
        yield
    finally:
        for name in moved:
            if (source / name).exists():
                raise RuntimeError('Concurrent asset mutation; preserve pack for manual recovery')
            (target / name).rename(source / name)
        target.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    command = ['flutter', 'build', 'appbundle', '--debug' if args.debug else '--release',
               '--target-platform', 'android-x64' if args.debug else 'android-arm64']
    if args.debug:
        command += ['--target', 'integration_test/mobile_smoke_test.dart',
                    '--dart-define=AMID_REQUIRE_FULL_STARTER=true']
        if os.environ.get('AMID_TEST_ABI') != 'x86_64':
            parser.error('The debug integration bundle requires AMID_TEST_ABI=x86_64')
    environment = dict(os.environ, ORG_GRADLE_PROJECT_amidPlayBundle='true',
                       CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    with staged_model(ROOT, catalog()['model']):
        # No --no-pub: release registrants must exclude integration_test.
        subprocess.run(command, cwd=ROOT, env=environment, check=True)
    print('AMID_PLAY_BUILD_OK: full APK payload restored; AI pack was build-only')


if __name__ == '__main__':
    main()
