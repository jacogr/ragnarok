# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guest STF maps from exact fuzz seeds with different header and state clocks."""
import hashlib
import json
from pathlib import Path
import current_stf_effects_oracle as effects
from current_stf_oracle import decode_checkpoint, checkpoint, tree, history
from current_stf_trace_genesis_oracle import initial_header
from state_layout_oracle import digest, chapter_key
from state_history_oracle import wire as history_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-seed-guests.json'


def expected_observations(check_frozen=True):
    """Keep state at1 and supply an exact slot0 seed, signing the genuine slot2 child to that unchanged header."""
    effects.expected_observations() # Preserve the original frozen family and its independently authored guest programs.
    header = bytearray(initial_header())
    header[96:100] = bytes(4)
    header = bytes(header)
    lines, roots = [], []
    for case in json.loads(effects.FIXTURE.read_text())['cases']:
        parent = decode_checkpoint(bytes.fromhex(case['parent_checkpoint']))
        records, peaks = history(parent[chapter_key(3)])
        fixed, pairs = records[-1]
        parent[chapter_key(3)] = history_wire(([(digest(header)+fixed[32:96]+bytes(4), pairs)], peaks))
        lines.extend(('H '+header.hex(), 'P '+checkpoint(list(parent.items())).hex()))
        roots.append([])
        for index in range(2):
            payloads = effects.PAYLOADS if index == 0 else ()
            child, parent = effects.successor(parent, case['mode'], payloads)
            lines.extend(('B '+child.hex(), 'O '+checkpoint(list(parent.items())).hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex())
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    base_sha256=hashlib.sha256(effects.FIXTURE.read_bytes()).hexdigest(),
                    transitions=10, chains=5, guest_executions=20, header_slot=0, state_slot=1,
                    roots=roots, expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return [], lines, evidence
