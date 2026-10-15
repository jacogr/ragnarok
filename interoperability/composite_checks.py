"""Independent optional/work/preimage references and official composite-vector checks."""
from mojo_support import codec_commands
import hashlib
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]


# Empty hex/record lists need an explicit token in the native adapters' trusted textual protocol.
def token(text):
    return text or '-'


# Interpret one canonical natural using the existing independent mathematical oracle.
def count_at(data, offset, decode):
    result = decode(data[offset:])
    if result in ('truncated', 'noncanonical'):
        return result # A nested discriminator error must not be reinterpreted as a record value.
    value, consumed = map(int, result.split())
    return value, offset + consumed


# Validate a bounded nested blob before slicing its payload; counts remain arbitrary precision in this oracle.
def blob_at(data, offset, limit, decode):
    prefix = count_at(data, offset, decode)
    if isinstance(prefix, str):
        return prefix # Missing/overlong counts expose no payload view.
    count, start = prefix
    if count > limit:
        return 'limitexceeded' # Policy precedes available-payload checks.
    if count > len(data) - start:
        return 'truncated' # Missing bytes cannot be implicitly padded.
    return data[start:start + count], start + count


# Run new native checks then compare exact variants and full nested records against independent results.
def verify_composite(build, nim_flags, linker, run, encode, decode):
    run(['nim', 'check', '--mm:arc', ROOT / 'nim/src/composite.nim'])
    run(['nim', 'c', *nim_flags, f'--out:{build / "nim-composite-tests"}', '-r', ROOT / 'nim/tests/test_composite.nim'])
    for name in ('raw_service_index', 'raw_work_variant', 'wrong_preimage_limit'):
        # These files deliberately violate nominal fields/union arguments, not syntax or protocol data.
        for command in ([ 'nim', 'check', '--mm:arc', ROOT / f'nim/tests/compile_fail/{name}.nim'],
                        [ 'odin', 'check', ROOT / f'odin/tests/compile_fail/{name}.odin', '-file']):
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            assert result.returncode != 0, command
            assert 'type mismatch' in result.stderr or 'Cannot assign value' in result.stderr, result.stderr
    drivers = [build / 'nim-composite-driver', build / 'odin-composite-driver']
    run(['nim', 'c', *nim_flags, f'--out:{drivers[0]}', ROOT / 'nim/tests/composite_driver.nim'])
    run(['odin', 'build', ROOT / 'odin/composite_driver', f'-out:{drivers[1]}', *linker])
    requests, expected = [], []

    # Append complete optional/work encoder cases with matching policy/storage precedence.
    def variant_encode(operation, tag, payload, limit, capacity):
        requests.append(f'{operation} {tag} {limit} {capacity} {token(payload.hex())}')
        has_blob = (operation == 'OE' and tag == 1) or (operation == 'WE' and tag == 0)
        if tag < 0 or tag > (1 if operation == 'OE' else 6):
            expected.append('inputerror' if operation == 'OE' else 'invalidtag') # Typed constructor protocol.
        elif has_blob and len(payload) > limit:
            expected.append('limitexceeded') # Only a payload-carrying variant applies blob policy.
        else:
            # Payload-free variants have no length field even when trusted source text contains unused bytes.
            wire = bytes([tag]) + (encode(len(payload)) + payload if has_blob else b'')
            expected.append(wire.hex() if len(wire) <= capacity else 'outputtoosmall')

    # Append variant decoder cases; unknown tags are rejected before narrowing/constructing typed variants.
    def variant_decode(operation, wire, limit):
        requests.append(f'{operation} {limit} {token(wire.hex())}')
        prefix = count_at(wire, 0, decode)
        if isinstance(prefix, str):
            expected.append(prefix) # No usable discriminant on prefix failure.
            return
        tag, offset = prefix
        maximum, blob_tag = (1, 1) if operation == 'OD' else (6, 0)
        if tag > maximum:
            expected.append('invalidtag') # Only the pinned schema tag set is accepted.
            return
        if tag != blob_tag:
            expected.append(f'absent {offset}' if operation == 'OD' else f'{tag}:- {offset}') # No nested payload.
            return
        blob = blob_at(wire, offset, limit, decode)
        if isinstance(blob, str):
            expected.append(blob) # Nested errors cannot expose a success/present value.
            return
        payload, consumed = blob
        expected.append(f'{"present" if operation == "OD" else "0"}:{token(payload.hex())} {consumed}')

    # Encode full tuple sequences independently of both native implementations.
    def preimage_encode(records, items, per_blob, total, capacity):
        text = ';'.join(f'{service}:{token(payload.hex())}' for service, payload in records)
        requests.append(f'PE {items} {per_blob} {total} {capacity} {token(text)}')
        if len(records) > items:
            expected.append('limitexceeded'); return # Outer count policy precedes storage and traversal.
        wire = encode(len(records))
        if len(wire) > capacity:
            expected.append('outputtoosmall'); return # The count alone must fit.
        budget = total
        for service, payload in records:
            # Per-record and aggregate payload budgets are checked before the next output extent.
            if len(payload) > min(per_blob, budget):
                expected.append('limitexceeded'); return
            field = service.to_bytes(4, 'little') + encode(len(payload)) + payload
            if len(field) > capacity - len(wire):
                expected.append('outputtoosmall'); return # Whole tuple extent must fit before commit.
            wire += field
            budget -= len(payload)
        expected.append(wire.hex())

    # Decode the full nested frame and compare actual service IDs/payloads, not just native round-trip bytes.
    def preimage_decode(wire, items, per_blob, total, capacity):
        requests.append(f'PD {items} {per_blob} {total} {capacity} {token(wire.hex())}')
        prefix = count_at(wire, 0, decode)
        if isinstance(prefix, str):
            expected.append(prefix); return # Outer count invalid before any record work.
        count, cursor = prefix
        if count > items:
            expected.append('limitexceeded'); return # Count stays arbitrary precision until all proofs.
        if count > (len(wire) - cursor) // 5:
            expected.append('truncated'); return # Four service bytes plus at least one blob-length byte per record.
        if count > capacity:
            expected.append('outputtoosmall'); return # Caller record capacity precedes nested scanning.
        values, budget = [], total
        for _ in range(count):
            if len(wire) - cursor < 4:
                expected.append('truncated'); return # A late missing tuple field must fail the entire frame.
            service = int.from_bytes(wire[cursor:cursor + 4], 'little')
            cursor += 4
            blob = blob_at(wire, cursor, min(per_blob, budget), decode)
            if isinstance(blob, str):
                expected.append(blob); return # Both policies apply before claimed payload slicing.
            payload, cursor = blob
            budget -= len(payload)
            values.append(f'{service}:{token(payload.hex())}')
        expected.append(f'{token(";".join(values))} {cursor}')

    pins = json.loads((ROOT / 'spec/pins.json').read_text())
    for path, digest in pins['vectors']['files'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path # Unmodified pinned fixture integrity.
    full_vector_checks = field_checks = 0
    for chain in ('tiny', 'full'):
        # Full preimage JSON and entire binary vectors are consumed and re-encoded by the native APIs.
        folder = ROOT / 'vendor/jamtestvectors/codec' / chain
        data = json.loads((folder / 'preimages_extrinsic.json').read_text())
        records = [(item['requester'], bytes.fromhex(item['blob'][2:])) for item in data]
        wire = (folder / 'preimages_extrinsic.bin').read_bytes()
        count, per_blob, total = len(records), max(len(p) for _, p in records), sum(len(p) for _, p in records)
        preimage_encode(records, count, per_blob, total, len(wire))
        assert expected[-1] == wire.hex() # Full encoder oracle must match official bytes before native execution.
        preimage_decode(wire, count, per_blob, total, count)
        assert expected[-1] == f'{token(";".join(f"{s}:{token(p.hex())}" for s, p in records))} {len(wire)}'
        full_vector_checks += 2
        for name in ('work_result_0', 'work_result_1'):
            # Work-output fields are real official spans, but the entire work-digest type is not implemented here.
            item = json.loads((folder / f'{name}.json').read_text())
            binary = (folder / f'{name}.bin').read_bytes()
            prefix = item['service_id'].to_bytes(4, 'little') + bytes.fromhex(item['code_hash'][2:])
            prefix += bytes.fromhex(item['payload_hash'][2:]) + item['accumulate_gas'].to_bytes(8, 'little')
            assert binary.startswith(prefix)
            if 'ok' in item['result']:
                tag, payload = 0, bytes.fromhex(item['result']['ok'][2:]) # Exact C.2 success field.
            else:
                assert item['result'] == {'panic': None}
                tag, payload = 2, b'' # Exact C.2 panic field.
            field = bytes([tag]) + (encode(len(payload)) + payload if tag == 0 else b'')
            suffix = b''.join(encode(item['refine_load'][key]) for key in
                              ('gas_used', 'imports', 'extrinsic_count', 'extrinsic_size', 'exports'))
            assert binary == prefix + field + suffix # All surrounding official bytes prove the field offset/extent.
            variant_encode('WE', tag, payload, len(payload), len(field))
            assert expected[-1] == field.hex()
            variant_decode('WD', field, len(payload))
            field_checks += 2
    rng = random.Random(0x434f4d504f)
    for size in (0, 1, 127, 128, 255, 256, 16383, 16384):
        payload = bytes(i % 256 for i in range(size))
        for operation, tag in (('OE', 1), ('WE', 0)):
            # Actual long payloads prove nested prefix-size transitions rather than checking just a claimed length.
            wire = bytes([tag]) + encode(size) + payload
            variant_encode(operation, tag, payload, size, len(wire))
            variant_encode(operation, tag, payload, max(0, size - 1), len(wire))
            variant_encode(operation, tag, payload, size, len(wire) - 1)
            decoder = 'OD' if operation == 'OE' else 'WD'
            variant_decode(decoder, wire + b'\x42', size)
            for cut in {0, 1, len(encode(size)), len(wire) - 1}:
                variant_decode(decoder, wire[:cut], size) # Missing discriminant/nested length/final payload.
    for tag in range(1, 7):
        variant_encode('WE', tag, b'\xaa', 0, 1) # Payload-free errors ignore unused pool bytes and zero blob policy.
        variant_decode('WD', bytes([tag, 255]), 0) # Trailing data must not be read as a blob length.
    variant_encode('OE', 0, b'\xff', 0, 1)
    variant_decode('OD', b'\x00\xff', 0)
    for count in (0, 1, 127, 128):
        records = [(rng.getrandbits(32), bytes([i % 256])) for i in range(count)]
        wire = encode(count) + b''.join(s.to_bytes(4, 'little') + encode(len(p)) + p for s, p in records)
        preimage_encode(records, count, 1, count, len(wire))
        preimage_decode(wire + b'\x42', count, 1, count, count)
        for cut in range(len(wire)):
            preimage_decode(wire[:cut], count, 1, count, count) # Every late-record truncation preserves earlier sentinels.
    for _ in range(300):
        records = [(rng.getrandbits(32), rng.randbytes(rng.randrange(17))) for _ in range(rng.randrange(9))]
        wire = encode(len(records)) + b''.join(s.to_bytes(4, 'little') + encode(len(p)) + p for s, p in records)
        total = sum(len(p) for _, p in records)
        per = max([len(p) for _, p in records] or [0])
        preimage_encode(records, len(records), per, total, len(wire))
        preimage_encode(records, len(records), per, total, len(wire) - 1) # Complete destination required.
        preimage_decode(wire, len(records), per, total, len(records))
        preimage_decode(wire, len(records), per, max(0, total - 1), len(records)) # Aggregate policy at a late blob.
        preimage_decode(wire, len(records), per, total, max(0, len(records) - 1)) # Typed output capacity.
    hostile = [b'', b'\x80\x00', encode(2**63), encode(2**64 - 1), b'\x02' + b'\0' * 4 + b'\0' + b'\0' * 4 + b'\x80\x00']
    for tag in range(256):
        hostile.extend((bytes([tag]) + b'\xff' * 8)[:cut] for cut in range(10)) # Every header and truncation size.
    hostile.extend(rng.randbytes(rng.randrange(65)) for _ in range(5000))
    for wire in hostile:
        limit = rng.choice((0, 3, 64, 2**64 - 1))
        variant_decode('OD', wire, limit)
        variant_decode('WD', wire, limit)
        preimage_decode(wire, rng.choice((0, 4, 2**64 - 1)), limit, limit, rng.randrange(9)) # No claimed-size allocation.
    request_file = build / 'composite-requests.txt'
    request_file.write_text('\n'.join(requests) + '\n')
    outputs = []
    for driver in codec_commands(build, drivers, 'composite'):
        # Each native adapter additionally asserts exact native re-encoding and failed-write atomicity.
        output = run([*driver, request_file], capture_output=True).stdout.splitlines()
        assert len(output) == len(expected), (driver, len(output), len(expected))
        for index, (actual, wanted) in enumerate(zip(output, expected)):
            assert actual == wanted, (driver, index, requests[index], actual, wanted)
        outputs.append(output)
    assert outputs[0] == outputs[1]
    print(f'PASS composite: {len(requests)} shared requests per implementation; '
          f'{full_vector_checks} complete official preimage checks; {field_checks} official work-output checks; '
          '6 negative compilation checks', flush=True)
