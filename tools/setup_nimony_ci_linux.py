#!/usr/bin/env python3
"""Install the checksum-pinned trial compiler and formatter on Linux x86-64; run no upstream installer."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
from setup_ci_linux import ROOT, download, extract


# Require the archive's own identity before any compiler execution or PATH export.
def verify_identity(root, pins):
    metadata = (root/'NIGHTLY.txt').read_text()
    expected = {'nimony-commit': pins['commit'], 'date': pins['date'], 'platform': pins['platform']}
    observed = dict(line.split(':', 1) for line in metadata.splitlines() if ':' in line)
    # Version/date/platform identify the exact selected nightly rather than a moving latest asset.
    for key, value in expected.items():
        if observed.get(key, '').strip() != value:
            raise ValueError('Unexpected Nimony archive identity: '+key)
    # These public tools and standard libraries must retain the official archive layout.
    for relative in ('bin/nimony', 'bin/nifmake', 'bin/niflink', 'lib/std/system.nim'):
        if not (root/relative).is_file():
            raise ValueError('Missing Nimony archive member: '+relative)
    return metadata


# Export only Nimony tools and the formatter binary; historical Nim 2 is not a second compiler on PATH.
def install(destination, pins, formatter_pins):
    if pins['formatter_version'] != formatter_pins['nim_version']:
        raise ValueError('Formatter pin disagrees with historical official archive')
    destination.mkdir(parents=True, exist_ok=True)
    data = download(pins['download'], destination/'nimony.archive')
    root = extract(data, destination/('nightly-'+pins['commit']))
    metadata = verify_identity(root, pins)
    formatter_data = download(formatter_pins['downloads']['nim'], destination/'formatter.archive')
    formatter_root = extract(formatter_data, destination/'formatter-source')
    formatter = formatter_root/'bin/nimpretty'
    if not formatter.is_file():
        raise ValueError('Pinned formatter archive has no nimpretty binary')
    tools = destination/'formatter-bin'
    tools.mkdir(exist_ok=True)
    link = tools/'nimpretty'
    # Repeated installation may replace only the symlink managed by this installer.
    if link.is_symlink():
        link.unlink()
    elif link.exists():
        raise ValueError('Refusing to replace an unrelated formatter path')
    link.symlink_to(formatter)
    return root, [root/'bin', tools], metadata


# Restrict binary execution to its intended host and export exact paths for later GitHub steps.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        raise SystemExit('This installer targets Linux x86-64 only')
    pins = json.loads((ROOT/'spec/nimony-ci-toolchain.json').read_text())
    formatter_pins = json.loads((ROOT/'spec/ci-toolchains.json').read_text())
    root, paths, metadata = install(args.destination.resolve(), pins, formatter_pins)
    version = subprocess.check_output([str(root/'bin/nimony'), '--version'], text=True)
    if not version.startswith(pins['version']+' '):
        raise ValueError('Nimony binary version disagrees with its archive pin')
    subprocess.run([str(paths[1]/'nimpretty'), '--version'], check=True)
    # GitHub consumes these files in subsequent steps; local installation still prints inspectable paths.
    if os.environ.get('GITHUB_PATH'):
        with Path(os.environ['GITHUB_PATH']).open('a') as output:
            output.write(''.join(str(path)+'\n' for path in paths))
    if os.environ.get('GITHUB_ENV'):
        with Path(os.environ['GITHUB_ENV']).open('a') as output:
            output.write('NIMONY='+str(root/'bin/nimony')+'\n')
    print(metadata+version)
    print('\n'.join(str(path) for path in paths))


# Importing archive-validation helpers never downloads or executes a compiler.
if __name__ == '__main__':
    main()
