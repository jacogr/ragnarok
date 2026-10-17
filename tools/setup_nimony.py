#!/usr/bin/env python3
"""Install the same pinned Nimony compiler/formatter for local development and Linux CI."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import shlex
import hashlib
from toolchain_archives import ROOT, download, extract


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
    for relative in ('bin/nimony', 'bin/nifmake', 'bin/niflink', 'bin/hastur', 'lib/std/system.nim'):
        if not (root/relative).is_file():
            raise ValueError('Missing Nimony archive member: '+relative)
    return metadata


# Export only Nimony tools and the formatter binary; historical Nim 2 is not a second compiler on PATH.
def install(destination, pins):
    destination.mkdir(parents=True, exist_ok=True)
    data = download(pins['download'], destination/'nimony.archive')
    root = extract(data, destination/('nightly-'+pins['commit']))
    metadata = verify_identity(root, pins)
    formatter_data = download(pins['formatter_download'], destination/'formatter.archive')
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


# Nimony emits its banner on stderr; capture both streams and reject mismatches/nonzero exits before PATH export.
def verify_version(compiler, expected):
    version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT)
    if not version.startswith(expected+' '):
        raise ValueError('Nimony binary version disagrees with its archive pin: '+repr(version))
    return version


# Select only explicitly pinned hosts; an unknown architecture must never execute a mismatched binary.
def host_pins(pins, system=None, machine=None):
    system = platform.system() if system is None else system
    machine = platform.machine() if machine is None else machine
    for name, entry in pins['platforms'].items():
        # Release metadata uses the archive platform name, not Python's host spelling.
        if entry['system'] == system and machine in entry['machines']:
            return {**pins, **entry, 'platform': name}
    raise ValueError('No pinned Nimony archive for '+system+' '+machine)


# Nimony dependency indexes retain toolchain paths; relocating an identical compiler needs a separate cache.
def cache_directory(compiler, folder, name):
    identity = hashlib.sha256(str(Path(compiler).resolve()).encode()).hexdigest()[:16]
    return Path(folder)/('compiler-'+identity)/(name+'-cache')


# Resolve the normal local installation without depending on a global compiler executable.
def installed(destination=None):
    destination = ROOT/'build/toolchain' if destination is None else Path(destination)
    manifest = json.loads((destination/'environment.json').read_text())
    pins = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()))
    verify_identity(Path(manifest['compiler']).parent.parent, pins)
    verify_version(Path(manifest['compiler']), pins['version'])
    if hashlib.sha256(Path(manifest['compiler']).read_bytes()).hexdigest() != manifest['compiler_sha256']:
        raise ValueError('Installed compiler differs from its verified archive')
    # Formatter integrity is checked independently: its generic banner alone cannot identify the archive revision.
    formatter = Path(manifest['formatter'])
    if hashlib.sha256(formatter.read_bytes()).hexdigest() != manifest['formatter_sha256']:
        raise ValueError('Installed formatter differs from its verified archive')
    if manifest['pins_sha256'] != hashlib.sha256((ROOT/'spec/toolchain.json').read_bytes()).hexdigest():
        raise ValueError('Toolchain pins changed; rerun setup')
    return Path(manifest['compiler']), formatter


# Install project-local tools, print a sourceable environment, and export the same paths to GitHub steps.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, default=ROOT/'build/toolchain')
    args = parser.parse_args()
    pins = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()))
    destination = args.destination.resolve()
    root, paths, metadata = install(destination, pins)
    compiler, formatter = root/'bin/nimony', paths[1]/'nimpretty'
    version = verify_version(compiler, pins['version'])
    banner = subprocess.check_output([str(formatter), '--version'], text=True).strip()
    if banner != pins['formatter_banner']:
        raise ValueError('Unexpected formatter banner: '+banner)
    manifest = dict(compiler=str(compiler), formatter=str(formatter),
                    compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                    formatter_sha256=hashlib.sha256(formatter.read_bytes()).hexdigest(),
                    pins_sha256=hashlib.sha256((ROOT/'spec/toolchain.json').read_bytes()).hexdigest())
    (destination/'environment.json').write_text(json.dumps(manifest, indent=2)+'\n')
    # Shell quoting preserves spaces without executing any path as shell code during setup.
    (destination/'env.sh').write_text('export NIMONY='+shlex.quote(str(compiler))+'\n'+
        'export NIMPRETTY='+shlex.quote(str(formatter))+'\n'+
        'export PATH='+shlex.quote(':'.join(str(path) for path in paths))+':"$PATH"\n')
    if os.environ.get('GITHUB_PATH'):
        # GitHub consumes the same selected compiler and formatter-only directories in later steps.
        with Path(os.environ['GITHUB_PATH']).open('a') as output:
            output.write(''.join(str(path)+'\n' for path in paths))
    if os.environ.get('GITHUB_ENV'):
        # Never export the historical Nim 2 compiler bundled alongside the formatter source archive.
        with Path(os.environ['GITHUB_ENV']).open('a') as output:
            output.write('NIMONY='+str(compiler)+'\nNIMPRETTY='+str(formatter)+'\n')
    print(metadata+version)
    print('Environment: '+str(destination/'env.sh'))


# Importing validation helpers never downloads or executes a compiler.
if __name__ == '__main__':
    main()
