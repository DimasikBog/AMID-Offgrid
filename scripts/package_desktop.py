#!/usr/bin/env python3
"""Zip the whole native bundle. Preserve executables, resolve only internal links."""
import argparse
from pathlib import Path
import zipfile


def package(source, output, extras=()):
    source, output = Path(source).resolve(), Path(output)
    if not source.is_dir():
        raise ValueError('Build bundle does not exist')
    files = sorted(p for p in source.rglob('*') if p.is_file())
    if not files:
        raise ValueError('Empty build bundle')
    for path in files:
        if not path.resolve().is_relative_to(source):
            raise ValueError('Bundle symlink escapes the application directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(source).as_posix())
        for path in map(Path, extras):
            archive.write(path, 'AMID_DOCUMENTATION/' + path.name)
    return len(files)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('output')
    parser.add_argument('--extra', action='append', default=[])
    args = parser.parse_args()
    print('Packaged', package(args.source, args.output, args.extra), 'bundle files')
