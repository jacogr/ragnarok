#!/usr/bin/env python3
"""Build native implementations and cross-check pinned fixtures. Python stdlib only."""
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


# Run a command visibly and stop the suite if it fails, so reported results reflect executed checks.
def run(args, **kwargs):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, text=True, **kwargs)


# Compute expected bytes from the mathematical definition independently of either native encoder.
def reference_encode(x):
    """Direct evaluation of GP C.1.1's piecewise mathematical definition."""
    assert 0 <= x < 2**64
    # Handle the definition's explicit zero case before selecting an encoded-size interval.
    if x == 0:
        return b'\x00'
    # Search the eight compact-size intervals; larger values use the full eight-byte payload below.
    for length in range(8):
        # Use this interval's prefix and remainder formula to construct the canonical bytes.
        if 2**(7 * length) <= x < 2**(7 * (length + 1)):
            head = 256 - 2**(8 - length) + x // 2**(8 * length)
            return bytes([head]) + (x % 2**(8 * length)).to_bytes(length, 'little')
    return b'\xff' + x.to_bytes(8, 'little')


# Interpret a prefix with interval arithmetic and check it belongs to the canonical encoder's image.
def reference_decode(data):
    # An empty input cannot provide the required first byte.
    if not data:
        return 'truncated'
    # Prefix intervals instead of the native decoders' bit-count loops.
    length = next((n for n in range(8) if data[0] < 256 - 2**(7 - n)), 8)
    # Avoid reading an incomplete payload after the header announces its length.
    if len(data) < length + 1:
        return 'truncated'
    head = 0 if length == 8 else data[0] - (256 - 2**(8 - length))
    x = head * 256**length + int.from_bytes(data[1:length + 1], 'little')
    # A different re-encoding means the supplied prefix was overlong and must be rejected.
    if reference_encode(x) != data[:length + 1]:
        return 'noncanonical'
    return f'{x} {length + 1}'


# Build primitive checks from pinned official JSON/binary pairs, validating their offsets and integrity.
def official_prefix_cases():
    """Only the natural length prefixes; no claim of full structure conformance."""
    requests, expected = [], []
    pins = json.loads((ROOT / 'spec/pins.json').read_text())
    # Check every copied fixture against the recorded hash before trusting it as test evidence.
    for path, digest in pins['vectors']['files'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    # Exercise both official chain parameter sets, even where their fixture contents happen to agree.
    for chain in ('tiny', 'full'):
        folder = ROOT / 'vectors/official/codec' / chain
        # Locate each structure's outer sequence-length prefix from its matching JSON entry count.
        for name in ('tickets_extrinsic', 'preimages_extrinsic'):
            items = json.loads((folder / f'{name}.json').read_text())
            data = (folder / f'{name}.bin').read_bytes()
            prefix = reference_encode(len(items))
            assert data.startswith(prefix)
            requests.extend([f'E {len(items)}', 'D ' + data[:len(prefix)].hex()])
            expected.extend([prefix.hex(), f'{len(items)} {len(prefix)}'])
            offset = len(prefix)
            # Preimages also contain variable blobs, so verify and test their nested length prefixes.
            if name == 'preimages_extrinsic':
                # Walk requester, length and blob fields in order to prove each prefix offset is correct.
                for item in items:
                    # GP C.2 preimages: E_4(service index), E(length), blob.
                    assert data[offset:offset + 4] == item['requester'].to_bytes(4, 'little')
                    offset += 4
                    blob = bytes.fromhex(item['blob'][2:])
                    prefix = reference_encode(len(blob))
                    assert data[offset:offset + len(prefix)] == prefix
                    requests.extend([f'E {len(blob)}', 'D ' + prefix.hex()])
                    expected.extend([prefix.hex(), f'{len(blob)} {len(prefix)}'])
                    offset += len(prefix)
                    assert data[offset:offset + len(blob)] == blob
                    offset += len(blob)
                assert offset == len(data)
    return requests, expected


# Build and check both languages, then compare the same request corpus with the reference results.
def main():
    nim_version = run(['nim', '--version'], capture_output=True).stdout
    odin_version = run(['odin', 'version'], capture_output=True).stdout
    assert 'Version 2.2.12 ' in nim_version, nim_version
    assert 'dev-2026-10:84bc3fc21' in odin_version, odin_version
    linker = []
    # On macOS, select the active Xcode SDK explicitly; other hosts use their system linker.
    if platform.system() == 'Darwin':
        sdk = run(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], capture_output=True).stdout.strip()
        linker = [f'-extra-linker-flags:-isysroot {sdk}']
    # Keep all binaries and generated inputs in temporary storage that is cleaned up even on failure.
    with tempfile.TemporaryDirectory(prefix='ragnarok-codec-') as temporary:
        build = Path(temporary)
        nim_flags = ['--mm:arc', f'--nimcache:{build / "nimcache"}']
        run(['nim', 'check', '--mm:arc', ROOT / 'nim/src/natural.nim'])
        run(['nim', 'c', *nim_flags, f'--out:{build / "nim-tests"}', '-r', ROOT / 'nim/tests/test_natural.nim'])
        run(['odin', 'check', ROOT / 'odin/codec', '-no-entry-point', '-vet', '-strict-style'])
        run(['odin', 'test', ROOT / 'odin/tests', f'-out:{build / "odin-tests"}', *linker])
        negatives = [
            ['nim', 'check', '--mm:arc', ROOT / 'nim/tests/compile_fail/raw_integer.nim'],
            ['odin', 'check', ROOT / 'odin/tests/compile_fail/raw_integer.odin', '-file'],
        ]
        # These programs must fail for the intended type mismatch; unexpected compilation success is a failure.
        for command in negatives:
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            assert result.returncode != 0, f'Expected type rejection: {command}'
            assert 'encode' in result.stderr and ('uint64' in result.stderr or 'u64' in result.stderr), result.stderr
        print('Both raw-integer negative compilation checks passed', flush=True)
        nim_driver, odin_driver = build / 'nim-driver', build / 'odin-driver'
        run(['nim', 'c', *nim_flags, f'--out:{nim_driver}', ROOT / 'nim/tests/driver.nim'])
        run(['odin', 'build', ROOT / 'odin/driver', f'-out:{odin_driver}', *linker])
        requests, expected = official_prefix_cases()
        official_count = len(requests)
        fixtures = json.loads((ROOT / 'vectors/natural-boundaries.json').read_text())
        # Check the saved size-boundary fixtures in both directions and verify their expected bytes independently.
        for item in fixtures:
            x, encoded = int(item['value']), item['hex']
            assert reference_encode(x).hex() == encoded
            requests.extend([f'E {x}', 'D ' + encoded])
            expected.extend([encoded, f'{x} {len(encoded) // 2}'])
        rng = random.Random(0x4a414d)
        values = [0, 2**64 - 1] + [rng.getrandbits(64) for _ in range(10000)]
        # For every natural, test encoding, decoding, and decoding with an unrelated trailing byte.
        for x in values:
            encoded = reference_encode(x)
            requests.extend([f'E {x}', 'D ' + encoded.hex(), 'D ' + (encoded + b'\x42').hex()])
            expected.extend([encoded.hex(), f'{x} {len(encoded)}', f'{x} {len(encoded)}'])
        inputs = [b'']
        # Every header, every proper prefix, zero payloads and maximum payloads.
        # Cover every possible first byte, including all payload sizes and the ff marker.
        for header in range(256):
            # Zero and all-one payloads probe the low and high extremes for each header.
            for payload in (b'\0' * 8, b'\xff' * 8):
                data = bytes([header]) + payload
                inputs.extend(data[:length] for length in range(10))
        # Deliberately encode values just below each size threshold using that unnecessarily long form.
        for length in range(1, 9):
            # Largest value below each encoding threshold, represented overlong.
            x = 2**(7 * length) - 1
            header = 255 if length == 8 else 256 - 2**(8 - length) + x // 256**length
            inputs.append(bytes([header]) + (x % 256**length).to_bytes(length, 'little'))
        inputs.extend(rng.randbytes(rng.randrange(33)) for _ in range(10000))
        # Feed every arbitrary or malformed byte sequence to both decoders and the independent reference.
        for data in inputs:
            requests.append('D ' + data.hex())
            expected.append(reference_decode(data))
        # uint64 overflow must be rejected by the adapter, never truncated.
        requests.extend(['E 18446744073709551616', 'E -1'])
        expected.extend(['inputerror', 'inputerror'])
        request_file = build / 'requests.txt'
        request_file.write_text('\n'.join(requests) + '\n')
        outputs = []
        # Run each native adapter on the exact same request file and require one response per request.
        for driver in (nim_driver, odin_driver):
            output = run([driver, request_file], capture_output=True).stdout.splitlines()
            assert len(output) == len(expected), (driver, len(output), len(expected))
            # Compare each response with its expected value/error and retain the failing request in the diagnostic.
            for index, (actual, wanted) in enumerate(zip(output, expected)):
                assert actual == wanted, (driver, index, requests[index], actual, wanted)
            outputs.append(output)
        assert outputs[0] == outputs[1]
        print(f'PASS: {len(requests)} shared requests per implementation; '
              f'{official_count} official prefix checks; {len(fixtures)} boundary fixtures; '
              'native tests and negative compilation checks', flush=True)


# Execute the suite only when this file is launched, allowing helper functions to be imported safely.
if __name__ == '__main__':
    main()
