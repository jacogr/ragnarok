# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent epoch-divergent guest states overflow the real eight-state fork window and retire on canonical extension."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_epoch_guests_oracle as guests
import jam_fuzzer_full_population_oracle as population
from current_stf_oracle import checkpoint,tree

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-epoch-capacity.json'
MODES = guests.MODES
CAPACITY = 8


def expected_observations(check_frozen=True):
    """Calculate nine direct epoch-crossing variants and the original-last continuation independently for each guest outcome."""
    lines,roots,hashes = [],[],[]
    for mode in MODES:
        _,prefix = guests.seed(mode);block,parent = prefix[-1]
        lines.extend(('H '+block[:297].hex(),'P '+checkpoint(list(parent.items())).hex()));roots.append([]);hashes.append([])
        states = []
        # Nine differently timed real epoch imports exceed exactly the configured eight retained positions.
        for slot in range(600,609):
            wire,state = population.successor(parent,slot);states.append(('V',wire,state))
        original,ordinary = population.successor(parent,599);extension,rotated = population.successor(ordinary,600)
        states.extend((('B',original,ordinary),('B',extension,rotated)))
        for kind,wire,state in states:
            encoded = checkpoint(list(state.items()));lines.extend((kind+' '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        assert len(set(roots[-1])) == 11
    evidence = dict(graypaper_commit=population.guests.full.GP,chains=len(MODES),transitions=33,sibling_imports=27,fork_capacity=CAPACITY,
                    epoch_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
