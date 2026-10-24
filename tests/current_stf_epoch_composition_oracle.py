# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent composition of supervision, privileged queues and funded lifecycle effects with epoch rotation/restart."""
import hashlib
import importlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_epoch_lifecycle_oracle import foundation
from current_stf_reporting_oracle import body,assurances
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key

FIXTURE=Path(__file__).parent/'fixtures/current-stf-epoch-composition.json'
CASES=(('supervised_storage',0,82),('supervised_storage',2,84),('supervised_storage',3,85),
       ('authorization_assign',0,107),('authorization_assign',2,109),('authorization_assign',5,112),
       ('reserved_creation',0,123),('reserved_creation',3,126),('reserved_creation',5,128),('reserved_creation',7,130),
       ('child_retirement',0,141),('child_retirement',3,144),('child_retirement',5,146),('child_retirement',6,147),
       ('child_recreation',0,148),('child_recreation',3,151),('child_recreation',5,153),('child_recreation',6,154))
SLOTS=(8,9,10,11,12,13)


def expected_observations(check_frozen=True):
    """Calculate108 complete signed maps through tail entry, boundary assurance/rotation and restarted lifecycle publication."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for family,ordinal,mode in CASES:
        source=importlib.import_module('current_stf_'+family+'_oracle');profile=source.PROFILES[ordinal]
        parent=source.original(profile);initial=dict(parent);reports={};budgets={};events=[]
        requests.append('C '+str(mode)+' reload');lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([])
        for slot in SLOTS:
            budget=100000
            gs=[pipeline.guarantee(parent,parent,1,slot,service=99,accumulation_gas=budget)] if slot in (9,11) else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'];budgets[item['report'][:32]]=budget
            ass=assurances(parent,5 if slot in (10,12) else 0,2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (10,12) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False,foundation=foundation(parent,slot))
            if family=='authorization_assign':
                plan['authorization_queues']=parent[chapter_key(2)][:2560]+source.queue() if released and profile in ('assign','checkpoint-panic') else parent[chapter_key(2)]
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                assert len(released)==1
                kwargs=dict(creation_slot=10,retirement_slot=12) if family in ('child_retirement','child_recreation') else {}
                events.append(source.effects(result,parent,profile,slot,budgets[released[0][:32]],**kwargs))
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
        traces.append(dict(family=family,profile=profile,mode=mode,fixture_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),events=events))
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes and fixture['traces']==traces
    return requests,lines,dict(transitions=108,chains=18,roots=roots,checkpoint_sha256=hashes,traces=traces)
