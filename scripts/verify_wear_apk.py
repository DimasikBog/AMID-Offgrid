#!/usr/bin/env python3
"""Check that the pocket APK is standalone managed code, not a Flutter bundle."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import zipfile

apk = Path(sys.argv[1])
with zipfile.ZipFile(apk) as z:
    assert z.testzip() is None
    names = set(z.namelist())
    assert {'AndroidManifest.xml', 'classes.dex', 'assets/cards.json'} <= names
    assert not any(n.startswith('lib/') and n.endswith('.so') for n in names)
    assert apk.stat().st_size < 20 * 1024 * 1024
sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
if not sdk:
    raise SystemExit('Android SDK is required to verify pocket signing')
tools = sorted((Path(sdk) / 'build-tools').glob('*/apksigner'))
subprocess.run([str(tools[-1]), 'verify', '--verbose', str(apk)], check=True)
print('Managed-code pocket APK:', apk.stat().st_size, 'bytes; SHA-256',
      hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest())
