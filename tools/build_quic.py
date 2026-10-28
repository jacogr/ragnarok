# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned quic ABI for production and verification with identical source checks.

Exposes dependencies and build_native for pristine QUIC/TLS dependency preparation and bridge
compilation.
"""
import json
import platform
import shutil
from pathlib import Path
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/quic'
PINS = json.loads((ROOT/'spec/quic-proof-pins.json').read_text())


# Resolve pinned native Git submodules, including LSQUIC's own recorded QPACK/HPACK children.
def dependencies(fetch):
    assert PINS['patches'] == [], 'QUIC must build without source patches'
    paths = {}
    # Child revisions are checked separately without rewriting the parent dependency's gitlinks.
    for name,entry in PINS['sources'].items():
        path = require_submodule(entry, fetch)
        if '/' not in name:
            paths[name] = path
    return paths


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
        run(['cmake', '-S', paths['lsquic'], '-B', ROOT / 'build/native/lsquic', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DCMAKE_BUILD_TYPE=Release',
             *compiler_options(ROOT/'build/native/lsquic'),
             '-DLSQUIC_BIN=OFF', '-DLSQUIC_TESTS=OFF', '-DLSQUIC_SHARED_LIB=OFF',
             '-DCMAKE_POSITION_INDEPENDENT_CODE=ON', f'-DBORINGSSL_INCLUDE={bssl / "include"}',
             f'-DBORINGSSL_LIB_ssl={ROOT / "build/native/boringssl/libssl.a"}', f'-DBORINGSSL_LIB_crypto={ROOT / "build/native/boringssl/libcrypto.a"}'], log)
        run(['cmake', '--build', ROOT / 'build/native/lsquic', '-j', '4'], log)
        # The bridge contains transport/TLS field extraction only; identity/framing policy is independently native.
        for name in ('cert_fields', 'transport_bridge'):
            run(['clang', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', f'-I{bssl / "include"}',
                 f'-I{paths["lsquic"] / "include"}', '-c', native / f'{name}.c', '-o', BUILD / f'{name}.o'], log)
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', BUILD / 'cert_fields.o',
             BUILD / 'transport_bridge.o', ROOT / 'build/native/lsquic/src/liblsquic/liblsquic.a',
             ROOT / 'build/native/boringssl/libssl.a', ROOT / 'build/native/boringssl/libcrypto.a', '-lz', '-o', library], log)
    return library

