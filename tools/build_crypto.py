# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned crypto ABI for production and verification with identical source checks.

Exposes dependencies and build_native for pristine crypto dependency preparation and bridge
compilation.
"""
import hashlib
import json
import platform
import shutil
import tomllib
from build_bandersnatch import sources as rust_sources, build_native as build_rust
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/crypto'
PINS = json.loads((ROOT/'spec/crypto-pins.json').read_text())


# Verify immutable dependency identities; fetch only crypto sources when explicitly requested.
def dependencies(fetch):
    assert PINS['patches'] == [], 'Crypto dependencies must remain unmodified'
    rust = PINS['rust_primitives']
    assert hashlib.sha256((ROOT / rust['lock']).read_bytes()).hexdigest() == rust['lock_sha256']
    manifest = tomllib.loads((ROOT / rust['manifest']).read_text())
    # Informational provider pins must agree with the actual direct Cargo requirements.
    for name in ('blake2', 'sha3', 'ed25519-zebra', 'zeroize'):
        dependency = manifest['dependencies'][name]
        version = dependency if isinstance(dependency, str) else dependency['version']
        assert version == '=' + rust[name], name
    paths = {}
    # BoringSSL is shared with QUIC; Git submodules own exact source revisions.
    for name,entry in PINS['sources'].items():
        paths[name]=require_submodule(entry,fetch)
    entry=PINS['wycheproof']
    require_submodule({'path':entry['submodule_path'],'repository':entry['repository'],'commit':entry['commit']},fetch)
    return paths


# Compile only the maintained primitive ABI; compiler-specific test adapters are built separately.
def build_native(paths):
    system = platform.system()
    assert system in ('Darwin', 'Linux')
    library = BUILD / ('libragnarok_crypto.dylib' if system == 'Darwin' else 'libragnarok_crypto.so')
    bssl = paths['boringssl']
    native = ROOT / 'build/native/boringssl'
    BUILD.mkdir(parents=True, exist_ok=True)
    rust_sources(False)
    backend = build_rust(False)
    # The provider is already needed for VRFs; colocate a byte-identical copy for crypto-only users.
    shutil.copy2(backend, BUILD / backend.name)
    include = [bssl / 'include', ROOT / 'native/crypto']
    # Retain the complete configure/compiler output for Linux CI diagnosis.
    with (BUILD / 'build.log').open('w') as log:
        run(['cmake', '-S', bssl, '-B', native, '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_TESTING=OFF',
             '-DOPENSSL_NO_ASM=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'], log)
        run(['cmake', '--build', native, '--target', 'crypto', '-j', '4'], log)
        obj = BUILD / 'native-0.o'
        run(['clang', '-O2', '-fPIC', '-Wall', '-Wextra', '-Werror',
             *[f'-I{p}' for p in include], '-c', ROOT / 'native/crypto/primitive_bridge.c',
             '-o', obj], log)
        # Resolve the Rust provider beside this bridge, independently of the build-machine path.
        origin = '@loader_path' if system == 'Darwin' else '$ORIGIN'
        identity = ['-Wl,-install_name,@rpath/' + library.name] if system == 'Darwin' else ['-Wl,-soname,' + library.name]
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', obj,
             native / 'libcrypto.a', backend, '-Wl,-rpath,' + origin, *identity,
             '-pthread', '-o', library], log)
    return library

