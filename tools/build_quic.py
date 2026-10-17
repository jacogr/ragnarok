"""Build the pinned quic ABI for production and verification with identical source checks."""
import json
import platform
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


# Compile the same transport/TLS source revisions for both peers; use no global package installs or fetched executables.
def build_native(paths):
    BUILD.mkdir(parents=True, exist_ok=True)
    bssl = paths['boringssl']
    system = platform.system()
    assert system in ('Darwin', 'Linux'), system
    library = BUILD / ('libquic_proof.dylib' if system == 'Darwin' else 'libquic_proof.so')
    native = ROOT / 'native/quic'
    # The exact native configure/build output is retained instead of hidden behind a success claim.
    with (BUILD / 'build.log').open('w') as log:
        run(['cmake', '-S', bssl, '-B', ROOT / 'build/native/boringssl', '-DCMAKE_BUILD_TYPE=Release',
             '-DBUILD_TESTING=OFF', '-DOPENSSL_NO_ASM=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'], log)
        run(['cmake', '--build', ROOT / 'build/native/boringssl', '--target', 'ssl', 'crypto', '-j', '4'], log)
        run(['cmake', '-S', paths['lsquic'], '-B', ROOT / 'build/native/lsquic', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DCMAKE_BUILD_TYPE=Release', '-DLSQUIC_BIN=OFF', '-DLSQUIC_TESTS=OFF', '-DLSQUIC_SHARED_LIB=OFF',
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

