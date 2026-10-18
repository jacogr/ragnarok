# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent C.2 prefix oracle and hashlib key binding for the CE fixture integration workload."""
import hashlib
from digest_checks import parse_digest
from test_codec import reference_decode


# Codec validity, exact standalone consumption and content binding are separate admission stages.
def verdict(wire, key):
    parsed = parse_digest(wire, 1024*1024, reference_decode)
    # A malformed compact field/tag/payload cannot publish an owner or reach hashing.
    if parsed in ('truncated','noncanonical','limitexceeded','invalidtag'):
        return 'codec'
    # Prefix decoders require an independent standalone-frame consumption guard.
    if int(parsed.rsplit(' ',1)[1]) != len(wire):
        return 'trailing'
    # Hash exact serialized preimage bytes, not any similarly sized digest field.
    if hashlib.blake2b(wire,digest_size=32).digest() != key:
        return 'hashmismatch'
    return 'ok '+wire.hex()


# Replay original official/authored integration fixtures plus truncations and original arbitrary-capture bytes.
def requests(folder):
    lines, expected = [], []
    # Each capture expectation uses only the independent mathematical codec and standard-library hashing.
    def capture(wire, key=None):
        key = hashlib.blake2b(wire,digest_size=32).digest() if key is None else key
        lines.append('C '+key.hex()+' '+(wire.hex() or '-'))
        expected.append(verdict(wire,key))
    for i in range(8):
        wire = (folder/f'{i}.bin').read_bytes()
        lines.append('K '+wire.hex())
        expected.append(hashlib.blake2b(wire,digest_size=32).hexdigest())
        capture(wire)
        key = bytearray(hashlib.blake2b(wire,digest_size=32).digest());key[0] ^= 1
        capture(wire,bytes(key))
        # Every small prefix and bounded large-record endpoints reject without advertised-size allocations.
        for n in (range(len(wire)) if len(wire)<512 else (*range(96),len(wire)-1)):
            capture(wire[:n])
        capture(wire+b'\0')
    state, mask = 0x494e544547524154, 2**64-1
    for iteration in range(10000):
        raw = bytearray()
        # Match the original test byte stream with explicit arbitrary-precision masking, not a native decoder.
        for _ in range(128):
            state = (state ^ (state<<13)) & mask
            state = (state ^ (state>>7)) & mask
            state = (state ^ (state<<17)) & mask
            raw.append(state & 255)
        capture(bytes(raw[:iteration%129]))
    return lines,expected
