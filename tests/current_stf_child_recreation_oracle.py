# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map funded reserved-ID retirement and fresh incarnation recreation cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-child-recreation.json'
PROFILES = ('liquid-liquid','protected-liquid','liquid-protected','protected-protected','panic','checkpoint-before-recreate','checkpoint-after-recreate')
PAYLOAD = b'R'


from current_stf_service_upgrades_oracle import replacement
from state_privileges_oracle import wire as privileges_wire


def program(profile):
    """After real cleanup/eject, recreate the same reserved ID with distinct minima and a fresh code reservation."""
    target=replacement();memory=digest(target)+len(target).to_bytes(4,'little')+(100).to_bytes(8,'little')+(19).to_bytes(8,'little')+bytes(8)
    memory+=digest(target)+len(target).to_bytes(4,'little')+(200).to_bytes(8,'little')+(39).to_bytes(8,'little')+bytes(8)
    mode=PROFILES.index(profile) if profile in PROFILES[:4] else 0
    instructions=[immediate(7,2**64-1),immediate(8,77),immediate(9,mode),immediate(10,196608),bytes([10,20]),
                  immediate(7,77),immediate(8,196608),immediate(9,len(target)),bytes([10,26]),immediate(7,77),bytes([10,23])]
    if profile=='checkpoint-before-recreate':
        instructions.append(bytes([10,19])) # Retain deletion/refund while discarding later recreation/debit.
    instructions += [immediate(7,2**64-1),immediate(8,77),immediate(9,mode),immediate(10,196668),bytes([10,20])]
    if profile=='checkpoint-after-recreate':
        instructions.append(bytes([10,19])) # Retain the new incarnation and its new pending reservation.
    instructions.append(b'\0' if profile in ('panic','checkpoint-before-recreate','checkpoint-after-recreate') else bytes([50,0]))
    return instructions,memory


def original(profile):
    """Fund both originals and commit registrar99 before signing under the explicit7/1/100 deposit schedule."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old)
    if profile in ('protected-liquid','protected-protected'):
        wide[0]=0;wide[1]=1000000
    parent[key]=account_wire((hashed,wide,narrow))
    code,wide,narrow=account_parse(parent[chapter_service(255,42)],105);wide=list(wide);wide[0]=10000
    parent[chapter_service(255,42)]=account_wire((code,wide,narrow));parent[chapter_key(12)]=privileges_wire((0,0,99,[0,0],[]))
    return parent


def effects(result,parent,profile,slot,budget,*,creation_slot=4,retirement_slot=6):
    """The old empty incarnation retires at the explicit later slot; fresh metadata/Q and a second funding debit replace it atomically."""
    key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105);wide,narrow=list(wide),list(narrow)
    child=chapter_service(255,77);kept=profile!='panic';retired=slot==retirement_slot and kept
    recreated=retired and profile!='checkpoint-before-recreate'
    mode=PROFILES.index(profile) if profile in PROFILES[:4] else 0
    source=1 if mode in (1,3) else 0;pools=(224,0) if mode in (0,1) else (0,224)
    if slot==creation_slot and kept:
        wide[source]-=224
        result[child]=account_wire((digest(replacement()),(*pools,100,19,0,0),(0,creation_slot,0,99,99,0)))
    if retired:
        assert child in parent
        result.pop(child);wide[0]+=224
    if recreated:
        wide[source]-=224
        result[child]=account_wire((digest(replacement()),(*pools,200,39,110,0),(2,retirement_slot,0,99,99,0)))
        result[request_key(77,digest(replacement()),len(replacement()))]=request_wire(())
    narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    instructions,_=program(profile)
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+2*3855+3250+458+103*int(profile.startswith('checkpoint-'))
    assert gas<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(99,[99]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,retired=retired,recreated=recreated,child_present=child in result)


def expected_observations(check_frozen=True):
    """Calculate forty-two signed transitions through actual reserved-ID retirement/recreation with four funding pools."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={};budgets={}
        requests.append('C '+str(index+148));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in range(2,8):
            budget=100000
            gs=[pipeline.guarantee(parent,initial,1,slot,service=99,accumulation_gas=budget)] if slot in (3,5) else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'];budgets[item['report'][:32]]=budget
            ass=assurances(parent,5 if slot in (4,6) else 0,2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4,6) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False)
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                assert len(released)==1
                traces[-1].append(effects(result,parent,profile,slot,budgets[released[0][:32]]))
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes and fixture['traces']==traces
        assert fixture['deposits']==dict(per_item=7,per_byte=1,per_account=100)
    return requests,lines,dict(transitions=42,chains=7,roots=roots,checkpoint_sha256=hashes,traces=traces)
