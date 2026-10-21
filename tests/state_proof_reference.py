# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent direct-partition reference for frozen GP trie proof fixtures.

The reference uses hashlib and unsorted list partitions, never production sorting,
node codecs or proof extraction. It exports cases and serialized fixture text.
"""
import hashlib


def node(entries, depth, query):
    """Return commitment and selected raw path with exact GP left truncation."""
    if not entries:
        # Empty subtrees contribute no node to the path.
        return bytes(32), []
    if len(entries) == 1:
        # Canonical inline leaves pad to 32 bytes; regular leaves commit raw value bytes.
        key, value = entries[0]
        if len(value) <= 32:
            raw = bytes([128 + len(value)]) + key + value.ljust(32, b'\0')
        else:
            raw = b'\xc0' + key + hashlib.blake2b(value, digest_size=32).digest()
        return hashlib.blake2b(raw, digest_size=32).digest(), [raw]
    # Partition directly instead of reusing production sorted range/binary search.
    mask = 1 << (247-depth)
    left = [entry for entry in entries if not int.from_bytes(entry[0], 'big') & mask]
    right = [entry for entry in entries if int.from_bytes(entry[0], 'big') & mask]
    a, left_path = node(left, depth+1, query)
    b, right_path = node(right, depth+1, query)
    raw = bytes([a[0] & 127]) + a[1:] + b
    selected = right_path if int.from_bytes(query, 'big') & mask else left_path
    return hashlib.blake2b(raw, digest_size=32).digest(), [raw, *selected]


def cases():
    """Cover empty/singleton, every value representation and shallow/deep branches."""
    result = []
    for size in (0, 1, 32, 33, 65):
        # A singleton needs no branch regardless of the query's shared prefix.
        key = bytes(31)
        entries = [(key, bytes(range(size)))]
        for query in (key, bytes([128]) + bytes(30)):
            result.append((entries, query))
    result.append(([], bytes(31)))
    for depth in (0, 1, 7, 8, 127, 239, 246, 247):
        # Explicit divergence bits exercise unary paths, both directions and empty-edge absence.
        entries = [(bytes(31), b''), ((1 << (247-depth)).to_bytes(31, 'big'), bytes(range(33)))]
        for query in (entries[0][0], entries[1][0], bytes([255])*31):
            result.append((entries, query))
    entries = [(hashlib.sha256(bytes([i])).digest()[:31], bytes([i])*i) for i in range(1, 9)]
    for query in [entry[0] for entry in entries] + [bytes(31), bytes([255])*31]:
        result.append((entries, query))
    return result


def fixture():
    """Serialize complete independent inputs, raw paths and expected roots without hidden metadata."""
    lines = []
    for entries, query in cases():
        # Root/path are independently derived; an absent neighbor's value is never supplied.
        root, path = node(entries, 0, query)
        found = next((value for key, value in entries if key == query), None)
        value = b'' if found is None else found
        fields = [root.hex(), query.hex(), str(int(found is not None)), value.hex() or '-', str(len(path))]
        fields.extend(raw.hex() for raw in path)
        fields.append(str(len(entries)))
        for key, payload in entries:
            fields.extend((key.hex(), payload.hex() or '-'))
        lines.append(' '.join(fields))
    return '\n'.join(lines) + '\n'
