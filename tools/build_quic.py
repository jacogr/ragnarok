# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned quic ABI for production and verification with identical source checks.

Exposes dependencies and build_native for pristine QUIC/TLS validation, hash-bound LSQUIC
build patches and bridge compilation.
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import tempfile
from pathlib import Path
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/quic'
PINS = json.loads((ROOT/'spec/quic-proof-pins.json').read_text())
PATH_NONCE_PATCH = 'native/quic/patches/lsquic-path-response-nonce.patch'
PATCH_FILES = {
    PATH_NONCE_PATCH: {'src/liblsquic/lsquic_full_conn_ietf.c'},
    'native/quic/patches/lsquic-public-stream-reset.patch': {
        'include/lsquic.h', 'src/liblsquic/lsquic_stream.c',
    },
}



# Resolve pinned native Git submodules, including LSQUIC's own recorded QPACK/HPACK children.
def dependencies(fetch):
    paths = {}
    # Child revisions are checked separately without rewriting the parent dependency's gitlinks.
    for name,entry in PINS['sources'].items():
        path = require_submodule(entry, fetch)
        if '/' not in name:
            paths[name] = path
    paths['lsquic'] = stage_lsquic(paths['lsquic'], PINS['patches'], PINS['sources']['lsquic']['commit'])
    return paths


def verify_hashes(source, expected):
    """Reject source drift and verify the exact contents after each approved patch."""
    for name, digest in sorted(expected.items()):
        if hashlib.sha256((source/name).read_bytes()).hexdigest() != digest:
            raise ValueError('QUIC patch source digest mismatch: '+name)


def stage_lsquic(source, entries, revision):
    """Apply only the named, hash-bound patches to a fresh copy of pristine LSQUIC."""
    names = [entry['path'] for entry in entries]
    if PATH_NONCE_PATCH not in names or len(set(names)) != len(names):
        raise ValueError('Expected one copy of each configured LSQUIC patch, including the nonce fix')
    for entry in entries:
        files = PATCH_FILES.get(entry['path'])
        if (files is None or entry['source'] != 'lsquic' or entry['commit'] != revision
                or set(entry['before']) != files or set(entry['after']) != files):
            raise ValueError('Unexpected LSQUIC patch or base: '+entry['path'])
        if hashlib.sha256((ROOT/entry['path']).read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('QUIC patch digest mismatch: '+entry['path'])
        verify_hashes(source, entry['before'])

    native = ROOT/'build/native'
    native.mkdir(parents=True, exist_ok=True)
    target = native/'lsquic-source'
    # Keep patch application outside the vendor checkout and isolate Git discovery.
    with tempfile.TemporaryDirectory(prefix='lsquic-stage-', dir=native) as temporary:
        staged = Path(temporary)/'source'
        shutil.copytree(source, staged, symlinks=True, ignore=shutil.ignore_patterns('.git'))
        environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(staged.parent))
        for entry in entries:
            for options in (['--check'], []):
                subprocess.run(['git', 'apply', *options, '--whitespace=error-all', str(ROOT/entry['path'])],
                               cwd=staged, env=environment, check=True, capture_output=True, text=True)
            verify_hashes(staged, entry['after'])
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
        run(['cmake', '-S', paths['lsquic'], '-B', ROOT / 'build/native/lsquic-patched', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DCMAKE_BUILD_TYPE=Release',
             *compiler_options(ROOT/'build/native/lsquic-patched'),
             '-DLSQUIC_BIN=OFF', '-DLSQUIC_TESTS=OFF', '-DLSQUIC_SHARED_LIB=OFF',
             '-DCMAKE_POSITION_INDEPENDENT_CODE=ON', f'-DBORINGSSL_INCLUDE={bssl / "include"}',
             f'-DBORINGSSL_LIB_ssl={ROOT / "build/native/boringssl/libssl.a"}', f'-DBORINGSSL_LIB_crypto={ROOT / "build/native/boringssl/libcrypto.a"}'], log)
        run(['cmake', '--build', ROOT / 'build/native/lsquic-patched', '-j', '4'], log)
        # The bridge contains transport/TLS field extraction only; identity/framing policy is independently native.
        for name in ('cert_fields', 'transport_bridge'):
            run(['clang', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', f'-I{bssl / "include"}',
                 f'-I{paths["lsquic"] / "include"}', '-c', native / f'{name}.c', '-o', BUILD / f'{name}.o'], log)
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', BUILD / 'cert_fields.o',
             BUILD / 'transport_bridge.o', ROOT / 'build/native/lsquic-patched/src/liblsquic/liblsquic.a',
             ROOT / 'build/native/boringssl/libssl.a', ROOT / 'build/native/boringssl/libcrypto.a', '-lz', '-o', library], log)
    return library

