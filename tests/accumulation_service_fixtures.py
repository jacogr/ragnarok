# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent accounts two-blob envelope and Psi_A code-size gate witnesses.

Exposes resolve and prepare for deterministic authored contexts; no PVM execution is simulated.
"""
import hashlib
import json
import random
from test_codec import reference_encode, reference_decode


# Interpret E(length(metadata)) || metadata || code with unbounded offsets and a separate local ceiling.
def resolve(raw, code_limit, preimage_limit):
    if len(raw) > preimage_limit:
        return 'LimitExceeded', b''  # Resource refusal never becomes protocol ineligibility.
    parsed = reference_decode(raw)
    if parsed in ('truncated', 'noncanonical'):
        return 'Malformed', b''  # The account definition supplies no code after malformed framing.
    length, prefix = map(int, parsed.split())
    if length > len(raw)-prefix:
        return 'Malformed', b''  # Prove the complete metadata before taking the remaining suffix.
    code = raw[prefix+length:]
    if len(code) > code_limit:
        return 'Oversized', code  # Protocol eligibility uses only the code suffix length.
    return 'Ready', code


# Seeded envelopes vary prefix boundaries, metadata, code and independent protocol/resource limits.
def prepare(folder):
    rng = random.Random(0x53455256494345)
    cases = [b'', b'\x80', b'\x80\x00', b'\xff'+bytes([255])*8,
             reference_encode(128)+bytes(127), b'\x00', b'\x00\x01', b'\x01\xff\x02']
    # Original framing is authored directly from the mathematical compact-natural encoder.
    for index in range(128):
        metadata = bytes([index])*rng.choice((0, 1, 127, 128, 16383, 16384))
        code = bytes([index+1])*rng.choice((0, 1, 4, 127, 128))
        cases.append(reference_encode(len(metadata))+metadata+code)
    lines = []
    # Each envelope sees zero, exact-ish and restrictive independent size ceilings.
    for ordinal, raw in enumerate(cases):
        for code_limit, preimage_limit in ((0, len(raw)), (128, len(raw)), (128, max(0, len(raw)-1))):
            status, code = resolve(raw, code_limit, preimage_limit)
            lines.append(f'{ordinal} {code_limit} {preimage_limit} {raw.hex() or "-"} '
                         f'{status} {code.hex() or "-"}')
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-service.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(authored_contexts=len(lines), fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-service.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
