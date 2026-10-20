# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent literal final exports, bottom-up proof pages and Lagrange erasure chunks."""
import hashlib
from functools import lru_cache
from pvm_bundle_erasure_reference import encode
from pvm_erasure_reference import original_count


def digest(data):
    """Hash exact leaf/node/raw bytes with the pinned 32-byte Blake2b width."""
    return hashlib.blake2b(data, digest_size=32).digest()


def segments(kind):
    """Author normalized final bytes directly, including discarded missing-code/panic exports."""
    good = bytes([11, 12, 13]) + bytes(4101)
    if kind == 0:
        return []
    if kind == 1:
        return [good]
    if kind == 3:
        return [good, bytes(4104), bytes(4104)]
    return [bytes(4104)]*kind


def commitment(data):
    """Build layers bottom-up, then derive root-first page paths and their exact canonical segment bytes."""
    capacity = 1
    while capacity < len(data):
        capacity *= 2
    leaves = [digest(b'leaf'+segment) for segment in data] + [bytes(32)]*(capacity-len(data))
    layers = [leaves]
    while len(layers[-1]) > 1:
        row = layers[-1]
        layers.append([digest(b'node'+row[index]+row[index+1]) for index in range(0, len(row), 2)])
    depth = len(layers)-1
    pages = []
    for page in range((len(data)+63)//64):
        path = [layers[level][(page >> (level-6)) ^ 1] for level in range(6, depth)]
        path.reverse()
        actual = leaves[page*64:min(page*64+64, len(data))]
        wire = bytes([len(path)]) + b''.join(path) + bytes([len(actual)]) + b''.join(actual)
        pages.append(wire+bytes(4104-len(wire)))
    return layers[-1][0], pages


@lru_cache(maxsize=None)
def coded(segment, validators):
    """Reuse identical literal zero segments without changing the independent coding transform."""
    return encode(segment, validators)


@lru_cache(maxsize=1)
def witnesses():
    """Commit every validator-major combined row buffer and explicit data/page parity chunks."""
    result = {}
    for name, kind, validators in [('Empty', 0, 6), ('Single', 1, 1023), ('Mixed', 3, 1023), ('Paged', 65, 6)]:
        data = segments(kind)
        root, pages = commitment(data)
        rows = data+pages
        matrix = [coded(segment, validators) for segment in rows]
        wire = b''.join(matrix[row][shard] for shard in range(validators) for row in range(len(rows)))
        original = original_count(validators)
        result[name] = dict(root=root, hash=digest(wire), rows=rows, matrix=matrix,
                            data_parity=matrix[0][original] if rows else b'',
                            page_parity=matrix[len(data)][validators-1] if pages else b'')
    return result
