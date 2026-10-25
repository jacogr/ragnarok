# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile same-block offender exclusion, prior-active assurance eligibility and genuine guest effects."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_pending_disputes_oracle as pending
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_verdicts_oracle as verdicts
import jam_fuzzer_full_offenders_oracle as offenders
from current_stf_report_guests_oracle import permutation
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key,digest

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-offender-guests.json'
BAD = digest(b'full same-block offender known bad report')
MODES = guests.MODES


def original(mode):
    """Keep each literal guest outcome while supplying an already-bad target for genuine culprit evidence."""
    parent = guests.original(mode);parent[chapter_key(5)] = offenders.encoded(([],[BAD],[],[]))
    return parent


def expected_observations(check_frozen=True):
    """Freeze failed punished-key guarantees, valid alternatives and683-vote guest releases before any client executes."""
    lines,roots,hashes = [],[],[];punished = []
    for mode in MODES:
        initial = original(mode);parent = initial;lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        states = []
        wire,parent = pending.advance(parent,2);states.append(('B',wire,parent,None))
        report = guests.guarantee(parent,initial)
        order = permutation(parent[chapter_key(6)][64:96],1023)
        group = [index for index,position in enumerate(order) if position//3 % 341 == 340]
        assert len(group) == 3;index = group[-1];punished.append(index)
        value = verdicts.payload(culprits=[offenders.culprit(index,BAD)])
        blocked = dict(report,credentials=[(i,guests.signed(i,b'jam_guarantee',digest(report['report']))[1]) for i in group[1:]])
        try: pending.advance(parent,3,[blocked],value)
        except AssertionError as error: assert str(error) == 'credential/InvalidSignature'
        else: raise AssertionError('independent reference admitted a newly offending guarantor')
        _,marks,_ = verdicts.plan(parent,value)
        wire,_,_,_ = pending.sealed(parent,3,[blocked],value,marks)
        states.append(('R',wire,parent,'credential/InvalidSignature'))
        allowed = dict(report,credentials=[(i,guests.signed(i,b'jam_guarantee',digest(report['report']))[1]) for i in group[:2]])
        wire,parent = pending.advance(parent,3,[allowed],value);states.append(('B',wire,parent,None))
        # The punished identity remains in prior active Gamma and must still be accepted as an assurer.
        selected = {index,1022}
        for voter in range(1023):
            if len(selected) == 683: break
            selected.add(voter)
        selected = sorted(selected);assert len(selected) == 683 and index in selected and 1022 in selected
        assured = guests.assurances(parent,683,indices=selected)
        wire,parent = guests.advance(parent,initial,mode,4,[],assured,allowed)
        states.append(('B',wire,parent,None))
        # Ordinary continuation shifts the nonempty accumulated-history ring once and preserves the complete guest namespace.
        wire,header,entropy_output,author = pending.sealed(parent,5,[],verdicts.payload(),[])
        parent = full.successor(parent,header,entropy_output,author=author);states.append(('B',wire,parent,None))
        assert offenders.judgments(parent[chapter_key(5)])[3] == [guests.roster_records()[index][32:64]]
        for kind,wire,state,reason in states:
            lines.append(kind+' '+wire.hex()+(' '+reason if reason is not None else ''))
            encoded = checkpoint(list(state.items()));lines.append('O '+encoded.hex())
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=len(MODES),transitions=15,accepted=12,refused=3,punished_indices=punished,
                    pending_fixture_sha256=hashlib.sha256(pending.FIXTURE.read_bytes()).hexdigest(),
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
