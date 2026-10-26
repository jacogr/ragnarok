# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full683-judgment verdicts, good/bad/wonky classification, opposing faults and exact atomic refusals."""
import copy
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_offenders_oracle as offenders
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_profile_oracle as full
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key,digest
from disputes_oracle import wire as disputes_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-verdicts.json'
TARGETS = {name:digest(('full-current verdict '+name).encode()) for name in ('good','bad','wonky')}


def payload(verdicts=(),*,culprits=(),faults=()):
    """Keep strict independent report/key ordering while preserving repeated evidence keys across sections."""
    value = offenders.payload(culprits=culprits,faults=faults)
    value['verdicts'] = sorted(verdicts,key=lambda row:row['target'])
    return value


def vote(index,ordinal,valid,target):
    """Bind one actual selected-roster ordinal and vote domain to an independently signed raw report hash."""
    return dict(index=ordinal,vote=valid,signature=guests.signed(index,b'jam_valid' if valid else b'jam_invalid',target)[1])


def verdict(parent,target,age,positives,*,count=None):
    """Choose a strict selected-population quorum including the highest available ordinal, retaining NULL positions in the population size."""
    epoch = int.from_bytes(parent[chapter_key(11)],'little')//600
    members = offenders.roster(parent[chapter_key(8 if age == epoch else 9)])
    quorum = 2*(len(members)//3)+1 if count is None else count
    indices = [index for index,row in enumerate(members) if row[32:64] in offenders.identities()]
    assert 1 <= quorum <= len(indices) and 0 <= positives <= quorum
    selected = indices[:quorum-1]+indices[-1:]
    assert len(set(selected)) == quorum
    votes = [vote(offenders.identities()[members[index][32:64]],index,position < positives,target) for position,index in enumerate(selected)]
    return dict(target=target,age=age,votes=votes)


def plan(parent,value,marker=None):
    """Apply parent-epoch populations, exact quorums/splits, signatures, posterior evidence and mandatory opposing faults."""
    groups = offenders.judgments(parent[chapter_key(5)])
    epoch = int.from_bytes(parent[chapter_key(11)],'little')//600
    active,previous = (offenders.roster(parent[chapter_key(chapter)]) for chapter in (8,9))
    good,removed = [],[]
    assert [row['target'] for row in value['verdicts']] == sorted(set(row['target'] for row in value['verdicts']))
    # Verdict selection precedes Safrole rotation; the incoming block's epoch cannot resize this quorum.
    for item in value['verdicts']:
        assert item['age'] == epoch or epoch > 0 and item['age'] == epoch-1, 'InvalidEpoch'
        members = active if item['age'] == epoch else previous;quorum = 2*(len(members)//3)+1
        assert len(item['votes']) == quorum, 'InvalidQuorum'
        assert all(item['target'] not in group for group in groups[:3]), 'AlreadyJudged'
        assert [row['index'] for row in item['votes']] == sorted(set(row['index'] for row in item['votes']))
        positive = 0
        for row in item['votes']:
            assert 0 <= row['index'] < len(members), 'InvalidKey'
            key = members[row['index']][32:64];domain = b'jam_valid' if row['vote'] else b'jam_invalid'
            assert key in offenders.identities() and row['signature'] == guests.signed(offenders.identities()[key],domain,item['target'])[1], 'InvalidSignature'
            positive += row['vote']
        assert positive in (0,quorum,len(members)//3), 'InvalidSplit'
        kind = 0 if positive == quorum else 1 if positive == 0 else 2
        groups[kind].append(item['target']);(good if kind == 0 else removed).append(item['target'])
    working = dict(parent);working[chapter_key(5)] = offenders.encoded(groups)
    after,marks = offenders.plan(working,offenders.payload(culprits=value['culprits'],faults=value['faults']),marker)
    # Every new good classification needs actual opposing fault evidence in this same complete extrinsic.
    assert all(target in {row['target'] for row in value['faults']} for target in good), 'MissingFault'
    return after,marks,removed


def advance(parent,slot,value,*,marker=None):
    """Author the complete signed verdict body and every posterior map without pending-report projections in this family."""
    assert parent[chapter_key(10)] == bytes(341) # Pending-report cancellation is a later composed family, not an inferred answer here.
    after,marks,_ = plan(parent,value,marker)
    raw = disputes_wire(value);wire,entropy_output,author = tickets.sealed(parent,slot,[],disputes=raw,offenders=marks)
    header = wire[:-(4+len(raw))]
    result = full.successor(parent,header,entropy_output,author=author);result[chapter_key(5)] = after
    return wire,result


def expected_observations(check_frozen=True):
    """Freeze three full classifications and exact quorum/split/epoch/signature/fault/repetition refusals before replay."""
    parent = guests.original('create');lines = ['P '+checkpoint(list(parent.items())).hex()];roots,hashes = [[]],[[]]
    selected = {name:verdict(parent,target,0,{'good':683,'bad':0,'wonky':341}[name]) for name,target in TARGETS.items()}
    valid = payload(selected.values(),faults=[offenders.fault(1022,TARGETS['good'],False)])
    quorum = copy.deepcopy(valid);quorum['verdicts'][0]['votes'].pop()
    split = copy.deepcopy(valid);item = next(row for row in split['verdicts'] if row['target'] == TARGETS['wonky'])
    old = item['votes'][341];item['votes'][341] = vote(old['index'],old['index'],True,item['target'])
    age = copy.deepcopy(valid);age['verdicts'][0]['age'] = 1
    signature = copy.deepcopy(valid);row = signature['verdicts'][0]['votes'][0]
    row['signature'] = row['signature'][:-1]+bytes([row['signature'][-1]^1])
    missing = payload(selected.values())
    events = [(2,value,reason) for value,reason in ((quorum,'InvalidQuorum'),(split,'InvalidSplit'),(age,'InvalidEpoch'),
               (signature,'InvalidSignature'),(missing,'MissingFault'))]+[(2,valid,None),
              (3,payload([selected['good']],faults=valid['faults']),'AlreadyJudged'),(3,payload(),None)]
    for slot,value,reason in events:
        if reason is not None:
            try: plan(parent,value)
            except AssertionError as error: assert str(error) == reason
            else: raise AssertionError('independent reference admitted invalid verdicts')
            marks = [row['key'] for section in ('culprits','faults') for row in value[section]]
            wire,_,_ = tickets.sealed(parent,slot,[],disputes=disputes_wire(value),offenders=marks)
            lines.append('R '+wire.hex()+' dispute/'+reason)
        else:
            wire,parent = advance(parent,slot,value);lines.append('B '+wire.hex())
        encoded = checkpoint(list(parent.items()));lines.append('O '+encoded.hex())
        roots[0].append(tree(list(parent.items()))[0].hex());hashes[0].append(hashlib.sha256(encoded).hexdigest())
    assert [len(group) for group in offenders.judgments(parent[chapter_key(5)])] == [1,1,1,1]
    evidence = dict(graypaper_commit=full.GP,chains=1,transitions=len(events),accepted=2,refused=6,
                    verdicts=3,quorum=683,judgments=2049,positive_counts=[683,0,341],
                    full_guests_sha256=hashlib.sha256(guests.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
