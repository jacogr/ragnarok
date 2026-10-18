# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 Boolean/bitstring wire equations and deterministic adversarial requests."""
import random
import hashlib
import json
from test_support import ROOT
from test_codec import reference_encode as natural, reference_decode

MAX = 2**64-1


# An empty fixed string still needs one token in the trusted native batch transport.
def token(value):
    return value.hex() or '-'


# Construct packed octets from mathematical logical positions, with no native codec or round trip.
def packed(bits):
    return bytes(sum(int(bit) * 2**j for j, bit in enumerate(bits[i:i+8])) for i in range(0, len(bits), 8))


# Explicit schema framing counts logical bits; fixed terms contain payload alone.
def wire(bits, variable):
    return (natural(len(bits)) if variable else b'') + packed(bits)


# Independent Boolean inverse accepts exactly the two one-octet encoder images.
def boolean(data):
    # Both values require a complete first octet, regardless of unrelated suffix bytes.
    if not data:
        return 'truncated'
    # All remaining first octets are outside the Boolean domain rather than truthy aliases.
    if data[0] > 1:
        return 'noncanonical'
    return f'{data[0]} 1'


# Compute exact canonical prefix observation independently of the production owner's implementation.
def decode(data, variable, count, limit):
    cursor = 0
    # Variable schemas carry a canonical natural bit count; fixed schemas get it from their caller.
    if variable:
        prefix = reference_decode(data)
        # Framing errors do not publish a count or any progress.
        if prefix in ('truncated', 'noncanonical'):
            return prefix
        count, cursor = map(int, prefix.split())
    # Limit policy precedes waiting for a potentially huge claimed payload.
    if count > limit:
        return 'limitexceeded'
    length = (count + 7) // 8  # Arbitrary precision deliberately differs from production uint64 arithmetic.
    # Complete payload extent is needed before indexing a final partial byte.
    if length > len(data) - cursor:
        return 'truncated'
    payload = data[cursor:cursor+length]
    # Unused high bits cannot represent a second encoding of the same logical string.
    if count % 8 and payload[-1] >= 2**(count % 8):
        return 'noncanonical'
    bits = ''.join(str((payload[i//8] // 2**(i%8)) % 2) for i in range(count))
    return f'{cursor+length} {count} {bits or "-"} {token(payload)} {token(natural(count)+payload)}'


# Preflight independent logical encoder inputs before capacity, preserving precise failure ordering.
def encode(bits, variable, count, limit, capacity):
    # Fixed schemas cannot omit or synthesize logical source elements.
    if not variable and len(bits) != count:
        return 'invalidcount'
    # Variable counts come from the independently supplied logical source, never a decoded native frame.
    count = len(bits) if variable else count
    # A broad destination cannot override a smaller caller resource policy.
    if count > limit:
        return 'limitexceeded'
    data = wire(bits, variable)
    # Complete output capacity is mandatory before committing the first payload/prefix bit.
    if len(data) > capacity:
        return 'outputtoosmall'
    return token(data)


# Reproducible corpus covers exhaustive tails, natural count boundaries and hostile untrusted claims.
def requests():
    lines, expected = [], []

    # Each Boolean decode is an independent inverse-domain check, including complete unrelated suffixes.
    def bd(data):
        lines.append('BD ' + token(data)); expected.append(boolean(data))

    # Source bools are logical values; the native test adapter constructs typed bools without decoding wire.
    def enc(bits, variable, count=None, limit=MAX, capacity=None):
        count = len(bits) if count is None else count
        capacity = len(wire(bits, variable))+3 if capacity is None else capacity
        lines.append(f'E {"V" if variable else "F"} {count} {limit} {capacity} {bits or "-"}')
        expected.append(encode(bits, variable, count, limit, capacity))

    # Decoders get independently constructed bytes plus explicit count/limit domains.
    def dec(data, variable, count=0, limit=MAX):
        lines.append(f'D {"V" if variable else "F"} {count} {limit} {token(data)}')
        expected.append(decode(data, variable, count, limit))

    bd(b'')
    # Exhaust every first octet: exactly two should succeed, with or without trailing unrelated data.
    for octet in range(256):
        bd(bytes([octet])); bd(bytes([octet, 0xAA]))
    # Boolean output has zero/exact/spare capacity paths with a suffix canary.
    for value in (0, 1):
        # Every destination size must preserve canaries outside the single written octet.
        for capacity in (0, 1, 3):
            lines.append(f'BE {value} {capacity}')
            expected.append('outputtoosmall' if capacity == 0 else f'{value:02x}')
    # Every final-byte pattern is classified for every possible partial/full byte length and both framings.
    for count in range(1, 9):
        # Exhaustive byte coverage catches bit order and every nonzero unused-padding combination.
        for octet in range(256):
            payload = bytes([octet])
            dec(payload, False, count); dec(natural(count)+payload, True)
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Published profile assurance bitfields exercise the generic fixed-bit API without changing the specialized codec.
    for profile, cores in (('tiny', 2), ('full', 341)):
        folder = ROOT/f'vendor/jamtestvectors/codec/{profile}'
        # Existing fixture hashes cover every JSON field consumed by these generic primitive checks.
        for name in ('assurances_extrinsic', 'disputes_extrinsic'):
            path = folder/f'{name}.json'
            assert hashlib.sha256(path.read_bytes()).hexdigest() == pins[str(path.relative_to(ROOT))]
        assurances = json.loads((folder/'assurances_extrinsic.json').read_text())
        # Observe each complete bitfield under its exact logical profile length, including unused high bits.
        for record in assurances:
            data = bytes.fromhex(record['bitfield'][2:])
            bits = ''.join(str((data[i//8] >> (i%8)) & 1) for i in range(cores))
            assert packed(bits) == data
            dec(data, False, cores, cores); enc(bits, False, limit=cores)
        disputes = json.loads((folder/'disputes_extrinsic.json').read_text())
        votes = {vote['vote'] for verdict in disputes['verdicts'] for vote in verdict['votes']}
        votes.update(fault['vote'] for fault in disputes['faults'])
        # Distinct published Boolean values reproduce the ordinary primitive domain without inflating repeated cases.
        for value in sorted(votes):
            bd(bytes([int(value)]))
    rng = random.Random(0x42495453303830)
    # Empty, byte-boundary and natural-length discriminator transitions get independently authored logical sources.
    for count in (0, 1, 2, 7, 8, 9, 15, 16, 17, 63, 64, 65, 127, 128, 129, 255, 256, 1023, 1024, 16383, 16384):
        # All-zero/all-one/random inputs reveal partial-byte padding as well as little-significance-first positions.
        for bits in ('0'*count, '1'*count, ''.join(str(rng.randrange(2)) for _ in range(count))):
            # Fixed and variable schemas must share payload exactly but disagree about the discriminator.
            for variable in (False, True):
                data = wire(bits, variable)
                enc(bits, variable); dec(data+b'\xA5', variable, count)
                # Exact/short/empty destinations establish preflight capacity and untouched suffix behavior.
                for capacity in sorted({0, max(0, len(data)-1), len(data)}):
                    enc(bits, variable, capacity=capacity)
                # Limits include logical counts just below, exactly at, and above the required cardinality.
                for limit in sorted({0, max(0, count-1), count}):
                    enc(bits, variable, limit=limit, capacity=0); dec(data, variable, count, limit)
                # Truncate every small frame and representative packed boundaries in larger strings.
                for cut in range(len(data)) if len(data) < 40 else sorted({0, 1, len(data)//2, len(data)-1}):
                    dec(data[:cut], variable, count)
                # Fixed schemas must reject even enormous mismatching counts before output policy/capacity.
                if not variable:
                    enc(bits, False, count=count+1, limit=0, capacity=0)
    # Oversized claims exercise every natural-width transition and uint64 maximum without allocating their payloads.
    for count in [2**k+d for k in (7, 14, 21, 28, 35, 42, 49, 56, 63) for d in (-1, 0, 1)] + [MAX-7, MAX-1, MAX]:
        # Broad and strict limits distinguish missing payload from resource-policy rejection.
        for limit in (MAX, max(0, count-1), 0):
            dec(natural(count), True, limit=limit); dec(b'', False, count, limit)
    # Overlong count encodings and every proper count prefix retain primitive canonicality/truncation precedence.
    for data in (b'\x80\0', b'\xc0\0\0', b'\xff'+bytes(8), b'\x80', b'\xff'+bytes(7)):
        dec(data, True); dec(data, True, limit=0)
    # Random hostile byte streams supplement structured length and padding boundary cases.
    for _ in range(2000):
        data = rng.randbytes(rng.randrange(80))
        dec(data, True, limit=rng.choice((0, 8, 1024, MAX)))
        dec(data, False, rng.randrange(512), rng.choice((0, 8, 1024, MAX)))
    return lines, expected
