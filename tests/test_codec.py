#!/usr/bin/env python3
"""Verify Nim against pinned fixtures and independent references. Python stdlib only."""
from test_support import codec_commands
import argparse
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
import struct
from bounded_checks import verify_bounded
from composite_checks import verify_composite
from digest_checks import verify_digest
import tempfile
from dependencies import codec_sources

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
    if reference_encode(x) != data[:length + 1]:
        return 'noncanonical'
    return f'{x} {length + 1}'


# Build primitive checks from pinned official JSON/binary pairs, validating their offsets and integrity.
def official_prefix_cases():
    """Only the natural length prefixes; no claim of full structure conformance."""
    requests, expected = [], []
    pins = json.loads((ROOT / 'spec/pins.json').read_text())
    # Check every upstream fixture against the recorded hash before trusting it as test evidence.
    for path, digest in pins['vectors']['files'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    # Exercise both official chain parameter sets, even where their fixture contents happen to agree.
    for chain in ('tiny', 'full'):
        folder = ROOT / 'vendor/jamtestvectors/codec' / chain
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


def reference_fixed_encode(value, width):
    # Unsupported widths must be rejected before trying any conversion or range calculation.
    if width < 0 or width > 8:
        return 'invalidwidth'
    # The exclusive upper bound also makes zero the only permitted zero-width value.
    if value >= 2**(8 * width):
        return 'outofrange'
    return value.to_bytes(width, 'little').hex()


# Interpret exactly the requested prefix; every full-width byte pattern has a valid unsigned value.
def reference_fixed_decode(data, width):
    # Width errors take priority over an empty or otherwise short buffer.
    if width < 0 or width > 8:
        return 'invalidwidth'
    # Short input must not be partially read or accepted as an implicitly padded value.
    if len(data) < width:
        return 'truncated'
    return f'{int.from_bytes(data[:width], "little")} {width}'


# Locate official fixed-width fields directly in the already pinned ticket/preimage fixtures.
def official_fixed_cases():
    requests, expected = [], []
    # Both chains provide independent fixture provenance even where these primitive fields coincide.
    for chain in ('tiny', 'full'):
        folder = ROOT / 'vendor/jamtestvectors/codec' / chain
        # A ticket attempt is one byte; a preimage requester/service index is four bytes (GP C.2).
        for name, field, width in [('tickets_extrinsic', 'attempt', 1),
                                   ('preimages_extrinsic', 'requester', 4)]:
            items = json.loads((folder / f'{name}.json').read_text())
            data = (folder / f'{name}.bin').read_bytes()
            offset = len(reference_encode(len(items)))
            # Walk the fixed field and use the remaining known JSON sizes to locate the next item.
            for item in items:
                value = item[field]
                encoded = data[offset:offset + width]
                assert encoded == value.to_bytes(width, 'little')
                requests.extend([f'FE {width} {value}', f'FD {width} {encoded.hex()}'])
                expected.extend([encoded.hex(), f'{value} {width}'])
                offset += width
                # Ticket signatures have a fixed length; preimage blobs include a natural length prefix.
                if name == 'tickets_extrinsic':
                    payload = bytes.fromhex(item['signature'][2:])
                else:
                    # Check the blob-length prefix without implementing a native sequence decoder.
                    payload = bytes.fromhex(item['blob'][2:])
                    length = reference_encode(len(payload))
                    assert data[offset:offset + len(length)] == length
                    offset += len(length)
                assert data[offset:offset + len(payload)] == payload
                offset += len(payload)
            assert offset == len(data)
    return requests, expected


# Build the fixed-width adapters and compare valid, malformed and overflowing cases against the independent reference.
def verify_fixed(build, nim_flags):
    run(['nim', 'check', '--mm:arc', ROOT / 'src/codec/fixed_unsigned.nim'])
    run(['nim', 'c', *nim_flags, f'--out:{build / "nim-fixed-tests"}', '-r',
         ROOT / 'tests/native/test_fixed_unsigned.nim'])
    # Domain distinctions must reject raw values, raw widths and general naturals in Nim.
    for name in ('fixed_raw_value', 'fixed_raw_width', 'natural_as_fixed'):
        commands = [['nim', 'check', '--mm:arc', ROOT / f'tests/native/compile_fail/{name}.nim']]
        # Require an encoder type-mismatch diagnostic rather than accepting any unrelated compiler failure.
        for command in commands:
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            assert result.returncode != 0, command
            assert 'encodeFixed' in result.stderr or 'encode_fixed' in result.stderr, result.stderr
    nim_driver = build / 'nim-fixed-driver'
    run(['nim', 'c', *nim_flags, f'--out:{nim_driver}', ROOT / 'tests/native/fixed_driver.nim'])
    requests, expected = official_fixed_cases()
    official_count = len(requests)
    fixtures = json.loads((ROOT / 'vectors/fixed-unsigned-boundaries.json').read_text())
    # Saved endian and width boundaries must match the independent reference before native checks.
    for item in fixtures:
        width, value, encoded = item['width'], int(item['value']), item['hex']
        assert reference_fixed_encode(value, width) == encoded
        requests.extend([f'FE {width} {value}', f'FD {width} {encoded}'])
        expected.extend([encoded, f'{value} {width}'])
    rng = random.Random(0x4649584544)
    # Test all supported widths, including non-machine widths and zero's empty representation.
    for width in range(9):
        values = [0, 2**(8 * width) - 1] + [rng.getrandbits(8 * width) for _ in range(1000)]
        # Every value has a round-trip, a trailing-byte check, and all its incomplete prefixes checked.
        for value in values:
            encoded = value.to_bytes(width, 'little')
            requests.extend([f'FE {width} {value}', f'FD {width} {encoded.hex()}',
                             f'FD {width} {(encoded + b"\x42").hex()}'])
            expected.extend([encoded.hex(), f'{value} {width}', f'{value} {width}'])
            # Any prefix missing even the highest byte must fail, irrespective of that byte's value.
            for length in range(width):
                requests.append(f'FD {width} {encoded[:length].hex()}')
                expected.append('truncated')
        # All bits above a requested width must trigger an encode error instead of being masked away.
        for value in [2**(8 * width), 2**64 - 1]:
            # The eight-byte upper bound exceeds the native value domain, so it is an adapter error.
            if value >= 2**64:
                wanted = 'inputerror'
            else:
                wanted = reference_fixed_encode(value, width)
            requests.append(f'FE {width} {value}')
            expected.append(wanted)
    # Fuzz lengths and widths together; invalid widths must take precedence over missing bytes.
    for _ in range(10000):
        data = rng.randbytes(rng.randrange(33))
        width = rng.randrange(-3, 13)
        requests.append(f'FD {width} {data.hex()}')
        expected.append(reference_fixed_decode(data, width))
    # Host-int extremes exercise width validation without allowing oversized shifts or narrowing casts.
    host_max = (1 << (8 * struct.calcsize('P') - 1)) - 1
    for width in (-host_max - 1, -1, 9, host_max):
        requests.extend([f'FE {width} 0', f'FD {width} ', f'FD {width} ffffffffffffffff'])
        expected.extend(['invalidwidth'] * 3)
    # Malformed or out-of-domain textual numbers are adapter errors before the native codec is called.
    requests.extend(['FE 1 -1', 'FE 8 18446744073709551616',
                     'FE 999999999999999999999999 0', 'FD -999999999999999999999999 '])
    expected.extend(['inputerror'] * 4)
    request_file = build / 'fixed-requests.txt'
    request_file.write_text('\n'.join(requests) + '\n')
    # Each native implementation must match the same independent results, including empty output lines.
    for driver in codec_commands(build, (nim_driver,), 'fixed'):
        output = run([*driver, request_file], capture_output=True).stdout.splitlines()
        assert len(output) == len(expected), (driver, len(output), len(expected))
        # Keep the exact failing request and observed/expected response in the diagnostic.
        for index, (actual, wanted) in enumerate(zip(output, expected)):
            assert actual == wanted, (driver, index, requests[index], actual, wanted)
    print(f'PASS fixed unsigned: {len(requests)} independent Nim requests; '
          f'{official_count} official field checks; {len(fixtures)} boundary fixtures; '
          '3 negative compilation checks', flush=True)


# Build and check Nim, then compare the same request corpus with the reference results.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    args = parser.parse_args()
    codec_sources()
    nim_version = run(['nim', '--version'], capture_output=True).stdout
    assert 'Version 2.2.12 ' in nim_version, nim_version
    # Keep all binaries and generated inputs in temporary storage that is cleaned up even on failure.
    with tempfile.TemporaryDirectory(prefix='ragnarok-codec-') as temporary:
        build = Path(temporary)
        nim_flags = ['--mm:arc', f'--nimcache:{build / "nimcache"}']
        run(['nim', 'check', '--mm:arc', ROOT / 'src/codec/natural.nim'])
        run(['nim', 'c', *nim_flags, f'--out:{build / "nim-tests"}', '-r', ROOT / 'tests/native/test_natural.nim'])
        # Result misuse is rejected even when a caller omits its success check; verify debug and release field guards.
        for mode in ([], ['-d:release']):
            run(['nim', 'c', *nim_flags, *mode, f'--out:{build / "nim-result-tests"}', '-r', ROOT / 'tests/native/test_result_safety.nim'])
        # Ownership regressions run in both caller build modes; ARC must retain isolated snapshots.
        for mode in ([], ['-d:release']):
            run(['nim', 'c', *nim_flags, *mode, f'--out:{build / "nim-ownership-tests"}', '-r', ROOT / 'tests/native/test_ownership.nim'])
        # Neither API exposes mutable snapshot storage or accepts an unrelated source pool.
        for language, fixture, needle in (('nim', 'mutable_owner.nim', 'data'), ('nim', 'wrong_owner_pool.nim', 'copyOwnedBlob')):
            command = [language, 'check', *['--mm:arc'], str(ROOT / 'tests/native/compile_fail' / fixture), *[]]
            result = subprocess.run(command, capture_output=True, text=True)
            assert result.returncode != 0 and needle in result.stderr, result.stderr
        # These public result APIs must reject payload construction/access from a failure or an unselected union.
        for language, fixture, flags in (('nim', 'failed_digest_payload.nim', ['check', '--mm:arc']),):
            result = subprocess.run([language, *flags, str(ROOT / 'tests/native/compile_fail' / fixture), *[]], capture_output=True, text=True)
            assert result.returncode != 0 and 'value' in result.stderr, result.stderr
        negatives = [['nim', 'check', '--mm:arc', ROOT / 'tests/native/compile_fail/raw_integer.nim']]
        # These programs must fail for the intended type mismatch; unexpected compilation success is a failure.
        for command in negatives:
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            assert result.returncode != 0, f'Expected type rejection: {command}'
            assert 'encode' in result.stderr and ('uint64' in result.stderr or 'u64' in result.stderr), result.stderr
        print('Raw-integer nominal safeguard passed', flush=True)
        nim_driver = build / 'nim-driver'
        run(['nim', 'c', *nim_flags, f'--out:{nim_driver}', ROOT / 'tests/native/driver.nim'])
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
        # Run each native adapter on the exact same request file and require one response per request.
        for driver in codec_commands(build, (nim_driver,), 'natural'):
            output = run([*driver, request_file], capture_output=True).stdout.splitlines()
            assert len(output) == len(expected), (driver, len(output), len(expected))
            # Compare each response with its expected value/error and retain the failing request in the diagnostic.
            for index, (actual, wanted) in enumerate(zip(output, expected)):
                assert actual == wanted, (driver, index, requests[index], actual, wanted)
        verify_fixed(build, nim_flags)
        verify_bounded(build, nim_flags, run, reference_encode, reference_decode)
        verify_composite(build, nim_flags, run, reference_encode, reference_decode)
        verify_digest(build, nim_flags, run, reference_encode, reference_decode)
        print(f'PASS: {len(requests)} independent Nim requests; '
              f'{official_count} official prefix checks; {len(fixtures)} boundary fixtures; '
              'native tests and negative compilation checks', flush=True)


# Execute the suite only when this file is launched, allowing helper functions to be imported safely.
if __name__ == '__main__':
    main()
