# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent literal packages, Lagrange shards and GP raw-leaf availability trees."""
from functools import lru_cache
from pvm_bundle_reference import digest, fixed, natural, immediate, preimage
from pvm_bundle_erasure_reference import encode
from pvm_export_erasure_reference import witnesses as export_witnesses


def bundle(kind):
    """Build the exact no-external-input package used by exportBundle without production serialization."""
    halt = bytes([50, 0])
    good = [immediate(7, 65536), immediate(8, 3), bytes([10, 8]), immediate(8, 0), halt]
    if kind == 0:
        guests = [([immediate(8, 0), halt], 0)]
    elif kind == 1:
        guests = [(good, 1)]
    elif kind == 3:
        guests = [(good, 1), ([halt], 1), (good[:3]+[bytes([0])], 1)]
    else:
        guests = [([halt], kind)]
    header = fixed(77, 4)+digest(preimage([halt]))
    context = bytes(132)+fixed(20, 4)+bytes(32)+b'\0'
    items = []
    for index, (program, exports) in enumerate(guests):
        items.append(fixed(42+index, 4)+digest(preimage(program))+fixed(10000, 8)
                     +fixed(100, 8)+fixed(exports, 2)+bytes([2, 81, 42+index])+b'\0\0')
    return header+context+bytes([1, 91, 2, 81, 82])+natural(len(items))+b''.join(items)


def node(items, hashing=digest, floor=False):
    """GP N returns raw singleton leaves and splits the unpadded sequence at ceil(n/2)."""
    if not items:
        return bytes(32)
    if len(items) == 1:
        return items[0]
    split = len(items)//2 if floor else (len(items)+1)//2
    return hashing(b'node'+node(items[:split], hashing, floor)+node(items[split:], hashing, floor))


def balanced(items, hashing=digest, floor=False):
    """Only a standalone singleton WB call hashes its raw item separately."""
    if len(items) == 1:
        return hashing(items[0])
    return node(items, hashing, floor)


@lru_cache(maxsize=1)
def witnesses():
    """Construct every six-field availability witness and count actual independent hash preimages."""
    result = {}
    cases = [('Empty', 0, 6), ('Single', 1, 1023), ('Mixed', 3, 1023), ('Paged', 65, 6)]
    exports = export_witnesses()
    for name, kind, validators in cases:
        data = bundle(kind)
        chunks = encode(data, validators)
        matrix = exports[name]['matrix']
        stats = [0, 0]

        def hashing(raw):
            """Count each real oracle hash and its exact preimage length, independent of production formulas."""
            stats[0] += 1
            stats[1] += len(raw)
            return digest(raw)

        leaves = []
        for index, chunk in enumerate(chunks):
            leaves.append(hashing(chunk)+balanced([row[index] for row in matrix], hashing))
        root = balanced(leaves, hashing)
        wire = (digest(data)+fixed(len(data), 4)+root+fixed(validators, 2)
                +exports[name]['root']+fixed(kind, 2))
        result[name] = dict(bundle=data, root=root, first=leaves[0], last=leaves[-1],
                            wire=wire, calls=stats[0], hash_bytes=stats[1], leaves=leaves)
    return result
