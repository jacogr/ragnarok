# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent literal bundles and Lagrange-coded chunk witnesses, with no native output inputs."""
import hashlib
from functools import lru_cache
from pvm_bundle_reference import witnesses as bundle_witnesses
from pvm_erasure_reference import interpolate, original_count


def digest(data):
    """Hash raw bytes using the specified 32-byte Blake2b output."""
    return hashlib.blake2b(data, digest_size=32).digest()


def bundle_bytes(rich=False):
    """Reconstitute the independently authored bundle's literal sections and cross-check its full hash."""
    expected = bundle_witnesses()['rich' if rich else 'ordinary']
    segments = [bytes([index]) + bytes(4103) for index in [1, 2, 3]]
    leaves = [digest(b'leaf' + segment) for segment in segments]
    right = digest(b'node' + leaves[2] + bytes(32))
    first = bytes([2]) + right + leaves[1]
    second = bytes([2]) + right + leaves[0]
    # Explicit raw section order includes repeated singleton imports and empty paths in the rich fixture.
    if rich:
        data = bytes([7])*128 + bytes([8])*129 + bytes([7])*128
        imported = bytes(4104) + segments[0] + segments[1] + bytes(4104)
        proofs = b'\0' + first + second + b'\0'
    else:
        data = b'abcabd'
        imported = segments[0] + segments[1]
        proofs = first + second
    bundle = bytes.fromhex(expected['package']) + data + imported + proofs
    assert len(bundle) == expected['length'] and digest(bundle).hex() == expected['hash']
    return bundle


def encode(data, validators):
    """Split contiguous originals, interpolate each little-endian word column and regroup by validator."""
    original = original_count(validators)
    padded = data + bytes((-len(data)) % (original*2))
    chunks = [padded[start:start+len(padded)//original]
              for start in range(0, len(padded), len(padded)//original)]
    output = [bytearray() for _ in range(validators)]
    for position in range(0, len(chunks[0]), 2):
        words = [int.from_bytes(chunk[position:position+2], 'little') for chunk in chunks]
        code = interpolate(list(range(original)), words, range(validators))
        for chunk, word in zip(output, code):
            chunk.extend(word.to_bytes(2, 'little'))
    return [bytes(chunk) for chunk in output]


@lru_cache(maxsize=1)
def witnesses():
    """Freeze complete encoded buffers plus explicit first/last parity chunks at both validator scales."""
    result = {}
    for name, rich, validators in [('Ordinary6', False, 6), ('Ordinary1023', False, 1023),
                                   ('Rich1023', True, 1023)]:
        data = bundle_bytes(rich)
        chunks = encode(data, validators)
        result[name] = dict(hash=digest(b''.join(chunks)).hex(),
                            first_parity=chunks[original_count(validators)].hex(),
                            last=chunks[-1].hex(), chunks=chunks, original=data)
    return result


if __name__ == '__main__':
    import json
    print(json.dumps({key: {field: value for field, value in row.items()
                           if field not in ('chunks', 'original')}
                      for key, row in witnesses().items()}, indent=2))
