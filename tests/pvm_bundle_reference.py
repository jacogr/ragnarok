# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP makebundle witnesses from literal guest instructions, packages and input bytes.

No production codec/hash output is read. Running this module prints reproducible JSON witnesses.
"""
import hashlib
import json


def digest(data):
    """Hash exact raw octets with the pinned Blake2b-256 output width."""
    return hashlib.blake2b(data, digest_size=32).digest()


def fixed(value, width):
    """Encode independently bounded literal E-width integers little-endian."""
    return value.to_bytes(width, 'little')


def natural(value):
    """Encode canonical JAM naturals for the small frozen fixture lengths."""
    assert 0 <= value < 16384
    # These witnesses span both the one- and two-byte canonical domains.
    if value < 128:
        return bytes([value])
    return bytes([128 + value // 256, value % 256])


def immediate(register, value):
    """Author the fixed load_imm_64 instruction without production assembler helpers."""
    return bytes([20, register]) + fixed(value, 8)


def preimage(instructions):
    """Frame metadata, literal standard envelope, raw program and its independent start mask."""
    code = b''.join(instructions)
    mask = bytearray((len(code) + 7) // 8)
    cursor = 0
    # Only authored instruction starts are set; operands never become executable boundaries.
    for instruction in instructions:
        mask[cursor // 8] |= 1 << (cursor % 8)
        cursor += len(instruction)
    raw = b'\0\0' + natural(len(code)) + code + mask
    return (b'\0' + fixed(3, 3) + fixed(3, 3) + bytes(5) + bytes([11, 12, 13])
            + bytes([21, 22, 23]) + fixed(len(raw), 4) + raw)


def fetched(selector):
    """Fetch three current-item bytes to stack memory, then return the exact written interval."""
    return [immediate(7, 196608), immediate(8, 0), immediate(9, 3),
            immediate(10, selector), immediate(11, 0), immediate(12, 0), bytes([10, 2]),
            immediate(7, 196608), immediate(8, 3), bytes([50, 0])]


def witnesses():
    """Build complete independent package/section encodings for ordinary and mixed-shape fixtures."""
    segments = [bytes([i]) + bytes(4103) for i in (1, 2, 3)]
    leaves = [digest(b'leaf' + segment) for segment in segments]
    left = digest(b'node' + leaves[0] + leaves[1])
    right = digest(b'node' + leaves[2] + bytes(32))
    root = digest(b'node' + left + right)
    singleton = bytes(4104)
    single_root = digest(b'leaf' + singleton)
    paths = [[right, leaves[1]], [right, leaves[0]], [left, bytes(32)]]
    auth = [immediate(7, 65536), immediate(8, 3), bytes([50, 0])]
    header = fixed(77, 4) + digest(preimage(auth))
    context = bytes(132) + fixed(20, 4) + bytes(32) + b'\0'
    result = {}
    # Distinct item/code/manifest shapes test both flattening order and omitted discriminators.
    for rich in (False, True):
        programs = ([[immediate(8, 0), bytes([50, 0])]] * 3 if rich
                    else [fetched(4), fetched(6)])
        extrinsics = ([[b'', bytes([7]) * 128], [],
                       [bytes([8]) * 129, b'', bytes([7]) * 128]] if rich
                      else [[b'abc'], [b'abd']])
        imported = ([[(-1, False), (0, False)], [], [(1, False), (-1, False)]] if rich
                    else [[(0, False)], [(1, True)]])
        items = []
        data, imports, proofs = b'', b'', b''
        # All blobs precede all imported leaves, which precede all path encodings.
        for index, program in enumerate(programs):
            encoded_imports = b''
            # Preserve every manifest occurrence and encode only its path with a discriminator.
            for ordinal, package_reference in imported[index]:
                segment, siblings, tree_root = ((singleton, [], single_root) if ordinal == -1
                                                else (segments[ordinal], paths[ordinal], root))
                reference = bytes([1]) + bytes(31) if package_reference else tree_root
                encoded_imports += reference + fixed(
                    max(ordinal, 0) | (32768 if package_reference else 0), 2)
                imports += segment
                proofs += natural(len(siblings)) + b''.join(siblings)
            blobs = extrinsics[index]
            commitments = b''.join(digest(blob) + fixed(len(blob), 4) for blob in blobs)
            item = (fixed(42 + index, 4) + digest(preimage(program)) + fixed(10000, 8)
                    + fixed(100, 8) + fixed(0, 2) + bytes([2, 81, 42 + index])
                    + natural(len(imported[index])) + encoded_imports
                    + natural(len(blobs)) + commitments)
            items.append(item)
            data += b''.join(blobs)
        package = header + context + bytes([1, 91, 2, 81, 82]) + natural(len(items)) + b''.join(items)
        bundle = package + data + imports + proofs
        result['rich' if rich else 'ordinary'] = dict(
            package=package.hex(), hash=digest(bundle).hex(),
            length=len(bundle), extrinsic_bytes=len(data), segment_bytes=len(imports), proof_bytes=len(proofs))
    result['long128_hash'] = digest(bytes([7]) * 128).hex()
    result['long129_hash'] = digest(bytes([8]) * 129).hex()
    return result


# Standalone output can regenerate frozen witnesses without consulting any Nim implementation.
if __name__ == '__main__':
    print(json.dumps(witnesses(), indent=2, sort_keys=True))
