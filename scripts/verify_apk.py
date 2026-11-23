#!/usr/bin/env python3
"""Check the installable archive, ARM64 native libraries and 16 KiB ELF pages."""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

apk = Path(sys.argv[1])
with zipfile.ZipFile(apk) as archive:
    if archive.testzip() is not None:
        raise SystemExit('APK contains a corrupt entry')
    names = set(archive.namelist())
    required = {'AndroidManifest.xml', 'classes.dex',
                'lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libapp.so'}
    if not required <= names:
        raise SystemExit('APK is missing required application files')
    native = sorted(n for n in names if n.startswith('lib/') and n.endswith('.so'))
    for name in native:
        if not name.startswith('lib/arm64-v8a/'):
            raise SystemExit(f'Unexpected native ABI: {name}')
        data = archive.read(name)
        if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
            raise SystemExit(f'Not an ARM64 ELF library: {name}')
        phoff = struct.unpack_from('<Q', data, 32)[0]
        entry_size, count = struct.unpack_from('<HH', data, 54)
        for index in range(count):
            kind, _, offset, address, _, _, _, alignment = struct.unpack_from(
                '<IIQQQQQQ', data, phoff + index * entry_size)
            if kind == 1 and (alignment < 16384 or offset % 16384 != address % 16384):
                raise SystemExit(f'ELF segment does not support 16 KiB pages: {name}')

sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
if sdk:
    tools = sorted((Path(sdk) / 'build-tools').glob('*/apksigner'))
    if not tools:
        raise SystemExit('Android SDK apksigner is missing')
    subprocess.run([str(tools[-1]), 'verify', '--verbose', str(apk)], check=True)
    subprocess.run([str(tools[-1].with_name('zipalign')), '-c', '-P', '16', '4', str(apk)], check=True)

print(f'Validated {len(native)} ARM64 libraries; SHA-256 {hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()}')
