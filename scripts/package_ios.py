#!/usr/bin/env python3
"""Package an unsigned iPhoneOS .app for subsequent personal signing.

This validates structure only. The resulting IPA is neither signed nor tested on
an iPhone. Signing/provisioning must happen before installation.
"""
import argparse
from pathlib import Path
import os
import plistlib
import re
import stat
import struct
import zipfile


def package_app(app, output):
    app, output = Path(app).resolve(), Path(output).resolve()
    if not app.is_dir() or app.suffix != '.app' or output.is_relative_to(app):
        raise ValueError('Expected a .app directory and an output outside it')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = info.get('CFBundleExecutable', '')
    if not executable or Path(executable).name != executable or executable in {'.', '..'}:
        raise ValueError('Unsafe CFBundleExecutable')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('The bundle must target a physical iPhone, not a simulator')
    if not re.fullmatch(r'\d+\.\d+\.\d+', info.get('CFBundleShortVersionString', '')):
        raise ValueError('The built bundle must contain a concrete release version')
    binary = app / executable
    with binary.open('rb') as source:
        header = source.read(8)
    if len(header) != 8 or struct.unpack('<II', header) != (0xfeedfacf, 0x100000c):
        raise ValueError('Expected a thin ARM64 Mach-O executable')
    if not binary.stat().st_mode & 0o111:
        raise ValueError('The app executable is missing executable permissions')
    if (app / '_CodeSignature').exists() or (app / 'embedded.mobileprovision').exists():
        raise ValueError('This packager expects an unsigned app without provisioning')
    entries = [app, *sorted(app.rglob('*'))]
    for path in entries:
        if not path.resolve().is_relative_to(app):
            raise ValueError(f'Bundle link escapes the app: {path.name}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in entries:
            name = 'Payload/' + path.relative_to(app.parent).as_posix()
            mode = path.lstat().st_mode
            if stat.S_ISDIR(mode):
                name += '/'
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = mode << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            if stat.S_ISLNK(mode):
                archive.writestr(entry, os.readlink(path).encode())
            elif stat.S_ISDIR(mode):
                archive.writestr(entry, b'')
            else:
                with path.open('rb') as source, archive.open(entry, 'w', force_zip64=True) as target:
                    while chunk := source.read(1024 * 1024):
                        target.write(chunk)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('The packaged IPA is corrupt')
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    info = package_app(args.app, args.output)
    print(f'Packaged {info["CFBundleIdentifier"]} {info["CFBundleShortVersionString"]}; UNSIGNED; device testing not run')


if __name__ == '__main__':
    main()
