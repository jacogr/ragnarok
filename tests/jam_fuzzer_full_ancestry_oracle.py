# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guest checkpoint ancestry, long full-profile sessions and honest missing child-root evidence."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_epochs_oracle as epochs
from current_stf_oracle import checkpoint, history, tree
from state_layout_oracle import chapter_key, digest
from state_trace_wire_oracle import wire as state_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-ancestry.json'


@cache
def calculate():
    """Calculate the complete checkpoint and every later map plus a separately signed missing-evidence control."""
    parent = guests.original('create'); initial = parent; stored = None
    # Build the checkpoint solely from independent whole-map guest equations, never captured native output.
    for slot in (2,3,4):
        gs = [guests.guarantee(parent,initial)] if slot == 3 else []
        if gs: stored = gs[0] # Keep the exact admitted report through its later genuine availability quorum.
        header,parent = guests.advance(parent,initial,'create',slot,gs,guests.assurances(parent,683 if slot == 4 else 0),stored)
    seed = parent; seed_header = header[:297]
    records = history(seed[chapter_key(3)])[0]
    anchor = records[-2][0]
    assert int.from_bytes(anchor[96:100],'little') == 3 and anchor[64:96] == seed_header[32:64]
    lines = ['H '+seed_header.hex()+' 3','P '+checkpoint(list(seed.items())).hex()];roots=[];hashes=[]
    stored = None
    # Twenty-eight real descendants exceed both the eight-entry C3 history and the default24 ancestry records.
    for slot in range(5,33):
        if slot in (5,6):
            gs = [guests.guarantee(parent,seed,slot=5,anchor=(anchor,anchor[64:96]))] if slot == 5 else []
            if gs: stored = gs[0] # The lookup at3 is proved by the supplied actual child header4.
            block,parent = guests.advance(parent,seed,'create',slot,gs,guests.assurances(parent,683 if slot == 6 else 0),stored,admission_slot=5)
        else:
            block,parent = epochs.successor(parent,slot) # Later whole maps preserve guest namespaces and advance history per block.
        encoded = checkpoint(list(parent.items()));lines.extend(('B '+block.hex(),'O '+encoded.hex()))
        roots.append(tree(list(parent.items()))[0].hex());hashes.append(hashlib.sha256(encoded).hexdigest())
    # Initial slot2 membership is honest but cannot supply the absent child3 prior-state root.
    earlier = records[-3][0]
    assert int.from_bytes(earlier[96:100],'little') == 2 and earlier[64:96] != bytes(32)
    missing_report = guests.guarantee(seed,seed,slot=5,anchor=(earlier,earlier[64:96]))
    body,commitment = guests.body([missing_report],[])
    author = int.from_bytes(digest(bytes(32)+(5).to_bytes(4,'little'))[:4],'little') %1023
    missing,_ = full.child(seed,body=body,extrinsic_root=commitment,author=author,secret=author+1)
    state = state_wire(sorted(seed.items()))
    initialize = b'\1'+seed_header+state[32:]+b'\1'+(2).to_bytes(4,'little')+earlier[:32]
    control = dict(initialize=initialize,block=missing,header=seed_header,state=state)
    evidence = dict(graypaper_commit=full.GP,chains=1,transitions=28,initial_slot=4,initial_ancestry_slot=3,
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    missing_evidence_sha256=hashlib.sha256(initialize+missing).hexdigest(),
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    return tuple(lines),evidence,control


def expected_observations(check_frozen=True):
    """Return independently frozen seed/header/descendant bytes; native replies never enter the reference."""
    lines,evidence,_ = calculate()
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence # Every full-map byte is frozen before native replay.
    return [],list(lines),dict(evidence)


def local_evidence_cases():
    """Expose the precomputed honest-metadata/missing-child control to the actual socket owner."""
    expected_observations()
    return [dict(calculate()[2])]
