# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guest effects survive offender filtering, two full-profile epoch rotations and population resizing."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_population_oracle as population
import jam_fuzzer_full_pending_disputes_oracle as pending
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_offenders_oracle as offenders
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-epoch-guests.json'
MODES = guests.MODES
SLOTS = (599,600,601,1199,1200,1201)


@cache
def seed(mode):
    """Admit genuine evidence and a correctly assigned report, then execute each literal guest outcome before rotation."""
    initial = population.original(mode);states = population.prelude(initial);parent = states[-1][1]
    wire,parent = population.successor(parent,4);states.append((wire,parent))
    report = guests.guarantee(parent,initial,slot=5)
    phi = offenders.judgments(parent[chapter_key(5)])[3]
    assert len(phi) == 5 and all(guests.roster_records()[index][32:64] not in phi for index,_ in report['credentials'])
    wire,parent = pending.advance(parent,5,[report]);states.append((wire,parent))
    wire,parent = guests.advance(parent,initial,mode,6,[],guests.assurances(parent,683),report,admission_slot=5)
    states.append((wire,parent))
    return initial,tuple(states)


def expected_observations(check_frozen=True):
    """Freeze every complete pre/post guest and epoch map before any native observation supplies an answer."""
    lines,roots,hashes = [],[],[]
    for mode in MODES:
        initial,prefix = seed(mode);states = list(prefix);parent = states[-1][1]
        lines.append('P '+checkpoint(list(initial.items())).hex());roots.append([]);hashes.append([])
        # Each crossing rotates once; the second makes the shorter physical population active with four NULL slots.
        for slot in SLOTS:
            wire,parent = population.successor(parent,slot);states.append((wire,parent))
        assert len(offenders.roster(parent[chapter_key(8)])) == 1020
        assert sum(row == population.NULL_VALIDATOR for row in offenders.roster(parent[chapter_key(8)])) == 4
        assert len(offenders.roster(parent[chapter_key(9)])) == 1023
        for wire,state in states:
            encoded = checkpoint(list(state.items()));lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=guests.full.GP,chains=len(MODES),transitions=33,
                    population_sha256=hashlib.sha256(population.FIXTURE.read_bytes()).hexdigest(),
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
