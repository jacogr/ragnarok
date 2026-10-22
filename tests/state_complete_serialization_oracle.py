# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent current-schema complete typed mappings and local V1 checkpoint bytes.

Authored examples use the existing independent chapter and trie equations, never
native output. These are serialization witnesses, not upstream valid-state vectors.
"""
from pathlib import Path
import hashlib
from state_composition_oracle import chapters, entries
from state_accounts_oracle import wire as metadata_wire
from state_trie_oracle import tree

ROWS = 32
SIZES = (0, 1, 31, 32, 33, 63, 64, 65)
MAGIC = b'RAGNAROK-FULL-V1\n'

def word(case, field, bits):
    """Distinct input fingerprints expose field swaps, E4/E8 widths and unsigned extremes."""
    if case % 8 == 0:
        return 0
    if case % 8 == 1:
        return (1 << bits)-1
    return ((case << (bits-8)) | (field << (bits-16)) | 0x0102)

def source(case):
    """Author all sixteen chapters and one fully identified service without opaque captures."""
    values = chapters()
    values[10] = word(case, 1, 32).to_bytes(4, 'little')
    raw_key = bytes((case+i) % 256 for i in range(SIZES[case % 8]))
    storage = bytes((3*case+i) % 256 for i in range(SIZES[(case+2) % 8]))
    payload = bytes((7*case+i) % 256 for i in range(SIZES[(case+4) % 8]))
    identity = hashlib.blake2b(payload, digest_size=32).digest()
    slots = tuple(range(1, case % 4+1))
    # The metadata layout is independently assembled from protocol-width input fields.
    wide = [word(case, i, 64) for i in range(1, 5)]
    wide += [34+81+len(raw_key)+len(storage)+len(payload), word(case, 6, 64)]
    narrow = [3, word(case, 2, 32), word(case, 3, 32), word(case, 4, 32),
              word(case, 5, 32), word(case, 6, 32)]
    metadata = metadata_wire((bytes(range(32)), wide, narrow))
    sid = (0, (1 << 32)-1, 0x01020304, 256)[case % 4]
    service = (sid, metadata, [(raw_key, storage)], [(identity, payload)],
               [(identity, len(payload), slots)], [])
    return values, service

def checkpoint(pairs):
    """Encode the documented local envelope directly around a list-partition commitment."""
    assert len({key for key, _ in pairs}) == len(pairs)
    root, _ = tree(pairs)
    return MAGIC + len(pairs).to_bytes(8, 'little') + root + b''.join(
        key + len(value).to_bytes(8, 'little') + value for key, value in sorted(pairs))

def encoded():
    """Each line contains one exact complete checkpoint, including every sorted key/value byte."""
    return ''.join(checkpoint(entries(values, [service])).hex()+'\n'
                   for values, service in map(source, range(ROWS))).encode()

def refusal_cases():
    """Recommit omitted/trailing chapters so typed failure is isolated from root integrity."""
    values = chapters()
    baseline = entries(values, [])
    yield 'V', 0, checkpoint(baseline)
    for chapter in range(1, 17):
        yield 'M', chapter, checkpoint(baseline[:chapter-1]+baseline[chapter:])
        altered = list(baseline)
        key, value = altered[chapter-1]
        altered[chapter-1] = (key, value+b'\0')
        yield 'T', chapter, checkpoint(altered)

def refusals_encoded():
    """Explicit verdict/chapter labels describe typed semantics outside the checkpoint wire format."""
    return ''.join(f'{mode} {chapter} {wire.hex()}\n'
                   for mode, chapter, wire in refusal_cases()).encode()

def multiservice_encoded():
    """Four disjoint IDs per source cover metadata plus all three service namespaces."""
    values = chapters()
    return ''.join(checkpoint(entries(values, [source(4*group+i)[1] for i in range(4)])).hex()+'\n'
                   for group in range(8)).encode()

if __name__ == '__main__':
    # Explicit regeneration changes only the authored fixture; descriptors are reviewed separately.
    (Path(__file__).parent/'fixtures/complete-serialization.txt').write_bytes(encoded())
    (Path(__file__).parent/'fixtures/serialization-refusals.txt').write_bytes(refusals_encoded())
    (Path(__file__).parent/'fixtures/multiservice-serialization.txt').write_bytes(multiservice_encoded())
