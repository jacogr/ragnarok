#!/usr/bin/env python3
"""Install checksum-pinned Linux CI tools into isolated runner storage; run no upstream installers."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


# Use retained archives only when their checksum matches the committed official release pin.
def download(entry, archive):
    # Fetch only missing assets; retained assets still undergo verification below.
    if not archive.exists():
        data = urllib.request.urlopen(entry['url'], timeout=60).read()
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['url']
        archive.write_bytes(data)
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise ValueError(f'Checksum mismatch: {archive}') # Never execute or extract a changed release asset.
    return data


# Extract a verified single-root archive safely and return its retained tool/source directory.
def extract(data, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as tar:
        roots = {Path(member.name).parts[0] for member in tar.getmembers() if Path(member.name).parts}
        if len(roots) != 1:
            raise ValueError('Expected one archive root') # Do not guess a binary path from an unexpected layout.
        tar.extractall(destination, filter='data')
    return destination / roots.pop()


# Install the existing compiler/formatter versions only on the selected Linux x86-64 CI target.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        raise SystemExit('This CI installer targets Linux x86-64 only')
    pins = json.loads((ROOT / 'spec/ci-toolchains.json').read_text())
    codec_pins = json.loads((ROOT / 'spec/pins.json').read_text())
    # Reject drift between CI downloads and the versions enforced by the existing test runners.
    assert pins['nim_version'] == codec_pins['toolchains']['nim']
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    paths = {}
    # Each tool is extracted separately so its archive layout cannot collide with another.
    for name in ('nim',):
        data = download(pins['downloads'][name], destination / f'{name}.archive')
        paths[name] = extract(data, destination / name)
    tool_paths = [paths['nim']/'bin']
    # GitHub consumes these paths in later steps; local invocation can instead use the printed directories.
    if os.environ.get('GITHUB_PATH'):
        with Path(os.environ['GITHUB_PATH']).open('a') as output:
            output.write(''.join(str(path) + '\n' for path in tool_paths))
    # Print all tool directories for inspection and local PATH setup.
    for path in tool_paths:
        print(path)
    subprocess.run([str(paths['nim'] / 'bin/nim'), '--version'], check=True)


# Importing helpers for archive validation never downloads or executes a compiler.
if __name__ == '__main__':
    main()
