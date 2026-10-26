# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile real-report dispute cancellation, exact report-hash identity and retained good/unrelated assignments."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_verdicts_oracle as verdicts
import jam_fuzzer_full_offenders_oracle as offenders
from current_stf_oracle import Reader,checkpoint,history,tree
from current_stf_reporting_oracle import pending
from current_stf_report_guests_oracle import permutation
from state_layout_oracle import chapter_key,digest
from state_availability_oracle import wire as availability_wire
from state_history_oracle import wire as history_wire
from state_statistics_oracle import parse as statistics_parse,wire as statistics_wire
from disputes_oracle import wire as disputes_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-pending-disputes.json'
REPORT_CORES = (0,339,340)


def reports(parent,initial):
    """Three distinct packages span low/high core encodings and independently signed current assignments."""
    return [guests.guarantee(parent,initial,core=core,label=b'pending-dispute-core'+core.to_bytes(2,'little')) for core in REPORT_CORES]


def sealed(parent,slot,guarantees,value,marks):
    """Seal the exact full body and literal evidence marker, including deliberately refused dispute batches."""
    _,_,kind,schedule,_ = tickets.consensus(parent[chapter_key(4)]);assert kind == 1
    author = next(index for index,row in enumerate(guests.roster_records()) if row[:32] == schedule[slot % 600])
    raw,commitment = guests.body(guarantees,[],disputes=disputes_wire(value))
    wire,entropy_output = full.sealed_child(parent,slot=slot,body=raw,extrinsic_root=commitment,author=author,secret=author+1,offenders=marks)
    return wire,wire[:-len(raw)],entropy_output,author


def advance(parent,slot,guarantees=(),value=None):
    """Cancel only newly bad/wonky complete-report hashes before vacancy, preserve unqualified reports and model every chapter."""
    value = verdicts.payload() if value is None else value
    after,marks,removed = verdicts.plan(parent,value)
    old = pending(parent[chapter_key(10)],341,1023)
    # Full canonical report bytes define a dispute target; package identities never stand in for that digest.
    for core,item in enumerate(old):
        if item is not None and (digest(item['guarantee']['report']) in removed or slot >= item['registered']+5): old[core] = None
    phi = offenders.judgments(after)[3];order = permutation(parent[chapter_key(6)][64:96],1023)
    assert [item['layout']['core'] for item in guarantees] == sorted(set(item['layout']['core'] for item in guarantees))
    # Every authored guarantee has two actual assigned, non-offending current-roster signatures.
    for item in guarantees:
        core = item['layout']['core'];assert 0 <= core < 341 and item['slot'] == slot
        assert old[core] is None, 'assignment/OccupiedCore'
        assert len(item['credentials']) == 2
        for index,signature in item['credentials']:
            assert (order[index]//3+(slot % 600)//10) % 341 == core, 'credential/WrongAssignment'
            assert guests.roster_records()[index][32:64] not in phi, 'credential/InvalidSignature'
            assert signature == guests.signed(index,b'jam_guarantee',digest(item['report']))[1], 'credential/InvalidSignature'
        old[core] = dict(guarantee={key:item[key] for key in ('report','slot','credentials')},registered=slot)
    wire,header,entropy_output,author = sealed(parent,slot,guarantees,value,marks)
    result = full.successor(parent,header,entropy_output,author=author)
    result[chapter_key(5)] = after;result[chapter_key(10)] = availability_wire(old)
    pools = Reader(parent[chapter_key(1)]);queues = parent[chapter_key(2)];rows = []
    for core in range(341):
        row = [pools.take(32) for _ in range(pools.count())]
        for item in guarantees:
            if item['layout']['core'] == core:
                assert item['layout']['authorizer'] in row
                row.remove(item['layout']['authorizer'])
        offset = (core*80+slot % 80)*32
        row = (row+[queues[offset:offset+32]])[-8:];rows.append(natural(len(row))+b''.join(row))
    pools.done();result[chapter_key(1)] = b''.join(rows)
    blocks,peaks = history(result[chapter_key(3)])
    blocks[-1] = (blocks[-1][0],b''.join(sorted(item['layout']['header'][:32]+item['layout']['header'][70:102] for item in guarantees)))
    result[chapter_key(3)] = history_wire((blocks,peaks))
    (current,previous,_,_),_ = statistics_parse(result[chapter_key(13)],(341,1023,1023,2**64-1,2**64-1))
    for index in {index for item in guarantees for index,_ in item['credentials']}:
        row = list(current[index]);row[4] += 1;current[index] = tuple(row)
    core_rows = [[0]*8 for _ in range(341)];activity = {}
    for item in guarantees:
        layout = item['layout'];assert len(layout['digests']) == 1
        load = layout['digests'][0][-1];service = layout['digests'][0][0]
        core_rows[layout['core']][2:] = [*load[1:],int.from_bytes(layout['header'][32:36],'little'),load[0]]
        row = activity.setdefault(service,[service]+[0]*11);row[3] += 1
        for index,amount in enumerate(load,4): row[index] += amount
    result[chapter_key(13)] = statistics_wire((current,previous,core_rows,[tuple(activity[sid]) for sid in sorted(activity)]))
    assert parent[chapter_key(14)] == result[chapter_key(14)] == bytes(600)
    assert parent[chapter_key(15)] == result[chapter_key(15)] == bytes(600)
    return wire,result


def expected_observations(check_frozen=True):
    """Freeze bad/wonky cancellation, good retention, exact package-vs-report identity and complete-map late-fault rollback."""
    lines,roots,hashes = [],[],[]
    for mode in ('classified-reports','package-is-not-report'):
        initial = guests.original('create');parent = initial;lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        states = []
        wire,parent = advance(parent,2);states.append(('B',wire,parent,None))
        supplied = reports(parent,initial);wire,parent = advance(parent,3,supplied);states.append(('B',wire,parent,None))
        targets = {item['layout']['core']:digest(item['report']) for item in supplied}
        assert all(item['report'][:32] != targets[item['layout']['core']] for item in supplied)
        if mode == 'classified-reports':
            selected = [verdicts.verdict(parent,targets[0],0,0),verdicts.verdict(parent,targets[339],0,341),verdicts.verdict(parent,targets[340],0,683)]
            invalid = verdicts.payload(selected)
            try: verdicts.plan(parent,invalid)
            except AssertionError as error: assert str(error) == 'MissingFault'
            else: raise AssertionError('independent reference admitted good verdict without fault')
            wire,_,_,_ = sealed(parent,4,[],invalid,[]);states.append(('R',wire,parent,'MissingFault'))
            valid = verdicts.payload(selected,faults=[offenders.fault(1022,targets[340],False)])
            wire,parent = advance(parent,4,value=valid);states.append(('B',wire,parent,None))
            remaining = pending(parent[chapter_key(10)],341,1023)
            assert [core for core,item in enumerate(remaining) if item is not None] == [340]
            assert remaining[340]['guarantee']['report'] == supplied[-1]['report'] and remaining[340]['registered'] == 3
            wire,parent = advance(parent,5);states.append(('B',wire,parent,None))
        else:
            wrong_identity = verdicts.payload([verdicts.verdict(parent,supplied[0]['report'][:32],0,0)])
            wire,parent = advance(parent,4,value=wrong_identity);states.append(('B',wire,parent,None))
            assert sum(item is not None for item in pending(parent[chapter_key(10)],341,1023)) == 3
            valid = verdicts.payload([verdicts.verdict(parent,targets[0],0,0)])
            wire,parent = advance(parent,5,value=valid);states.append(('B',wire,parent,None))
            assert [core for core,item in enumerate(pending(parent[chapter_key(10)],341,1023)) if item is not None] == [339,340]
        wire,parent = advance(parent,8);states.append(('B',wire,parent,None))
        assert parent[chapter_key(10)] == bytes(341) # Exact five-slot expiry removes the still-unqualified good/unrelated assignments.
        for kind,wire,state,reason in states:
            lines.append(kind+' '+wire.hex()+(' dispute/'+reason if reason is not None else ''))
            encoded = checkpoint(list(state.items()));lines.append('O '+encoded.hex())
            roots[-1].append(tree(list(state.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=2,transitions=sum(map(len,roots)),accepted=10,refused=1,report_cores=list(REPORT_CORES),
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    verdict_fixture_sha256=hashlib.sha256(verdicts.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
