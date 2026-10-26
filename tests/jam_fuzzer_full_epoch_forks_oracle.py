# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full consensus siblings diverge across an epoch boundary while retaining genuine guest effects."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_epoch_guests_oracle as guests
import jam_fuzzer_full_population_oracle as population
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-epoch-forks.json'
MODES = guests.MODES


def expected_observations(check_frozen=True):
    """Calculate an epoch-crossing sibling, original-last pre-epoch child and later canonical rotation from each real guest seed."""
    lines,roots,hashes = [],[],[]
    for mode in MODES:
        _,prefix = guests.seed(mode);header,parent = prefix[-1]
        assert int.from_bytes(header[96:100],'little') == 6
        lines.extend(('H '+header[:297].hex(),'P '+checkpoint(list(parent.items())).hex()));roots.append([]);hashes.append([])
        variant,sibling = population.successor(parent,600)
        original,ordinary = population.successor(parent,599)
        changed = {key for key in sibling if sibling[key] != ordinary[key]}
        assert {chapter_key(index) for index in (4,6,11,13)} <= changed
        extension,rotated = population.successor(ordinary,600)
        assert tree(list(sibling.items()))[0] != tree(list(rotated.items()))[0]
        # Original-last retains its sibling; the next canonical child retires that former sibling group.
        for kind,wire,state in (('V',variant,sibling),('B',original,ordinary),('B',extension,rotated)):
            encoded = checkpoint(list(state.items()));lines.extend((kind+' '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=population.guests.full.GP,chains=len(MODES),transitions=9,sibling_imports=3,
                    epoch_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
