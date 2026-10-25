# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent epoch/ticket fork STF maps replay attributed known Ring inputs without generating campaigns."""
import hashlib
import json
from pathlib import Path
from current_stf_epoch_oracle import (FIXTURE as BASE, expected_observations as epoch, bank_records,
                                      successor, submitted_for, SLOTS, consensus)
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key
from state_complete_serialization_oracle import checkpoint

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-epoch-forks.json'


def expected_observations(check_frozen=True):
    """Every mutant removes one current ticket; original-last alone controls later winners, rotations and entropy."""
    requests, _, _ = epoch()
    fixture = json.loads(BASE.read_text())
    bank = bank_records(fixture)
    initial = bytes.fromhex(fixture['parent_checkpoint'])
    original = decode_checkpoint(initial)
    roots = dict(pending=consensus(original[chapter_key(4)])[1], staging=bytes.fromhex(fixture['staging_ring_root']))
    lines, variants, accepted = [], 0, 0
    for slots in SLOTS:
        parent = dict(original)
        lines.append('P '+initial.hex())
        for slot in slots:
            submitted = submitted_for(slot, bank)
            if submitted:
                wire, changed = successor(parent, slot, submitted[:-1], bank, roots)
                lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(changed.items())).hex()))
                variants += 1
            wire, parent = successor(parent, slot, submitted, bank, roots)
            lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(parent.items())).hex()))
            accepted += 1
    evidence = dict(base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(), original_last=accepted,
                    ticket_siblings=variants, successful_imports=accepted+variants, chains=3,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == evidence
    return requests, lines, evidence
