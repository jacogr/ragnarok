# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent service namespaces and current supervisor metadata, frozen with direct-partition trie roots."""
import hashlib
from state_proof_reference import node


def hashed(service, domain):
    """Apply the pinned interleave equation to an independently hashed raw namespace preimage."""
    digest = hashlib.blake2b(domain, digest_size=32).digest()
    number = service.to_bytes(4, 'little')
    return b''.join(bytes([number[i], digest[i]]) for i in range(4)) + digest[4:27]


def fixture():
    """Build four full independently serialized maps spanning empty, inline and hashed preimage leaves."""
    lines = []
    for service, size in [(0, 0), (7, 1), (0x12345678, 32), (0xffffffff, 33)]:
        # Supervisor and all account fields are encoded directly, not through a production codec.
        blob = bytes(range(size))
        digest = hashlib.blake2b(blob, digest_size=32).digest()
        raw = bytes(range(size // 2))
        stored = bytes(reversed(blob))
        metadata = (b'\0' + digest + (17).to_bytes(4, 'little') + (19).to_bytes(4, 'little')
                    + b''.join(value.to_bytes(8, 'little') for value in [99, 101, 103, 107, size, 109])
                    + b''.join(value.to_bytes(4, 'little') for value in [3, 2, 4, 23]))
        number = service.to_bytes(4, 'little')
        account = bytes([255]) + b''.join(bytes([number[i], 0]) for i in range(4)) + bytes(22)
        storage = hashed(service, bytes([255])*4 + raw)
        preimage = hashed(service, bytes([254, 255, 255, 255]) + digest)
        request = hashed(service, size.to_bytes(4, 'little') + digest)
        history = b'\1' + (4).to_bytes(4, 'little')
        entries = [(account, metadata), (storage, stored), (preimage, blob), (request, history)]
        root, _ = node(entries, 0, account)
        fields = [str(service), raw.hex() or '-', stored.hex() or '-', blob.hex() or '-', digest.hex(),
                  account.hex(), storage.hex(), preimage.hex(), request.hex(), metadata.hex(), history.hex(), root.hex()]
        lines.append(' '.join(fields))
    return '\n'.join(lines) + '\n'
