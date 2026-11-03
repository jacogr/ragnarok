# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned quic ABI for production and verification with identical source checks.

Exposes dependencies and build_native for pristine vendor validation, an approved hash-bound
LSQUIC public reset API build copy, and bridge compilation.
"""
import hashlib
import json
import os
import subprocess
import tempfile
import platform
import shutil
from pathlib import Path
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/quic'
PINS = json.loads((ROOT/'spec/quic-proof-pins.json').read_text())


# Resolve pristine pinned submodules and stage only the approved LSQUIC public API addition.
def dependencies(fetch):
    paths = {}
    # Child revisions are checked separately without rewriting the parent dependency's gitlinks.
    for name,entry in PINS['sources'].items():
        path = require_submodule(entry, fetch)
        if '/' not in name:
            paths[name] = path
    patches = PINS['patches']
    if len(patches) != 1 or patches[0]['source'] != 'lsquic' or patches[0]['commit'] != PINS['sources']['lsquic']['commit']:
        raise ValueError('Expected the approved LSQUIC reset patch at its recorded base')
    paths['lsquic'] = stage_lsquic(paths['lsquic'], patches[0])
    return paths


def stage_lsquic(source, entry):
    """Recreate a verified build copy; neither vendor files nor previous failed staging are compiled."""
    names = {'include/lsquic.h', 'src/liblsquic/lsquic_stream.c'}
    patch = ROOT/entry['path']
    if entry['path'] != 'native/quic/patches/lsquic-public-stream-reset.patch':
        raise ValueError('Unexpected QUIC source patch')
    if hashlib.sha256(patch.read_bytes()).hexdigest() != entry['sha256']:
        raise ValueError('QUIC patch digest mismatch')
    if set(entry['before']) != names or set(entry['after']) != names:
        raise ValueError('Unexpected QUIC patch file set')
    # Exact input hashes reject drift before copying or invoking any patch operation.
    for name in sorted(names):
        if hashlib.sha256((source/name).read_bytes()).hexdigest() != entry['before'][name]:
            raise ValueError('QUIC patch input mismatch: '+name)
    native = ROOT/'build/native'
    native.mkdir(parents=True, exist_ok=True)
    target = native/'lsquic-source'
    # Every preparation starts from pristine checked sources, including pinned nested submodules.
    with tempfile.TemporaryDirectory(prefix='lsquic-stage-', dir=native) as temporary:
        staged = Path(temporary)/'source'
        shutil.copytree(source, staged, symlinks=True, ignore=shutil.ignore_patterns('.git'))
        # Prevent Git from discovering the application's ancestor checkout; apply only in this copy.
        environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(staged.parent))
        for arguments in (['--check'], []):
            subprocess.run(['git', 'apply', *arguments, '--whitespace=error-all', str(patch)],
                           cwd=staged, env=environment, check=True, capture_output=True, text=True)
        # No fuzzy application, unexpected output or previously modified cache can enter the build.
        for name in sorted(names):
            if hashlib.sha256((staged/name).read_bytes()).hexdigest() != entry['after'][name]:
                raise ValueError('QUIC patch output mismatch: '+name)
        if target.is_symlink():
            raise ValueError('QUIC build source must not be a symlink')
        if target.exists():
            shutil.rmtree(target)
        staged.rename(target)
    return target


# A compiler switch must start a new CMake configuration; automatic resets lose the same call's options.
def compiler_options(directory):
    """Select absolute Clang drivers and discard only incompatible generated CMake configuration."""
    selected = {}
    for key, binary in (('CMAKE_C_COMPILER', 'clang'), ('CMAKE_CXX_COMPILER', 'clang++')):
        # Missing native prerequisites must fail before touching a previously configured tree.
        found = shutil.which(binary)
        if found is None:
            raise FileNotFoundError('Required native compiler not found: '+binary)
        selected[key] = str(Path(found).absolute())
    cache = directory/'CMakeCache.txt'
    if cache.is_file():
        # CMake records absolute driver paths; compare the exact arguments it will receive.
        recorded = {}
        for line in cache.read_text().splitlines():
            if line.startswith(('CMAKE_C_COMPILER:', 'CMAKE_CXX_COMPILER:')):
                # Retain only compiler identities; all other options remain owned by the configure call.
                name, value = line.split('=', 1)
                recorded[name.split(':', 1)[0]] = value
        if any(key in recorded and recorded[key] != value for key, value in selected.items()):
            # Keep unrelated build output; CMake regenerates these two managed configuration paths.
            cache.unlink()
            configuration = directory/'CMakeFiles'
            if configuration.exists():
                shutil.rmtree(configuration)
    return ['-D'+key+'='+value for key, value in selected.items()]


# Compile the same transport/TLS source revisions for both peers; use no global package installs or fetched executables.
def build_native(paths):
    BUILD.mkdir(parents=True, exist_ok=True)
    bssl = paths['boringssl']
    system = platform.system()
    assert system in ('Darwin', 'Linux'), system
    library = BUILD / ('libquic_proof.dylib' if system == 'Darwin' else 'libquic_proof.so')
    native = ROOT / 'native/quic'
    # Use the same Clang toolchain as the bridges rather than the host default C/C++ compiler.
    # The exact native configure/build output is retained instead of hidden behind a success claim.
    with (BUILD / 'build.log').open('w') as log:
        run(['cmake', '-S', bssl, '-B', ROOT / 'build/native/boringssl', '-DCMAKE_BUILD_TYPE=Release',
             *compiler_options(ROOT/'build/native/boringssl'),
             '-DBUILD_TESTING=OFF', '-DOPENSSL_NO_ASM=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'], log)
        run(['cmake', '--build', ROOT / 'build/native/boringssl', '--target', 'ssl', 'crypto', '-j', '4'], log)
        run(['cmake', '-S', paths['lsquic'], '-B', ROOT / 'build/native/lsquic-reset', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DCMAKE_BUILD_TYPE=Release',
             *compiler_options(ROOT/'build/native/lsquic-reset'),
             '-DLSQUIC_BIN=OFF', '-DLSQUIC_TESTS=OFF', '-DLSQUIC_SHARED_LIB=OFF',
             '-DCMAKE_POSITION_INDEPENDENT_CODE=ON', f'-DBORINGSSL_INCLUDE={bssl / "include"}',
             f'-DBORINGSSL_LIB_ssl={ROOT / "build/native/boringssl/libssl.a"}', f'-DBORINGSSL_LIB_crypto={ROOT / "build/native/boringssl/libcrypto.a"}'], log)
        run(['cmake', '--build', ROOT / 'build/native/lsquic-reset', '-j', '4'], log)
        # The bridge contains transport/TLS field extraction only; identity/framing policy is independently native.
        for name in ('cert_fields', 'transport_bridge'):
            run(['clang', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', f'-I{bssl / "include"}',
                 f'-I{paths["lsquic"] / "include"}', '-c', native / f'{name}.c', '-o', BUILD / f'{name}.o'], log)
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', BUILD / 'cert_fields.o',
             BUILD / 'transport_bridge.o', ROOT / 'build/native/lsquic-reset/src/liblsquic/liblsquic.a',
             ROOT / 'build/native/boringssl/libssl.a', ROOT / 'build/native/boringssl/libcrypto.a', '-lz', '-o', library], log)
    return library

