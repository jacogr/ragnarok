# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile verdict cancellation before assurances, same-block offender eligibility and genuine guest execution."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_pending_disputes_oracle as pending_reports
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_verdicts_oracle as verdicts
import jam_fuzzer_full_offenders_oracle as offenders
from current_stf_oracle import checkpoint,history,tree
from current_stf_reporting_oracle import pending
from state_layout_oracle import chapter_key,digest
from disputes_oracle import wire as disputes_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-verdict-availability.json'
MODES = guests.MODES


def available(parent,value,assured):
    """Apply new bad/wonky removals before validating each assurance bit against the actual remaining assignments."""
    after,marks,removed = verdicts.plan(parent,value)
    old = pending(parent[chapter_key(10)],341,1023)
    for core,item in enumerate(old):
        if item is not None and digest(item['guarantee']['report']) in removed: old[core] = None
    anchor = history(parent[chapter_key(3)])[0][-1][0][:32];votes = [0]*341
    # The new Phi does not remove an original active member's assurance eligibility.
    for item in assured:
        assert item['anchor'] == anchor and len(item['bits']) == 43
        assert item['signature'] == guests.signed(item['index'],b'jam_available',digest(anchor+item['bits']))[1]
        bits = int.from_bytes(item['bits'],'little')
        for core in range(341):
            if bits & (1 << core):
                assert old[core] is not None, 'availability/UnassignedCore'
                votes[core] += 1
    released = [item['guarantee']['report'] for core,item in enumerate(old) if item is not None and votes[core] >= 683]
    return after,marks,released


def sealed(parent,assured,value,marks):
    """Commit and sign a complete genuinely invalid assurance/dispute composition without fabricating a posterior."""
    _,_,kind,schedule,_ = tickets.consensus(parent[chapter_key(4)]);assert kind == 1
    author = next(index for index,row in enumerate(guests.roster_records()) if row[:32] == schedule[4])
    raw,commitment = guests.body([],assured,disputes=disputes_wire(value))
    return full.sealed_child(parent,slot=4,body=raw,extrinsic_root=commitment,author=author,secret=author+1,offenders=marks)[0]


def expected_observations(check_frozen=True):
    """Freeze late post-dispute assurance refusals and storage/rollback/checkpoint guest maps for the surviving good report."""
    lines,roots,hashes = [],[],[]
    for mode in MODES:
        initial = guests.original(mode);parent = initial;lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        states = []
        wire,parent = pending_reports.advance(parent,2);states.append(('B',wire,parent,None))
        supplied = pending_reports.reports(parent,initial);wire,parent = pending_reports.advance(parent,3,supplied);states.append(('B',wire,parent,None))
        targets = {item['layout']['core']:digest(item['report']) for item in supplied}
        selected = [verdicts.verdict(parent,targets[0],0,0),verdicts.verdict(parent,targets[339],0,341),verdicts.verdict(parent,targets[340],0,683)]
        value = verdicts.payload(selected,faults=[offenders.fault(1022,targets[340],False)])
        voters = list(range(682))+[1022]
        invalid = guests.assurances(parent,683,indices=voters,cores=(0,340))
        try: available(parent,value,invalid)
        except AssertionError as error: assert str(error) == 'availability/UnassignedCore'
        else: raise AssertionError('independent reference assured a report canceled by this block')
        _,marks,_ = verdicts.plan(parent,value)
        states.append(('R',sealed(parent,invalid,value,marks),parent,'availability/UnassignedCore'))
        assured = guests.assurances(parent,683,indices=voters,cores=(340,))
        after,marks,released = available(parent,value,assured)
        assert released == [supplied[-1]['report']] and marks == [guests.roster_records()[1022][32:64]]
        wire,parent = guests.advance(parent,initial,mode,4,[],assured,supplied[-1],disputes=disputes_wire(value),offenders=marks,posterior_judgments=after)
        states.append(('B',wire,parent,None))
        assert parent[chapter_key(10)] == bytes(341) and [len(group) for group in offenders.judgments(parent[chapter_key(5)])] == [1,1,1,1]
        wire,header,entropy_output,author = pending_reports.sealed(parent,5,[],verdicts.payload(),[])
        parent = full.successor(parent,header,entropy_output,author=author);states.append(('B',wire,parent,None))
        for kind,wire,state,reason in states:
            lines.append(kind+' '+wire.hex()+(' '+reason if reason is not None else ''))
            encoded = checkpoint(list(state.items()));lines.append('O '+encoded.hex())
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=len(MODES),transitions=15,accepted=12,refused=3,
                    pending_fixture_sha256=hashlib.sha256(pending_reports.FIXTURE.read_bytes()).hexdigest(),
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
