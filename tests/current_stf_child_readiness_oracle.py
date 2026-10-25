# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map public child creation, same-invocation code provision and later executable readiness cases."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-child-readiness.json'
PROFILES = ('provide','panic','checkpoint-before-provide','checkpoint-after-provide','unknown-target')
PAYLOAD = b'R'


from current_stf_service_creation_oracle import creation_ids
from current_stf_service_upgrades_oracle import replacement


def program(profile):
    """Save the returned public child ID in r6 across checkpoint19, then provide its actual halt-code bytes."""
    target=replacement();memory=digest(target)+len(target).to_bytes(4,'little')+(100).to_bytes(8,'little')+(19).to_bytes(8,'little')+bytes(8)+target
    instructions=[immediate(7,2**64-1),immediate(8,2**64-1),immediate(9,0),immediate(10,196608),bytes([10,20]),bytes([100,0x76])]
    if profile=='checkpoint-before-provide':
        instructions.append(bytes([10,19])) # This implication contains the child but no queued code provision.
    instructions += [bytes([100,0x67]),immediate(8,196668),immediate(9,len(target))]
    if profile=='unknown-target':
        instructions.append(immediate(7,77)) # A genuine missing-target WHO cannot satisfy the new child's request.
    instructions.append(bytes([10,28]))
    if profile=='checkpoint-after-provide':
        instructions.append(bytes([10,19])) # Child and queued code pair are retained together.
    instructions.append(b'\0' if profile in ('panic','checkpoint-before-provide','checkpoint-after-provide') else bytes([50,0]))
    return instructions,memory


def original(profile):
    """Only the creator's literal code identity changes; child namespaces do not exist in any original."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    return parent


def effects(result,parent,profile,slot,budget,child=None, *, creation_slot=4, execution_slots=(6,), statistics_config=DEFAULT):
    """Creation/provision terminal selection determines whether a later real child report can execute current code."""
    target=replacement();provided=profile in ('provide','checkpoint-after-provide')
    if slot==creation_slot:
        child=creation_ids(result,slot,1)[0]
        instructions,_=program(profile)
        gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+3855+3980+(2264*len(target)+1023)//1024+103*int(profile.startswith('checkpoint-'))
        if profile!='panic':
            result[chapter_service(255,child)]=account_wire((digest(target),(0,0,100,19,81+len(target),0),(2,slot,0,99,99,0)))
            result[request_key(child,digest(target),len(target))]=request_wire((slot,)) if provided else request_wire(())
            if provided:
                result[value_key('P',child,digest(target))]=target # Final fnprovide sees the newly published child's still-relevant request.
        else:
            child=None # Ordinary creation and queued code vanish together on uncheckpointed panic.
        service=99
    else:
        assert slot in execution_slots and child is not None
        service=child;gas=22 if provided else 0 # N1/G0 remains honest for a created but not yet code-ready account.
    assert gas<=budget
    key=chapter_service(255,service);code,wide,narrow=account_parse(result[key],105)
    narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],statistics_config)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(service,[service]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,service=service,child=child,code_ready=provided and child is not None)


def expected_observations(check_frozen=True):
    """Calculate thirty complete transitions, including genuine follow-up reports only for retained public children."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={};budgets={};child_id=None
        requests.append('C '+str(index+131));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in range(2,8):
            budget=100000;service=99 if slot==3 else child_id
            gs=[pipeline.guarantee(parent,initial,1,slot,service=service,accumulation_gas=budget)] if slot==3 or slot==5 and child_id is not None else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'];budgets[item['report'][:32]]=budget
            ass=assurances(parent,5 if slot==4 or slot==6 and child_id is not None else 0,2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4,6) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False)
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                assert len(released)==1
                event=effects(result,parent,profile,slot,budgets[released[0][:32]],child_id);traces[-1].append(event);child_id=event['child']
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes and fixture['traces']==traces
    return requests,lines,dict(transitions=30,chains=5,roots=roots,checkpoint_sha256=hashes,traces=traces)
