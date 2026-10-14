#!/usr/bin/env python3
"""Reproducible native crypto build, independent vectors, ownership and type-boundary checks."""
import argparse
import concurrent.futures
import ctypes
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
from test_quic import fetch_source, run
from toolchain_checks import odin_matches

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/crypto'
PINS = json.loads((ROOT / 'spec/crypto-pins.json').read_text())


# Verify immutable dependency identities; fetch only crypto sources when explicitly requested.
def dependencies(fetch):
    assert PINS['patches'] == [], 'Crypto dependencies must remain unmodified'
    paths = {}
    # Reuse QUIC's identical BoringSSL revision/build without requiring any transport sources.
    for name, entry in PINS['sources'].items():
        destination = ROOT / 'build/quic/native-sources/boringssl' if name == 'boringssl' else BUILD / 'sources' / name
        marker = destination / '.ragnarok-source.json'
        # Fetch missing pinned source archives, never executable installers.
        if fetch and not marker.exists():
            fetch_source(entry, destination)
        assert marker.exists(), f'Run with --fetch for {name}'
        actual = json.loads(marker.read_text())
        assert actual['repository'] == entry['repository'] and actual['commit'] == entry['commit']
        paths[name] = destination
    return paths


# Compile a narrow ABI from pristine BoringSSL/XKCP sources, then both checked native test adapters.
def build(paths):
    assert PINS['nim'] in subprocess.check_output(['nim', '--version'], text=True)
    assert odin_matches(subprocess.check_output(['odin', 'version'], text=True), PINS['odin'])
    system = platform.system()
    assert system in ('Darwin', 'Linux')
    library = BUILD / ('libragnarok_crypto.dylib' if system == 'Darwin' else 'libragnarok_crypto.so')
    bssl, xkcp = paths['boringssl'], paths['xkcp']
    native = ROOT / 'build/quic/native-bssl'
    config = BUILD / 'config'
    config.mkdir(exist_ok=True)
    (config / 'config.h').write_text('#define XKCP_has_KeccakP1600 1\n')
    include = [config, bssl / 'include', xkcp / 'lib/common', xkcp / 'lib/high/Keccak',
               xkcp / 'lib/low/KeccakP-1600/plain-64bits', xkcp / 'lib/low/KeccakP-1600/plain-64bits/SnP',
               xkcp / 'lib/low/KeccakP-1600/common', xkcp / 'lib/low/common']
    sources = [ROOT / 'interoperability/crypto/primitive_bridge.c',
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
        linker = []
        # macOS's Odin linker needs the selected SDK; Linux uses system headers/libraries.
        if system == 'Darwin':
            sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
            linker = [f'-extra-linker-flags:-isysroot {sdk}']
        # Test checked debug and optimized release builds; do not disable result/union assertions.
        for mode in ('debug', 'release'):
            run(['nim', 'c', '--mm:arc', '--cc:clang', '--clang.linkerexe:clang++', '--skipParentCfg',
                 '--skipUserCfg', *(['-d:release'] if mode == 'release' else []), f'--passL:{library}',
                 f'--nimcache:{BUILD / ("nim-cache-" + mode)}', f'--out:{BUILD / ("nim-" + mode)}',
                 ROOT / 'nim/crypto/driver.nim'], log)
            run(['odin', 'build', ROOT / 'odin/crypto_driver', '-vet', '-strict-style',
                 *(['-o:speed'] if mode == 'release' else []), f'-out:{BUILD / ("odin-" + mode)}', *linker], log)


# Query one native process; all inputs are public deterministic fixtures and argument size is bounded.
def query(binary, command, *values):
    args = [value.hex() or '-' if isinstance(value, bytes) else value for value in values]
    return subprocess.check_output([str(binary), command, *args], text=True, timeout=20).strip()


# Independent test-only integer Keccak-f oracle; never imported by production language implementations.
def keccak256(message):
    mask = (1 << 64) - 1
    rotations = [0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14]
    constants = [0x1,0x8082,0x800000000000808a,0x8000000080008000,0x808b,0x80000001,
                 0x8000000080008081,0x8000000000008009,0x8a,0x88,0x80008009,0x8000000a,
                 0x8000808b,0x800000000000008b,0x8000000000008089,0x8000000000008003,
                 0x8000000000008002,0x8000000000000080,0x800a,0x800000008000000a,
                 0x8000000080008081,0x8000000000008080,0x80000001,0x8000000080008008]
    padded = bytearray(message)
    padded.extend(bytes(136 - len(padded) % 136))
    padded[len(message)] = 1
    padded[-1] |= 128
    state = [0] * 25
    # Absorb complete rate blocks and permute after each, including the final legacy padding block.
    for block in range(0, len(padded), 136):
        # Little endian lanes are independent from the backend's machine representation.
        for lane in range(17):
            state[lane] ^= int.from_bytes(padded[block+lane*8:block+lane*8+8], 'little')
        # Apply the specified theta/rho/pi/chi/iota round equations with arbitrary precision integers.
        for constant in constants:
            parity = [state[x] ^ state[x+5] ^ state[x+10] ^ state[x+15] ^ state[x+20] for x in range(5)]
            delta = [parity[(x-1)%5] ^ ((parity[(x+1)%5]<<1) | (parity[(x+1)%5]>>63)) & mask for x in range(5)]
            mixed = [state[i] ^ delta[i%5] for i in range(25)]
            permuted = [0] * 25
            # Rotate then move lanes to the pi coordinates.
            for i, value in enumerate(mixed):
                x, y = i%5, i//5
                shift = rotations[i]
                permuted[y+5*((2*x+3*y)%5)] = ((value << shift) | (value >> (64-shift))) & mask
            state = [permuted[i] ^ ((~permuted[(i//5)*5+(i+1)%5]) & permuted[(i//5)*5+(i+2)%5]) for i in range(25)]
            state[0] ^= constant
    return b''.join(v.to_bytes(8, 'little') for v in state)[:32].hex()


# Reject implicit mixing of hashes/key roles and access to private retained seed storage at compilation.
def type_checks():
    probes = {'hash': ('var a: Blake2bHash; let b: KeccakHash = a',
                       'a: primitives.Blake2b_Hash; b: primitives.Keccak_Hash = a; _ = b'),
              'key': ('var a: Blake2bHash; let b: EdPublicKey = a',
                      'a: primitives.Blake2b_Hash; b: primitives.Ed_Public_Key = a; _ = b'),
              'seed': ('var a: EdSeed; discard a.storage',
                       'a: primitives.Ed_Seed; _ = a.bytes')}
    # Positive controls establish that generated paths and source syntax reach the actual APIs.
    positive_nim = BUILD / 'positive.nim'
    positive_nim.write_text('import "../../nim/crypto/primitives"\nvar a: Blake2bHash\ndiscard a\n')
    subprocess.run(['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg', str(positive_nim)],
                   check=True, capture_output=True)
    positive_odin = BUILD / 'positive.odin'
    positive_odin.write_text('package main\nimport primitives "../../odin/crypto"\nmain :: proc() {a: primitives.Blake2b_Hash; _ = a}\n')
    subprocess.run(['odin', 'check', str(positive_odin), '-file'], check=True, capture_output=True)
    # Negative diagnostics are retained so failures cannot be confused with missing imports/toolchains.
    with (BUILD / 'type-checks.log').open('wb') as log:
        for name, (nim, odin) in probes.items():
            np = BUILD / f'negative_{name}.nim'
            np.write_text(f'import "../../nim/crypto/primitives"\n{nim}\n')
            result = subprocess.run(['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg', str(np)], capture_output=True)
            log.write(result.stdout + result.stderr)
            assert result.returncode != 0, name
            assert b'invalid module name' not in result.stderr
            op = BUILD / f'negative_{name}.odin'
            op.write_text(f'package main\nimport primitives "../../odin/crypto"\nmain :: proc() {{{odin}}}\n')
            result = subprocess.run(['odin', 'check', str(op), '-file'], capture_output=True)
            log.write(result.stdout + result.stderr)
            assert result.returncode != 0, name
            assert b'Invalid import path' not in result.stderr



# Run independent public vectors, malformed encodings, boundary messages and cross-provider signatures.
def test(binary):
    invalid = subprocess.run([str(binary), 'F'], capture_output=True, text=True)
    assert invalid.returncode != 0
    # Require the expected checked-result diagnostic, not an unrelated process failure.
    diagnostic = invalid.stdout + invalid.stderr
    assert ('FieldDefect' in diagnostic if binary.name.startswith('nim') else 'assert' in diagnostic.lower())
    assert query(binary, 'O') == 'ok'
    assert query(binary, 'T') == 'ok'
    fixture = ROOT / 'vectors/official/crypto'
    assert hashlib.sha256((fixture / 'rfc8032.json').read_bytes()).hexdigest() == PINS['rfc8032']['fixture_sha256']
    assert hashlib.sha256((fixture / 'ed25519-wycheproof.json').read_bytes()).hexdigest() == PINS['wycheproof']['sha256']
    assert hashlib.sha256((fixture / 'LICENSE-wycheproof').read_bytes()).hexdigest() == PINS['wycheproof']['license_sha256']
    vectors = json.loads((fixture / 'rfc8032.json').read_text())
    # Every RFC pure-Ed25519 seed/public/message/signature tuple is tested byte for byte.
    for v in vectors:
        seed, public, message, signature = [bytes.fromhex(v[k]) for k in ('seed','public','message','signature')]
        assert query(binary, 'P', seed) == public.hex()
        assert query(binary, 'S', seed, message) == signature.hex()
        assert query(binary, 'V', public, signature, message) == '1'
        altered = bytes([signature[0]^1]) + signature[1:]
        assert query(binary, 'V', public, altered, message) == '0'
        assert query(binary, 'V', public, signature, message+b'!') == '0'
    verdicts = {}
    wycheproof = json.loads((fixture / 'ed25519-wycheproof.json').read_text())
    # Preserve every corpus label; backend disagreements cannot be silently skipped.
    for group in wycheproof['testGroups']:
        public = bytes.fromhex(group['publicKey']['pk'])
        # Every group shares one public key; each signature/message keeps its own upstream expected label.
        for v in group['tests']:
            actual = query(binary, 'V', public, bytes.fromhex(v['sig']), bytes.fromhex(v['msg']))
            expected = '1' if v['result'] == 'valid' else '0'
            # Wrong widths are rejected at the typed import boundary rather than entering verification.
            if len(v['sig']) != 128:
                assert v['result'] == 'invalid'
                expected = 'error'
            assert actual == expected, (binary.name, v['tcId'], v['comment'], actual, expected)
            verdicts[v['tcId']] = actual
    identity = bytes([1]) + bytes(31)
    zero = bytes(32)
    # Preserve an observed provider policy difference, rather than asserting only ordinary vectors coincide.
    expected_identity = '1' if binary.name.startswith('nim') else '0'
    assert query(binary, 'V', identity, identity+zero, b'') == expected_identity
    assert query(binary, 'V', identity, identity+zero, b'abc') == expected_identity
    assert query(binary, 'V', zero, zero+zero, b'') == '0'
    # S equal to the group order is outside the canonical scalar interval for either provider.
    order = (2**252 + 27742317777372353535851937790883648493).to_bytes(32, 'little')
    assert query(binary, 'V', identity, identity+order, b'') == '0'
    rng = random.Random(8032)
    lengths = [0,1,2,31,32,63,64,65,127,128,129,135,136,137,255,256,271,272,273,1023,4096,16384]
    cases = [b'', b'abc'] + [rng.randbytes(n) for n in lengths] + [rng.randbytes(rng.randrange(2048)) for _ in range(32)]
    # Verify exact digest-length parameter and legacy padding across both algorithms' block boundaries.
    for message in cases:
        assert query(binary, 'B', message) == hashlib.blake2b(message, digest_size=32).hexdigest()
        assert query(binary, 'K', message) == keccak256(message)
    # Invalid import sizes must expose only error, never padding/truncation or a fabricated key.
    for n in (0,1,31,33,63,65):
        assert query(binary, 'P', bytes(n)) == 'error'
        assert query(binary, 'S', bytes(n), b'') == 'error'
        assert query(binary, 'V', bytes(n), bytes(64), b'') == 'error'
    for n in (0,1,32,63,65):
        assert query(binary, 'V', bytes(32), bytes(n), b'') == 'error'
    return {'rfc8032':len(vectors), 'wycheproof':len(verdicts), 'hash_messages':len(cases), 'ownership':'passed', 'native_threads':4, 'rounds_per_thread':128, 'checked_failure':'passed', 'identity_public_key_accepted':expected_identity == '1'}


# Cross-sign independent deterministic fixtures and stress simultaneous calls through separate native processes.
def cross_test():
    nim, odin = BUILD / 'nim-release', BUILD / 'odin-release'
    rng = random.Random(25519)
    # Both providers must produce the same ordinary deterministic signature and accept the other's output.
    for i in range(32):
        seed, message = rng.randbytes(32), rng.randbytes(i*17)
        key = query(nim, 'P', seed)
        assert key == query(odin, 'P', seed)
        signature = query(nim, 'S', seed, message)
        assert signature == query(odin, 'S', seed, message)
        assert query(odin, 'V', bytes.fromhex(key), bytes.fromhex(signature), message) == '1'
        assert query(nim, 'V', bytes.fromhex(key), bytes.fromhex(signature), message) == '1'
    return 32


# Check C pointer/length validation, all-or-nothing writes and the explicit erasure routine directly.
def bridge_checks():
    path = BUILD / ('libragnarok_crypto.dylib' if platform.system() == 'Darwin' else 'libragnarok_crypto.so')
    lib = ctypes.CDLL(str(path))
    output = (ctypes.c_ubyte * 64)(*[0xa5]*64)
    # Missing nonempty input must leave caller output untouched for both hash backends.
    for name in ('rc_blake2b256', 'rc_keccak256'):
        function = getattr(lib, name)
        function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
        function.restype = ctypes.c_int
        assert function(None, 1, output) == 0
        assert bytes(output) == bytes([0xa5])*64
        assert function(None, 0, None) == 0
    lib.rc_ed_public.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.rc_ed_public.restype = ctypes.c_int
    assert lib.rc_ed_public(None, output) == 0
    lib.rc_ed_sign.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
    lib.rc_ed_sign.restype = ctypes.c_int
    assert lib.rc_ed_sign(None, None, 0, output) == 0
    assert bytes(output) == bytes([0xa5])*64
    lib.rc_wipe.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    lib.rc_wipe.restype = None
    lib.rc_wipe(output, 64)
    assert bytes(output) == bytes(64)
    lib.rc_wipe(None, 0)


# Entry point leaves a machine-readable success record only after every test has passed.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / 'results.json').unlink(missing_ok=True)
    build(dependencies(args.fetch))
    assert keccak256(b'') == 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
    assert keccak256(b'abc') == '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45'
    type_checks()
    bridge_checks()
    names = ['nim-debug','odin-debug','nim-release','odin-release']
    # Independent process suites can run concurrently without sharing seed owners or allocators.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        records = dict(zip(names, pool.map(test, [BUILD / name for name in names])))
    summary = {'status':'passed', 'platform':platform.platform(), 'suites':records,
               'cross_signed_messages':cross_test(), 'negative_type_probes':6, 'patches':[],
               'ed25519_policy_difference':'BoringSSL accepts identity A/R with S=0; Odin default rejects it'}
    (BUILD / 'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))


# Importing the runner exposes helpers but never starts a build or performs network access.
if __name__ == '__main__':
    main()
