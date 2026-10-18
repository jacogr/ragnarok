# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent compact-argument and initial-service-ID witnesses for GP Psi_A/I.

Exposes candidate and prepare using Python's arbitrary-precision arithmetic and hashlib Blake2b.
"""
import hashlib
import json
import random
from test_codec import reference_encode

FIRST = 2**16
END = 2**32-2**8


# General E concatenates compact service, raw entropy and compact slot, without header-specific E4 widths.
def candidate(service, entropy, slot):
    seed = reference_encode(service)+entropy+reference_encode(slot)
    return int.from_bytes(hashlib.blake2b(seed, digest_size=32).digest()[:4], 'little') % (END-FIRST)+FIRST


# Explicit occupied sets and unbounded modular arithmetic determine each expected bounded membership search.
def prepare(folder):
    rng = random.Random(0x494E564F43415445)
    cases = []
    widths = (0, 1, 127, 128, 16383, 16384, 65536, 2**32-1)
    # Cross every service/slot compact-width boundary with empty and full-width argument counts.
    for service in widths:
        for slot in widths:
            cases.append((service, slot, rng.choice((0, 1, 127, 128, 16384, 2**64-1)), bytes(32)))
    # Additional entropy and arbitrary u32 values prevent zero-word or narrow-scalar special cases.
    for _ in range(128):
        cases.append((rng.randrange(2**32), rng.randrange(2**32), rng.randrange(2**64), rng.randbytes(32)))
    lines = []
    # For every seed, exact and one-below ceilings distinguish final absence from a guessed next ID.
    for ordinal, (service, slot, count, entropy) in enumerate(cases):
        first = candidate(service, entropy, slot)
        occupied_count = ordinal % 6
        occupied = {(first-FIRST+i) % (END-FIRST)+FIRST for i in range(occupied_count)}
        selected = next((first-FIRST+i) % (END-FIRST)+FIRST
                        for i in range(occupied_count+1) if (first-FIRST+i) % (END-FIRST)+FIRST not in occupied)
        arguments = reference_encode(slot)+reference_encode(service)+reference_encode(count)
        for probes in (occupied_count, occupied_count+1):
            expected = 'LimitExceeded' if probes <= occupied_count else str(selected)
            lines.append(f'{service} {slot} {count} {entropy.hex()} {first} {arguments.hex()} '
                         f'{",".join(map(str, sorted(occupied))) or "-"} {probes} {expected}')
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-invocation.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(authored_contexts=len(lines), fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-invocation.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
