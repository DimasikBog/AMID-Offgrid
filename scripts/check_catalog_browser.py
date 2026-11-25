#!/usr/bin/env python3
"""Compile actual bundled metadata into the Chrome test without a mock asset channel.
Flutter's browser unit-test binding does not serve rootBundle assets like the app.
"""
import argparse
import base64
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['chrome', 'vm'], default='chrome')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='amid-catalog-test-') as directory:
        defines = Path(directory) / 'metadata.json'
        defines.write_text(json.dumps({
            'OFFGRID_CATALOG_BASE64': base64.b64encode((ROOT / 'assets/catalog.json').read_bytes()).decode('ascii'),
            'OFFGRID_STARTER_BASE64': base64.b64encode((ROOT / 'assets/offline_model/catalog.json').read_bytes()).decode('ascii'),
            'OFFGRID_MESH_VECTORS_BASE64': base64.b64encode((ROOT / 'test/fixtures/mesh_vectors.json').read_bytes()).decode('ascii'),
        }))
        platform = ['--platform', 'chrome'] if args.platform == 'chrome' else []
        subprocess.run(['flutter', 'test', '--no-pub', *platform,
                        '--dart-define-from-file', str(defines),
                        'test/catalog_metadata_test.dart',
                        'test/offline_profile_codec_test.dart',
                        'test/mesh_wire_test.dart'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
