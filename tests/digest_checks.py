"""Independent full work-digest oracle, pinned official vectors and shared native checks."""
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]


# Preserve empty payloads as explicit adapter tokens.
def token(data):
    return data.hex() or '-'


# Encode the C.2 tuple directly using Python's separate integer/byte operations and mathematical natural oracle.
def wire_for(value, encode):
    service, code, payload_hash, gas, tag, blob, metrics = value
    result = service.to_bytes(4, 'little') + code + payload_hash + gas.to_bytes(8, 'little') + bytes([tag])
    # Only successful work outputs have a variable blob; errors are payload-free.
    if tag == 0:
        result += encode(len(blob)) + blob
    return result + b''.join(encode(metric) for metric in metrics)


# Report every field in native-adapter order, ensuring hash/metric swaps cannot hide behind round trips.
def text_for(value, consumed):
    service, code, payload_hash, gas, tag, blob, metrics = value
    return ' '.join(map(str, (service, code.hex(), payload_hash.hex(), gas, tag,
                             token(blob) if tag == 0 else '-', *metrics, consumed)))


# Decode a full prefix with arbitrary-precision checked cursors, independently of either production tuple codec.
def parse_digest(data, limit, decode):
    # Fixed fields must exist before any scalar conversion or hash slice.
    if len(data) < 76:
        return 'truncated'
    cursor = 76

    # Consume exactly one canonical natural at the current cursor, preserving failure categories.
    def natural_at():
        nonlocal cursor
        result = decode(data[cursor:])
        # Overlong and incomplete fields cannot advance the shared cursor.
        if result in ('truncated', 'noncanonical'):
            return result
        value, consumed = map(int, result.split())
        cursor += consumed
        return value

    tag = natural_at()
    # Discriminator errors precede schema interpretation.
    if isinstance(tag, str):
        return tag
    if tag > 6:
        return 'invalidtag' # No unrecognized tag is narrowed into a union/enum.
    blob = b''
    # Success alone carries a length-prefixed blob with caller policy.
    if tag == 0:
        length = natural_at()
        if isinstance(length, str):
            return length # Missing or overlong nested count.
        if length > limit:
            return 'limitexceeded' # Apply policy before checking actual payload extent.
        if length > len(data) - cursor:
            return 'truncated' # No padding for missing payload bytes.
        blob = data[cursor:cursor + length]
        cursor += length
    metrics = []
    # Validate all five naturals, including the last field, before exposing a usable digest.
    for _ in range(5):
        metric = natural_at()
        if isinstance(metric, str):
            return metric # No partial tuple on suffix failure.
        metrics.append(metric)
    value = (int.from_bytes(data[:4], 'little'), data[4:36], data[36:68],
             int.from_bytes(data[68:76], 'little'), tag, blob, metrics)
    return text_for(value, cursor)


# Construct the unchanged independent corpus without building or executing a native adapter.
def batch_requests(encode, decode):
    requests, expected = [], []

    # Encode all fields using explicit limits and destination capacities in the native test protocol.
    def add_encode(value, limit, capacity):
        service, code, payload_hash, gas, tag, blob, metrics = value
        requests.append(' '.join(map(str, ('E', limit, capacity, service, code.hex(), payload_hash.hex(), gas, tag, token(blob), *metrics))))
        # Policy failures precede destination capacity; payload-free errors ignore blob limits.
        if tag == 0 and len(blob) > limit:
            expected.append('limitexceeded')
        else:
            wire = wire_for(value, encode)
            expected.append(wire.hex() if len(wire) <= capacity else 'outputtoosmall')

    # Decode one full tuple prefix and compare every field, not just re-encoded identity.
    def add_decode(wire, limit):
        requests.append(f'D {limit} {token(wire)}')
        expected.append(parse_digest(wire, limit, decode))

    official = 0
    # Tiny/full success and panic fixtures are unmodified complete work-digest JSON/binary pairs.
    for chain in ('tiny', 'full'):
        for name in ('work_result_0', 'work_result_1'):
            folder = ROOT / 'vendor/jamtestvectors/codec' / chain
            item = json.loads((folder / f'{name}.json').read_text())
            tag, blob = (0, bytes.fromhex(item['result']['ok'][2:])) if 'ok' in item['result'] else (2, b'')
            metrics = [item['refine_load'][key] for key in ('gas_used', 'imports', 'extrinsic_count', 'extrinsic_size', 'exports')]
            value = (item['service_id'], bytes.fromhex(item['code_hash'][2:]), bytes.fromhex(item['payload_hash'][2:]), item['accumulate_gas'], tag, blob, metrics)
            wire = (folder / f'{name}.bin').read_bytes()
            assert wire_for(value, encode) == wire
            add_encode(value, len(blob), len(wire))
            add_decode(wire, len(blob))
            assert expected[-1] == text_for(value, len(wire))
            official += 2
    rng = random.Random(0x444947455354)
    boundaries = [0, 1, 127, 128, 16383, 16384, 2**56 - 1, 2**56, 2**64 - 1]
    # Independently vary all six integer positions across prefix transitions and full-width maxima.
    for position in range(6):
        for number in boundaries:
            metrics = [0] * 5
            gas = 42
            if position == 0:
                gas = number # Accumulation gas always remains exactly eight bytes.
            else:
                metrics[position - 1] = number # Refinement counters use canonical naturals.
            value = (2**32 - 1, bytes(range(32)), bytes(range(255, 223, -1)), gas, 0, b'\xaa\xbb', metrics)
            wire = wire_for(value, encode)
            add_encode(value, 2, len(wire))
            add_decode(wire + b'\xff', 2)
            for cut in range(len(wire)):
                add_decode(wire[:cut], 2)
    # Exercise real long blobs through the nested length-header transitions.
    for size in (0, 1, 127, 128, 255, 256, 16383, 16384):
        value = (7, rng.randbytes(32), rng.randbytes(32), 1, 0, rng.randbytes(size), [1, 2, 3, 4, 5])
        wire = wire_for(value, encode)
        add_encode(value, size, len(wire))
        add_encode(value, max(0, size - 1), len(wire))
        add_encode(value, size, len(wire) - 1)
        add_decode(wire, size)
        add_decode(wire, max(0, size - 1))
        # Missing tag, length, payload and each suffix byte have independent error paths.
        for cut in (76, 77, len(wire) - 6, len(wire) - 1):
            add_decode(wire[:cut], size)
    # Random valid tuples cover every error tag, differing nominal fields and arbitrary metrics.
    for _ in range(300):
        tag = rng.randrange(7)
        value = (rng.getrandbits(32), rng.randbytes(32), rng.randbytes(32), rng.getrandbits(64), tag,
                 rng.randbytes(rng.randrange(33)), [rng.choice(boundaries) for _ in range(5)])
        wire = wire_for(value, encode)
        limit = len(value[5]) if tag == 0 else 0
        add_encode(value, limit, len(wire))
        add_encode(value, limit, len(wire) - 1)
        add_decode(wire + b'\x42', limit)
        # Mutations beyond the fixed prefix exercise variants and counters without always failing the initial guard.
        for _ in range(3):
            changed = bytearray(wire)
            changed[rng.randrange(76, len(changed))] = rng.randrange(256)
            add_decode(changed, 64)
    fixed = bytes(76)
    for header in range(256):
        for cut in range(10):
            add_decode(fixed + (bytes([header]) + bytes([255]) * 8)[:cut], 2**64 - 1)
    for position in range(5):
        add_decode(fixed + b'\x02' + bytes(position) + b'\x80\x00' + bytes(4 - position), 0)
    # Reproducible arbitrary buffers reach both short-prefix guards and deeper suffix parsing.
    for _ in range(5000):
        add_decode(rng.randbytes(rng.randrange(161)), rng.choice((0, 3, 64, 2**64 - 1)))
    return requests, expected, official
