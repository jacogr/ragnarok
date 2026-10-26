#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the optional resident guest executor against pristine pinned public PolkaVM sources.

Exposes build_native for production and selected native test profiles. All Cargo commands
use the shared pinned Rust toolchain and checked-in lockfile; no upstream scripts are patched.
"""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tomllib
from native_dependencies import ROOT, require_submodule


def build_native():
    """Validate source identity and build the optional ABI, retaining its complete log."""
    pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
    upstream = require_submodule(pins, False)
    fields = ('name', 'version', 'source', 'checksum')
    known = {tuple(package.get(key) for key in fields)
             for package in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
    for package in tomllib.loads((ROOT/'native/polkavm/Cargo.lock').read_text())['package']:
        # The bridge adds no transitive upgrade beyond the pristine upstream closure.
        if package['name'] != 'ragnarok-polkavm' and tuple(package.get(key) for key in fields) not in known:
            raise ValueError('Unpinned runtime dependency: '+package['name'])
    rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    target = ROOT/'build/polkavm'
    target.mkdir(parents=True, exist_ok=True)
    command = ['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked',
               '--manifest-path', str(ROOT/'native/polkavm/Cargo.toml'), '--target-dir', str(target)]
    with (target/'build.log').open('w') as log:
        # ABI trust-boundary and reset/ownership tests run before a library can enter the application.
        tests = command.copy()
        tests[4] = 'test'
        subprocess.run(tests, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    suffix = '.dylib' if platform.system() == 'Darwin' else '.so'
    library = target/'release'/('libragnarok_polkavm'+suffix)
    if not library.is_file():
        raise FileNotFoundError('Missing optional PolkaVM ABI: '+str(library))
    return library


def prepare(folder):
    """Supply the regular native runner's library and explicit source/build evidence."""
    library = build_native()
    evidence = dict(pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text()), patches=[],
                    library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
                    lock_sha256=hashlib.sha256((ROOT/'native/polkavm/Cargo.lock').read_bytes()).hexdigest(),
                    log='build/polkavm/build.log')
    return library, evidence


if __name__ == '__main__':
    # Make owns dependency setup before invoking this supported optional build entry point.
    print(build_native())
