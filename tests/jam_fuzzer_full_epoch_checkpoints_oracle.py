# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guest checkpoint restarts preserve population rotations and distinguish absent local ancestry evidence."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_epoch_guests_oracle as epochs
import jam_fuzzer_full_population_oracle as population
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_pending_disputes_oracle as pending
from current_stf_oracle import checkpoint,history,tree
from state_layout_oracle import chapter_key,digest
from state_trace_wire_oracle import wire as state_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-epoch-checkpoints.json'
MODES = epochs.MODES


@cache
def calculate():
    """Own honest restart headers, independent successor maps and genuine missing-child-root controls before execution."""
    lines,roots,hashes,controls = [],[],[],[]
    for mode in MODES:
        _,prefix = epochs.seed(mode);block,seed = prefix[-1];header = block[:297]
        records = history(seed[chapter_key(3)])[0];previous = records[-2][0];earlier = records[-3][0]
        assert int.from_bytes(previous[96:100],'little') == 5 and previous[64:96] == header[32:64]
        assert int.from_bytes(earlier[96:100],'little') == 4
        lines.extend(('H '+header.hex()+' 5','P '+checkpoint(list(seed.items())).hex()));roots.append([]);hashes.append([])
        report = guests.guarantee(seed,seed,slot=7,anchor=(previous,previous[64:96]))
        first,admitted = pending.advance(seed,7,[report]);expired,cleared = pending.advance(admitted,12)
        assert cleared[chapter_key(10)] == bytes(341)
        states = [(first,admitted),(expired,cleared)];parent = cleared
        # Restarted imports retain actual namespace outcomes and rotate once per imported epoch crossing.
        for slot in epochs.SLOTS:
            wire,parent = population.successor(parent,slot)
            states.append((wire,parent))
        for wire,state in states:
            encoded = checkpoint(list(state.items()));lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        report = guests.guarantee(seed,seed,slot=7,anchor=(earlier,earlier[64:96]))
        body,commitment = guests.body([report],[])
        author = int.from_bytes(digest(bytes(32)+(7).to_bytes(4,'little'))[:4],'little') %1023
        missing,_ = full.child(seed,body=body,extrinsic_root=commitment,author=author,secret=author+1)
        state = state_wire(sorted(seed.items()))
        # Slot4 membership is authentic, but header6 proves only its immediate parent5 prior-state root.
        initialize = b'\1'+header+state[32:]+b'\1'+(4).to_bytes(4,'little')+earlier[:32]
        controls.append(dict(initialize=initialize,block=missing,header=header,state=state))
    evidence = dict(graypaper_commit=full.GP,chains=len(MODES),transitions=24,initial_slot=6,initial_ancestry_slot=5,
                    epoch_guests_sha256=hashlib.sha256(epochs.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    missing_evidence_sha256=[hashlib.sha256(case['initialize']+case['block']).hexdigest() for case in controls],
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    return tuple(lines),evidence,tuple(controls)


def expected_observations(check_frozen=True):
    """Expose complete independent restart streams; native replies never supply expected state."""
    lines,evidence,_ = calculate()
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],list(lines),dict(evidence)


def local_evidence_cases():
    """Bind one authentic-metadata/missing-child control to each separately initialized guest checkpoint."""
    expected_observations()
    return [[dict(case)] for case in calculate()[2]]


def required_controls():
    """Declare local-evidence observations from the frozen fixture independently of generated job bindings."""
    frozen = json.loads(FIXTURE.read_text());assert frozen['chains'] == len(frozen['missing_evidence_sha256'])
    return dict(local_missing_evidence=frozen['chains'])
