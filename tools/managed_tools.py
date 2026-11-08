#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Serialize tool setup/cleanup and replace installations at their stable absolute paths.

Build tools embed absolute paths. Keep the prior installation as a rollback directory while
building its replacement, then retire it only after validation succeeds.
"""
from contextlib import contextmanager, nullcontext
import argparse
import fcntl
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
from toolchain_archives import ROOT

TOOLS = ROOT/'build-tools'


def remove(path):
    """Remove a managed entry without following a directory symlink."""
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


@contextmanager
def operation(destination):
    """Exclude concurrent setup/cleanup and recover an interrupted replacement before reuse."""
    TOOLS.mkdir(parents=True, exist_ok=True)
    with (TOOLS/'.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = destination.with_name('.'+destination.name+'-previous')
        if previous.exists():
            # An interrupted replacement never authorizes a partially installed executable.
            remove(destination)
            previous.rename(destination)
        yield
        if destination.parent == TOOLS and destination.is_dir():
            # Retire the old layout only after the replacement or retained installation succeeds.
            remove(TOOLS.parent/'build'/destination.name)


@contextmanager
def replacement(destination, archives=()):
    """Replace one tool, retaining only requested archives and restoring old output on failure.

The caller holds operation() and validates the completed installation inside this context.
"""
    previous = destination.with_name('.'+destination.name+'-previous')
    if destination.is_symlink():
        raise ValueError('Refusing to replace a symlinked tool directory')
    had_previous = destination.exists()
    if had_previous:
        destination.rename(previous)
    try:
        destination.mkdir(parents=True)
        for name in archives:
            # Copy only current pinned archives; each consumer still verifies its checksum.
            cached = previous/name
            if had_previous and cached.is_file():
                shutil.copyfile(cached, destination/name)
        yield
    except BaseException:
        # Build errors and cancellation restore the preceding installation at its original path.
        remove(destination)
        if had_previous:
            previous.rename(destination)
        raise
    else:
        remove(previous)


def clean():
    """Retire all managed tools while preserving the lock inode used by waiting installers."""
    TOOLS.mkdir(parents=True, exist_ok=True)
    with (TOOLS/'.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for path in TOOLS.iterdir():
            # Unlinking the lock itself would let later installers bypass an existing waiter.
            if path.name != '.lock':
                remove(path)


@contextmanager
def native_cache(destination, inputs, commands, outputs):
    """Retain native incremental builds only for unchanged inputs, tools, environment and ABI bytes.

Yield whether the validated outputs are reusable. Callers retain source checks and runtime
assurance; C bridges may skip compilation while Rust adapters still execute Cargo tests/builds.
Changed identities replace the entire cache so old pin versions cannot accumulate indefinitely.
"""
    environment = ('CC', 'CXX', 'AR', 'CFLAGS', 'CPPFLAGS', 'CXXFLAGS', 'LDFLAGS',
                   'RUSTFLAGS', 'RUSTC', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER',
                   'CARGO_ENCODED_RUSTFLAGS', 'CARGO_BUILD_RUSTFLAGS', 'CARGO_BUILD_TARGET',
                   'RUSTUP_TOOLCHAIN', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET', 'CMAKE_GENERATOR')
    files = {__file__: hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    for path in inputs:
        # Inputs include bridge sources/headers, pin declarations and the owning build script.
        selected = sorted(path.rglob('*')) if path.is_dir() else [path]
        for source in selected:
            if source.is_file() and not any(part in ('target', '__pycache__') for part in source.parts):
                files[str(source)] = hashlib.sha256(source.read_bytes()).hexdigest()
    identity = dict(files=files, platform=[platform.system(), platform.release(), platform.version()],
                    machine=platform.machine(),
                    environment={name: os.environ.get(name) for name in environment},
                    tools=[dict(path=shutil.which(command[0]),
                                version=subprocess.check_output(command, text=True, stderr=subprocess.STDOUT))
                           for command in commands])
    signature = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    with operation(destination):
        stamp = destination/'native-environment.json'
        try:
            old = json.loads(stamp.read_text())
            hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}
            reusable = old['identity'] == signature and old['outputs'] == hashes
        except (OSError, ValueError, KeyError):
            reusable = False # Missing or changed output must rebuild before any consumer can link it.
        transaction = nullcontext() if reusable else replacement(destination)
        with transaction:
            yield reusable
            hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}
            manifest = dict(identity=signature, outputs=hashes)
            stamp.write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['clean'])
    parser.parse_args()
    clean()
