"""Independent mathematical work-report oracle and deterministic shared corpus (test-only)."""
import copy
import hashlib
import json
import random
from pathlib import Path
from test_codec import reference_encode as natural, reference_decode
from digest_checks import wire_for as digest_wire, parse_digest

ROOT = Path(__file__).resolve().parents[1]
MAX_BLOBS = 49152


# Preserve empty fields in the trusted whitespace-separated adapter representation.
def token(data):
    return data.hex() or '-'


# Convert official named JSON fields into the separate oracle's complete report representation.
def official(chain):
    item = json.loads((ROOT / f'vendor/jamtestvectors/codec/{chain}/work_report.json').read_text())
    spec, ctx = item['package_spec'], item['context']
    # Upstream fixture hex is explicitly prefixed, unlike the trusted adapter protocol.
    def blob(value):
        return bytes.fromhex(value[2:])
    header = (blob(spec['hash']) + spec['length'].to_bytes(4, 'little') + blob(spec['erasure_root'])
              + blob(spec['exports_root']) + spec['exports_count'].to_bytes(2, 'little')
              + b''.join(blob(ctx[k]) for k in ('anchor', 'state_root', 'beefy_root', 'lookup_anchor'))
              + ctx['lookup_anchor_slot'].to_bytes(4, 'little'))
    digests = []
    # Work outputs retain their normative success/error discriminators and all five load metrics.
    for entry in item['results']:
        tag, payload = (0, blob(entry['result']['ok'])) if 'ok' in entry['result'] else (2, b'')
        digests.append((entry['service_id'], blob(entry['code_hash']), blob(entry['payload_hash']),
                        entry['accumulate_gas'], tag, payload,
                        [entry['refine_load'][k] for k in ('gas_used', 'imports', 'extrinsic_count', 'extrinsic_size', 'exports')]))
    return dict(header=header, prerequisites=b''.join(blob(x) for x in ctx['prerequisites']),
                core=item['core_index'], authorizer=blob(item['authorizer_hash']), gas=item['auth_gas_used'],
                auth=blob(item['auth_output']), lookup=b'', digests=digests)


# Serialize the complete C.2 layout directly, without calling any production candidate implementation.
def encode(value):
    return (value['header'] + natural(len(value['prerequisites']) // 32) + value['prerequisites']
            + natural(value['core']) + value['authorizer'] + natural(value['gas'])
            + natural(len(value['auth'])) + value['auth'] + natural(len(value['lookup']) // 64)
            + value['lookup'] + natural(len(value['digests']))
            + b''.join(digest_wire(d, natural) for d in value['digests']))


# Flatten named fields into an independent construction request, not a work-report decode/re-encode request.
def fields(value):
    return ' '.join((token(value['header']), token(value['prerequisites']), str(value['core']),
                     token(value['authorizer']), str(value['gas']), token(value['auth']), token(value['lookup']),
                     token(b''.join(digest_wire(d, natural) for d in value['digests'])), str(len(value['digests']))))


# Internal oracle rejection carries only its reason, mirroring the candidates' failure-only contract.
class Rejected(Exception):
    pass


# Parse every field with arbitrary-precision cursors; return named-field text and consumed count or a reason.
def decode(data, cores):
    cursor = 0
    # Size proofs precede indexing, including missing fixed headers and late payloads.
    def take(length):
        nonlocal cursor
        if length > len(data) - cursor:
            raise Rejected('truncated')
        result = data[cursor:cursor + length]
        cursor += length
        return result
    # The oracle's interval-based primitive decoder checks canonicality before advancing this cursor.
    def number():
        nonlocal cursor
        parsed = reference_decode(data[cursor:])
        if parsed in ('truncated', 'noncanonical'):
            raise Rejected(parsed)
        value, length = map(int, parsed.split())
        cursor += length
        return value
    # Sets/maps require strict key ordering, so equal adjacent keys also fail.
    def ordered(raw, stride):
        keys = [raw[i:i + 32] for i in range(0, len(raw), stride)]
        if any(a >= b for a, b in zip(keys, keys[1:])):
            raise Rejected('noncanonical')
    try:
        header = take(234)
        prerequisites = number()
        if prerequisites > 8:
            raise Rejected('limitexceeded')
        prereq_bytes = take(32 * prerequisites)
        ordered(prereq_bytes, 32)
        core = number()
        if core >= cores:
            raise Rejected('limitexceeded')
        authorizer = take(32)
        gas, auth_length = number(), number()
        if auth_length > MAX_BLOBS:
            raise Rejected('limitexceeded')
        auth = take(auth_length)
        lookups = number()
        if lookups > 8 - prerequisites:
            raise Rejected('limitexceeded')
        lookup = take(64 * lookups)
        ordered(lookup, 64)
        count = number()
        if count < 1 or count > 16:
            raise Rejected('limitexceeded')
        start = cursor
        total = auth_length
        # Reuse the separately proven independent digest oracle, never a native candidate codec.
        for _ in range(count):
            result = parse_digest(data[cursor:], MAX_BLOBS - total, reference_decode)
            if result in ('truncated', 'noncanonical', 'invalidtag', 'limitexceeded'):
                raise Rejected(result)
            parts = result.split()
            if parts[4] == '0' and parts[5] != '-':
                total += len(bytes.fromhex(parts[5]))
            cursor += int(parts[-1])
        return ' '.join((token(header), token(prereq_bytes), str(core), token(authorizer), str(gas),
                         token(auth), token(lookup), token(data[start:cursor]), str(count), str(cursor)))
    except Rejected as error:
        return str(error)


# Build small, ordinary and protocol-boundary reports; identical bytes are used for every language.
def corpus():
    base = official('full')
    result = [('official', base)]
    small = copy.deepcopy(base)
    small.update(auth=b'', digests=[(0, bytes(32), bytes(32), 0, 0, b'', [0] * 5)], core=0)
    result.append(('minimal', small))
    for name, count, auth_size, blob_size, prerequisites, lookups in (
            ('typical', 4, 256, 1024, 2, 2), ('maximum-metadata', 16, 0, 0, 4, 4),
            ('maximum-payload', 16, 8192, 2560, 4, 4), ('maximum-auth', 1, 49152, 0, 8, 0),
            ('maximum-lookup', 1, 0, 0, 0, 8)):
        value = copy.deepcopy(small)
        value['auth'] = bytes((i * 29 + 11) % 256 for i in range(auth_size))
        value['prerequisites'] = b''.join(bytes([i + 1]) * 32 for i in range(prerequisites))
        value['lookup'] = b''.join(bytes([i + 17]) * 32 + bytes([i + 101]) * 32 for i in range(lookups))
        value['core'], value['gas'] = 340, 2**64 - 1
        value['digests'] = [(i + 1, bytes([i + 19]) * 32, bytes([i + 37]) * 32,
                             2**64 - 1, 0, bytes([i + 73]) * blob_size,
                             [0, 127, 128, 16384, 2**64 - 1]) for i in range(count)]
        result.append((name, value))
    return result


# Produce deterministic malformed and valid requests; expected semantics come only from this oracle.
def requests():
    lines, expected = [], []
    # Keep each request paired with its independently computed expected response.
    def add_decode(wire, cores=341):
        lines.append(f'D {cores} {token(wire)}')
        expected.append(decode(wire, cores))
    # Official JSON/binary equality checks include both configured chain profiles and immutable file hashes.
    pins = json.loads((ROOT / 'spec/pins.json').read_text())
    for chain, cores in (('tiny', 6), ('full', 341)):
        value = official(chain)
        wire = (ROOT / f'vendor/jamtestvectors/codec/{chain}/work_report.bin').read_bytes()
        for extension in ('json', 'bin'):
            path = f'vendor/jamtestvectors/codec/{chain}/work_report.{extension}'
            assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == pins['vectors']['files'][path]
        assert encode(value) == wire
        assert decode(wire, cores) == fields(value) + ' ' + str(len(wire))
        add_decode(wire, cores)
        lines.append(f'E {cores} {len(wire)} ' + fields(value)); expected.append(wire.hex())
    # Every corpus frame tests independent construction, prefix consumption and exact/insufficient capacities.
    for name, value in corpus():
        wire = encode(value)
        assert decode(wire, 341) == fields(value) + ' ' + str(len(wire)), name
        for suffix in (b'', b'\xaa\xbb'):
            add_decode(wire + suffix)
        for capacity in (0, len(wire) - 1, len(wire), len(wire) + 7):
            lines.append(f'E 341 {capacity} ' + fields(value))
            expected.append(wire.hex() if capacity >= len(wire) else 'outputtoosmall')
        # All truncations of small/ordinary and metadata-boundary structures; large blobs use targeted cuts.
        cuts = range(len(wire)) if len(wire) < 8192 else sorted(set((0, 233, 234, 235, len(wire)//2, len(wire)-1)))
        for length in cuts:
            add_decode(wire[:length])
        # Native-only assertions additionally exercise late failures, owner lifetime and alias atomicity.
        for kind in ('span', 'count', 'tag', 'core', 'alias'):
            lines.append(f'X 341 {kind} {token(wire)}')
            expected.append({'span':'invalidspan', 'count':'limitexceeded', 'tag':'invalidtag',
                             'core':'limitexceeded', 'alias':'aliasedbuffers'}[kind])
    rng = random.Random(0x5245504F5254)
    values = corpus()
    # Structured mutation reaches nested canonicality, blob, metric and dependency fields.
    for i in range(8000):
        wire = bytearray(encode(values[i % len(values)][1]))
        for _ in range(rng.randrange(1, 5)):
            at = rng.randrange(len(wire))
            wire[at] = rng.randrange(256)
        if i % 3 == 0:
            wire = wire[:rng.randrange(len(wire))]
        add_decode(bytes(wire), (0, 6, 341)[i % 3])
    # Pure arbitrary bytes also exercise missing headers and hostile count encodings.
    for _ in range(1000):
        add_decode(rng.randbytes(rng.randrange(750)))
    # Explicit noncanonical and count-overflow prefixes cannot narrow into fixed metadata arrays.
    base = encode(values[1][1])
    for prefix in (natural(9), natural(2**64-1), b'\x80\x00'):
        add_decode(base[:234] + prefix + base[235:])
    # Valid individual blobs whose sum is excessive must fail in both encoding and decoding.
    value = copy.deepcopy(values[1][1])
    value['auth'] = bytes(MAX_BLOBS)
    value['digests'][0] = (0, bytes(32), bytes(32), 0, 0, b'x', [0] * 5)
    add_decode(encode(value))
    lines.append('E 341 65536 ' + fields(value)); expected.append('limitexceeded')
    # Counts and core indices are validated independently from actual buffer availability.
    for core in (6, 340, 341, 2**64-1):
        value = copy.deepcopy(values[1][1]); value['core'] = core
        for cores in (6, 341):
            add_decode(encode(value), cores)
            lines.append(f'E {cores} 65536 ' + fields(value))
            expected.append(encode(value).hex() if core < cores else 'limitexceeded')
    # Explicit set/dictionary order and shared dependency-budget failures are independent of fuzz luck.
    for kind in ('prerequisite-duplicate','prerequisite-descending','lookup-duplicate','lookup-descending','dependency-budget'):
        value = copy.deepcopy(values[1][1])
        first,second = bytes([1])*32,bytes([2])*32
        if kind.startswith('prerequisite'):
            value['prerequisites'] = first+first if kind.endswith('duplicate') else second+first
        elif kind.startswith('lookup'):
            value['lookup'] = first+bytes([71])*32+(first if kind.endswith('duplicate') else bytes(32))+bytes([72])*32
        else:
            value['prerequisites'] = b''.join(bytes([i])*32 for i in range(5))
            value['lookup'] = b''.join(bytes([i])*32+bytes([i+41])*32 for i in range(4))
        add_decode(encode(value))
        lines.append('E 341 65536 '+fields(value))
        expected.append('limitexceeded' if kind == 'dependency-budget' else 'noncanonical')
    # Locate scalar/count fields in a minimal report independently of the native decoder's progress metadata.
    minimal = encode(values[1][1])
    # prerequisite count 234, core 235, auth gas 268, auth length 269, lookup count 270, digest count 271.
    for position in (234,235,268,269,270,271):
        add_decode(minimal[:position]+b'\x80\x00'+minimal[position+1:])
    for count in (0,17,2**64-1):
        add_decode(minimal[:271]+natural(count)+minimal[272:])
    # The final digest metric is canonical and complete only after its entire natural payload exists.
    add_decode(minimal[:-1]+b'\x80\x00')
    add_decode(minimal[:-1]+b'\xff'+bytes(7))
    return lines, expected
