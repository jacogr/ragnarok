#!/usr/bin/env python3
"""Maintained crypto build, independent vector equations and native ABI checks."""
import ctypes
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
from test_quic import run
from dependencies import require_submodule

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/crypto'
PINS = json.loads((ROOT / 'spec/crypto-pins.json').read_text())


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


def test(binary):
    invalid = subprocess.run([str(binary), 'F'], capture_output=True, text=True)
    assert invalid.returncode != 0
    # Require the expected checked-result diagnostic, not an unrelated process failure.
    diagnostic = invalid.stdout + invalid.stderr
    assert 'value.status == None' in diagnostic and '[AssertionDefect]' in diagnostic
    assert query(binary, 'O') == 'ok'
    assert query(binary, 'T') == 'ok'
    fixture = ROOT / 'vectors/official/crypto'
    assert hashlib.sha256((fixture / 'rfc8032.json').read_bytes()).hexdigest() == PINS['rfc8032']['fixture_sha256']
    assert hashlib.sha256((ROOT / PINS['wycheproof']['submodule_path'] / PINS['wycheproof']['path']).read_bytes()).hexdigest() == PINS['wycheproof']['sha256']
    assert hashlib.sha256((ROOT / PINS['wycheproof']['submodule_path'] / 'LICENSE').read_bytes()).hexdigest() == PINS['wycheproof']['license_sha256']
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
    wycheproof = json.loads((ROOT / PINS['wycheproof']['submodule_path'] / PINS['wycheproof']['path']).read_text())
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
    expected_identity = '1'
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
def generated_signatures(binary=None):
    binary = binary or BUILD/'nim-release'
    rng = random.Random(25519)
    # Deterministic public fixture seeds exercise ordinary signing and verification beyond the known answers.
    for i in range(32):
        seed, message = rng.randbytes(32), rng.randbytes(i*17)
        public = bytes.fromhex(query(binary,'P',seed))
        signature = bytes.fromhex(query(binary,'S',seed,message))
        assert query(binary,'V',public,signature,message) == '1'
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
