"""Build the pinned crypto ABI for production and verification with identical source checks."""
import json
import platform
from native_dependencies import ROOT, require_submodule, run

BUILD = ROOT/'build/crypto'
PINS = json.loads((ROOT/'spec/crypto-pins.json').read_text())


# Verify immutable dependency identities; fetch only crypto sources when explicitly requested.
def dependencies(fetch):
    assert PINS['patches'] == [], 'Crypto dependencies must remain unmodified'
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
    bssl, xkcp = paths['boringssl'], paths['xkcp']
    native = ROOT / 'build/native/boringssl'
    config = BUILD / 'config'
    # Fresh production builds may not have run the test harness that creates BUILD.
    config.mkdir(parents=True, exist_ok=True)
    (config / 'config.h').write_text('#define XKCP_has_KeccakP1600 1\n')
    include = [config, bssl / 'include', xkcp / 'lib/common', xkcp / 'lib/high/Keccak',
               xkcp / 'lib/low/KeccakP-1600/plain-64bits', xkcp / 'lib/low/KeccakP-1600/plain-64bits/SnP',
               xkcp / 'lib/low/KeccakP-1600/common', xkcp / 'lib/low/common']
    sources = [ROOT / 'native/crypto/primitive_bridge.c',
               xkcp / 'lib/high/Keccak/KeccakSponge.c',
               xkcp / 'lib/low/KeccakP-1600/plain-64bits/KeccakP-1600-opt64.c']
    # Retain the complete configure/compiler output for Linux CI diagnosis.
    with (BUILD / 'build.log').open('w') as log:
        run(['cmake', '-S', bssl, '-B', native, '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_TESTING=OFF',
             '-DOPENSSL_NO_ASM=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'], log)
        run(['cmake', '--build', native, '--target', 'crypto', '-j', '4'], log)
        objects = []
        # The bridge and upstream sources are compiled individually; no source patches/build hooks run.
        for i, source in enumerate(sources):
            obj = BUILD / f'native-{i}.o'
            run(['clang', '-O2', '-fPIC', '-Wall', '-Wextra', '-Werror',
                 *[f'-I{p}' for p in include], '-c', source, '-o', obj], log)
            objects.append(obj)
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', *objects,
             native / 'libcrypto.a', '-pthread', '-o', library], log)
    return library

