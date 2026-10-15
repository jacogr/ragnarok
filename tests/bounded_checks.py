"""Independent bounded-container reference cases and native native correctness checks (stdlib only)."""
from test_support import codec_commands
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]


# Represent empty payloads/element lists explicitly in the adapter's whitespace-delimited protocol.
def token(text):
    return text or '-'


# Parse a count using the already independent natural oracle, then prove policy and complete payload size.
def frame(data, width, limit, reference_decode):
    prefix = reference_decode(data)
    # Natural wire errors must remain visible rather than being reinterpreted as a count.
    if prefix in ('truncated', 'noncanonical'):
        return prefix
    count, offset = map(int, prefix.split())
    # Limits apply before output capacity, host conversion or count-dependent work.
    if count > limit:
        return 'limitexceeded'
    # Python's arbitrary-width arithmetic provides a reference independent of the native division proof.
    if count * width > len(data) - offset:
        return 'truncated'
    return count, offset, offset + count * width


# Exercise byte strings and fixed-unsigned sequences using references and official unmodified blob spans.
def verify_bounded(build, nim_flags, run, reference_encode, reference_decode):
    run(['nim', 'check', '--mm:arc', ROOT / 'src/bounded.nim'])
    run(['nim', 'c', *nim_flags, f'--out:{build / "nim-bounded-tests"}', '-r',
         ROOT / 'tests/native/test_bounded.nim'])
    # New limit/value distinctions must fail for both compilers, in addition to existing primitive checks.
    for name in ('raw_byte_limit', 'wrong_limit_domain', 'raw_sequence_values'):
        commands = [['nim', 'check', '--mm:arc', ROOT / f'tests/native/compile_fail/{name}.nim']]
        for command in commands:
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            assert result.returncode != 0, command
            assert 'type mismatch' in result.stderr or 'Cannot assign value' in result.stderr, result.stderr
            assert any(name in result.stderr for name in
                       ('ByteLimit', 'Byte_Limit', 'FixedUnsigned', 'Fixed_Unsigned')), result.stderr
    nim_driver = build / 'nim-bounded-driver'
    run(['nim', 'c', *nim_flags, f'--out:{nim_driver}', ROOT / 'tests/native/bounded_driver.nim'])
    requests, expected = [], []

    # Append byte-encoder cases and compare policy/capacity precedence before constructing expected bytes.
    def be(data, limit, capacity):
        requests.append(f'BE {limit} {capacity} {token(data.hex())}')
        prefix = reference_encode(len(data))
        # A policy breach takes precedence over output capacity.
        if len(data) > limit:
            expected.append('limitexceeded')
        elif len(prefix) + len(data) > capacity:
            # No bytes may be committed to a destination that cannot hold the entire frame.
            expected.append('outputtoosmall')
        else:
            # Count prefix and raw octets form the full canonical variable blob.
            expected.append((prefix + data).hex())

    # Append byte-decoder cases; return only the payload token and exact consumed frame length on success.
    def bd(data, limit):
        requests.append(f'BD {limit} {token(data.hex())}')
        proof = frame(data, 1, limit, reference_decode)
        # Prefix, resource and payload errors have no usable returned span.
        if isinstance(proof, str):
            expected.append(proof)
        else:
            # The byte result excludes length-prefix octets and any trailing field.
            count, offset, consumed = proof
            expected.append(f'{token(data[offset:consumed].hex())} {consumed}')

    # Append fixed-sequence encoder cases; width/count/storage checks precede preflighting element values.
    def se(values, width, limit, capacity):
        requests.append(f'SE {width} {limit} {capacity} {token(",".join(map(str, values)))}')
        prefix = reference_encode(len(values))
        # Invalid widths reject even an empty sequence before any other work.
        if width < 0 or width > 8:
            expected.append('invalidwidth')
        elif len(values) > limit:
            # Zero-width elements still count against policy.
            expected.append('limitexceeded')
        elif len(prefix) + len(values) * width > capacity:
            # Complete output capacity is required before committing any prefix or element.
            expected.append('outputtoosmall')
        elif any(value >= 2**(8 * width) for value in values):
            # A late overflowing value must reject the entire operation.
            expected.append('valueoutofrange')
        else:
            expected.append((prefix + b''.join(value.to_bytes(width, 'little') for value in values)).hex())

    # Append fixed-sequence decoder cases, guarding capacity before constructing a Python result list too.
    def sd(data, width, limit, capacity):
        requests.append(f'SD {width} {limit} {capacity} {token(data.hex())}')
        # Width validation precedes all wire interpretation.
        if width < 0 or width > 8:
            expected.append('invalidwidth')
            return
        proof = frame(data, width, limit, reference_decode)
        # Wire and policy failures take priority over output capacity.
        if isinstance(proof, str):
            expected.append(proof)
            return
        count, offset, consumed = proof
        # Never allocate count-dependent reference results until caller-owned capacity proves the count small.
        if count > capacity:
            expected.append('outputtoosmall')
            return
        values = [int.from_bytes(data[offset + i * width:offset + (i + 1) * width], 'little')
                  for i in range(count)]
        expected.append(f'{token(",".join(map(str, values)))} {consumed}')

    # Official preimage blob spans include both the exact natural length and the complete raw payload.
    for chain in ('tiny', 'full'):
        folder = ROOT / 'vendor/jamtestvectors/codec' / chain
        items = json.loads((folder / 'preimages_extrinsic.json').read_text())
        wire = (folder / 'preimages_extrinsic.bin').read_bytes()
        offset = len(reference_encode(len(items)))
        # Verify surrounding service indices and every blob byte before claiming an official case.
        for item in items:
            assert wire[offset:offset + 4] == item['requester'].to_bytes(4, 'little')
            offset += 4
            payload = bytes.fromhex(item['blob'][2:])
            size = len(reference_encode(len(payload))) + len(payload)
            blob_wire = wire[offset:offset + size]
            assert blob_wire == reference_encode(len(payload)) + payload
            be(payload, len(payload), size)
            bd(blob_wire, len(payload))
            offset += size
        assert offset == len(wire)
    official_count = len(requests)
    fixtures = json.loads((ROOT / 'vectors/bounded-containers.json').read_text())
    # Stored project fixtures make representative empty/multi-octet/zero-width containers easy to inspect.
    for item in fixtures:
        wire = bytes.fromhex(item['hex'])
        # Blob and scalar-sequence fixtures have distinct schemas and native APIs.
        if item['kind'] == 'bytes':
            payload = bytes.fromhex(item['payload'])
            assert wire == reference_encode(len(payload)) + payload
            be(payload, len(payload), len(wire))
            bd(wire, len(payload))
        else:
            # Numeric strings preserve all 64 value bits in these JSON fixtures.
            values = list(map(int, item['values']))
            width = item['width']
            assert wire == reference_encode(len(values)) + b''.join(v.to_bytes(width, 'little') for v in values)
            se(values, width, len(values), len(wire))
            sd(wire, width, len(values), len(values))
    rng = random.Random(0x424f554e44)
    # Length-prefix transitions need actual payloads; sample cuts avoid quadratic-sized shared files.
    for size in (0, 1, 127, 128, 255, 256, 16383, 16384):
        data = bytes(i % 256 for i in range(size))
        wire = reference_encode(size) + data
        be(data, size, len(wire))
        be(data, size, len(wire) - 1)
        bd(wire + b'\x42', size)
        bd(wire, max(0, size - 1))
        # Prefix truncations and the final missing payload byte are distinct boundary failures.
        for cut in {0, 1, len(reference_encode(size)) - 1, len(wire) - 1}:
            bd(wire[:cut], size)
    # Random complete byte strings cover successful spans and policy/capacity errors together.
    for _ in range(500):
        data = rng.randbytes(rng.randrange(257))
        wire = reference_encode(len(data)) + data
        be(data, len(data), len(wire))
        be(data, len(data), len(wire) - 1)
        bd(wire, len(data))
        bd(wire + rng.randbytes(3), max(0, len(data) - 1))
    # All strides, including zero, combine valid sequences, storage limits and late range failures.
    for width in range(9):
        for count in (0, 1, 127, 128):
            values = [rng.getrandbits(8 * width) for _ in range(count)]
            wire = reference_encode(count) + b''.join(v.to_bytes(width, 'little') for v in values)
            se(values, width, count, len(wire))
            se(values, width, count, len(wire) - 1)
            sd(wire + b'\x42', width, count, count)
            sd(wire, width, max(0, count - 1), count)
            sd(wire, width, count, max(0, count - 1))
            # Every incomplete element/container prefix must fail before modifying caller-owned values.
            for cut in range(len(wire)):
                sd(wire[:cut], width, count, count)
            # Values in narrower domains can have a representable late element that does not fit.
            if width < 8:
                se([0, 2**(8 * width)], width, 2, 32)
    # Arbitrary input headers cross all 256 tags, truncation boundaries and caller policies.
    hostile = [b'', b'\x80\x00', b'\xc0\x00\x00', reference_encode(2**64 - 1), reference_encode(2**63)]
    for header in range(256):
        for size in range(10):
            hostile.append((bytes([header]) + b'\xff' * 8)[:size])
    hostile.extend(rng.randbytes(rng.randrange(65)) for _ in range(5000))
    # Exercise both decoders on every malformed/random wire sequence; some also decode successfully.
    for wire in hostile:
        limit = rng.choice([0, 1, 8, 128, 2**64 - 1])
        bd(wire, limit)
        sd(wire, rng.randrange(-2, 11), limit, rng.randrange(9))
    # Huge canonical counts must fail safely without host casts, overflowing products or claimed-size allocation.
    for count in (2**63, 2**64 - 1):
        wire = reference_encode(count)
        bd(wire, 2**64 - 1)
        sd(wire, 8, 2**64 - 1, 8)
        sd(wire, 0, 2**64 - 1, 8)
        sd(wire, 0, 8, 8)
    # Signed width extremes are checked before even an empty wire header is interpreted.
    for width in (-2**63, -1, 9, 2**63 - 1):
        se([], width, 0, 0)
        sd(b'', width, 0, 0)
    request_file = build / 'bounded-requests.txt'
    request_file.write_text('\n'.join(requests) + '\n')
    # Each adapter also asserts that every failing write/decode preserves the entire supplied destination.
    for driver in codec_commands(build, (nim_driver,), 'bounded'):
        output = run([*driver, request_file], capture_output=True).stdout.splitlines()
        assert len(output) == len(expected), (driver, len(output), len(expected))
        # Preserve the failing request in the assertion so any semantic mismatch can be replayed exactly.
        for index, (actual, wanted) in enumerate(zip(output, expected)):
            assert actual == wanted, (driver, index, requests[index], actual, wanted)
    print(f'PASS bounded: {len(requests)} independent Nim requests; '
          f'{official_count} official blob checks; {len(fixtures)} project fixtures; '
          '3 negative compilation checks', flush=True)
