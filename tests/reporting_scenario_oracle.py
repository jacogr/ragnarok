# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Retain independently calculated scenario inputs, signed blocks and complete maps without native observations."""
import hashlib
import json
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key


def collect(cases, fixture, sources, check_frozen=True):
    """Bind exact original inputs and every independently calculated successor/refusal before native execution."""
    requests, lines, roots, hashes, refusals = [], [], [], [], []
    transitions = 0
    for case in cases:
        parent = case['initial']
        encoded = checkpoint(list(parent.items()))
        requests.append(f"C {case['name']} {tree(list(parent.items()))[0].hex()} {encoded.hex()}")
        if 'parameters' in case: requests[-1] += ' '+case['parameters'].hex()
        lines.append('P '+encoded.hex()); roots.append([]); hashes.append([])
        for block, after, negatives in case['steps']:
            assert block[32:64] == tree(list(parent.items()))[0]
            assert int.from_bytes(after[chapter_key(11)], 'little') > int.from_bytes(parent[chapter_key(11)], 'little')
            for wire, reason in negatives:
                assert wire[32:64] == block[32:64]
                requests.append(f'N {wire.hex()} {reason}'); lines.append('N '+reason); refusals.append(reason)
            requests.append('B '+block.hex()); encoded = checkpoint(list(after.items()))
            lines.extend(('B '+block.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(after.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            parent = after; transitions += 1
    evidence = dict(transitions=transitions, chains=len(cases), roots=roots,
                    checkpoint_sha256=hashes, refusals=refusals)
    if any('parameters' in case for case in cases):
        evidence['parameters_sha256'] = [hashlib.sha256(case['parameters']).hexdigest() if 'parameters' in case else None for case in cases]
    if check_frozen:
        frozen = json.loads(fixture.read_text())
        assert frozen['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert frozen['sources_sha256'] == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        assert frozen['evidence'] == evidence
    return requests, lines, evidence
