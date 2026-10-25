# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full guest maps for nine valid siblings, eight-state eviction and original-last continuation."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_epochs_oracle as epochs
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-fork-capacity.json'
CAPACITY = 8


@cache
def calculate():
    """Calculate every full snapshot before native execution, including each additional genuine assurance signature."""
    lines,roots,hashes = [],[],[]
    for mode in guests.MODES:
        initial = guests.original(mode);parent = initial;stored = None
        # The independent seed contains an admitted real report whose guest has not yet executed.
        for slot in (2,3):
            gs = [guests.guarantee(parent,initial)] if slot == 3 else []
            if gs: stored = gs[0] # Availability siblings share this same immutable report and pre-guest parent.
            block,parent = guests.advance(parent,initial,mode,slot,gs,[],stored)
        lines.extend(('H '+block[:297].hex(),'P '+checkpoint(list(parent.items())).hex()));roots.append([]);hashes.append([])
        baseline,original = guests.advance(parent,initial,mode,4,[],guests.assurances(parent,683),stored)
        # Nine distinct genuine quorums overflow exactly the actual eight-state target window.
        for count in range(684,693):
            block,variant = guests.advance(parent,initial,mode,4,[],guests.assurances(parent,count),stored)
            assert {key for key in variant if variant[key] != original[key]} == {chapter_key(3),chapter_key(13)}
            encoded = checkpoint(list(variant.items()));lines.extend(('V '+block.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(variant.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        # Original-last execution preserves all guest effects, then a direct extension retires the old sibling group.
        for block,result in ((baseline,original),epochs.successor(original,5)):
            encoded = checkpoint(list(result.items()));lines.extend(('B '+block.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(result.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=guests.full.GP,chains=3,transitions=33,sibling_imports=27,fork_capacity=CAPACITY,
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    return tuple(lines),evidence


def expected_observations(check_frozen=True):
    """Expose only precommitted independently authored seed/header/block/map streams."""
    lines,evidence = calculate()
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence # Observed native states never supply an expected map.
    return [],list(lines),dict(evidence)
