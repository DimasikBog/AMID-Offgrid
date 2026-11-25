#!/usr/bin/env python3
"""Compile actual bundled metadata into the Chrome test without a mock asset channel.
Flutter's browser unit-test binding does not serve rootBundle assets like the app.
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='amid-catalog-test-') as directory:
        defines = Path(directory) / 'metadata.json'
        defines.write_text(json.dumps({
            'OFFGRID_CATALOG_JSON': (ROOT / 'assets/catalog.json').read_text(),
            'OFFGRID_STARTER_JSON': (ROOT / 'assets/offline_model/catalog.json').read_text(),
        }))
        subprocess.run(['flutter', 'test', '--no-pub', '--platform', 'chrome',
                        '--dart-define-from-file', str(defines),
                        'test/catalog_metadata_test.dart'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
