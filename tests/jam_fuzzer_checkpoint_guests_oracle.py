# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map guest continuation after fresh checkpoint-seeded fuzz sessions."""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as guests
from current_stf_oracle import checkpoint, tree
from current_stf_reporting_oracle import assurances
from current_stf_trace_genesis_oracle import initial_header

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-checkpoint-guests.json'


def expected_observations(check_frozen=True):
    """Resume exact independently calculated checkpoints with only parent membership and the real seed child header."""
    guests.expected_observations() # Keep the original guest equation/program family frozen independently.
    lines, roots = [], []
    for mode in guests.MODES:
        parent = guests.original(mode)
        header = initial_header()
        lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([])
        for slot in range(2, 9):
            if slot in (3, 5, 7):
                # The seed header itself proves the supplied parent's prior root; no missing full child is fabricated.
                lines.extend(('H '+header.hex()+' '+str(slot-2),
                              'P '+checkpoint(list(parent.items())).hex()))
            gs = [guests.guarantee(parent, parent, 1, slot, service=99)] if slot in (3, 5, 7) else []
            ass = assurances(parent, 5 if slot in (4, 6, 8) else 0, 2)
            wire, posterior = guests.advance(parent, parent, mode, slot, gs, ass)
            lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(posterior.items())).hex()))
            roots[-1].append(tree(list(posterior.items()))[0].hex())
            parent = posterior
            header = wire[:297]
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    base_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    transitions=35, chains=5, checkpoints=15, sessions=20,
                    roots=roots, expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return [], lines, evidence
