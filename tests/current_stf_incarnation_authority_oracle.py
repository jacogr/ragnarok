# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map actual supervisor retirement/recreation and later incarnation-bound authority cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-incarnation-authority.json'
PROFILES = ('stale','rebind','panic','checkpoint-panic','creator-panic')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire
from current_stf_supervised_storage_oracle import program as foreign_program


def programs(profile):
    """The old77 is retired and recreated with real foreign-write code;42 must explicitly bind the new incarnation later."""
    child_instructions,child_memory=foreign_program('write');child=envelope(child_instructions,child_memory)
    if profile=='stale':
        first=[bytes([50,0])];memory42=b''
    else:
        first=[immediate(7,2**64-1),immediate(8,77),bytes([10,29])];memory42=b''
        if profile=='checkpoint-panic':
            first.append(bytes([10,19])) # Keep the exact new supervisor creation slot despite the later panic.
        first.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    memory99=digest(child)+len(child).to_bytes(4,'little')+(100).to_bytes(8,'little')+(19).to_bytes(8,'little')+bytes(8)+child
    second=[immediate(7,77),bytes([10,23]),immediate(7,2**64-1),immediate(8,77),immediate(9,0),immediate(10,196608),bytes([10,20]),
            immediate(7,77),immediate(8,196668),immediate(9,len(child)),bytes([10,28]),b'\0' if profile=='creator-panic' else bytes([50,0])]
    return (first,memory42),(second,memory99),(child_instructions,child_memory)


def original(profile):
    """Old empty77 genuinely exists at creation0 and supervises42; no future-incarnation metadata is fabricated."""
    parent=transfers.original('halt')
    for sid,(instructions,memory) in zip((42,99),programs(profile)[:2]):
        key=chapter_service(255,sid);old_hash,wide,narrow=account_parse(parent[key],105)
        old=parent.pop(value_key('P',sid,old_hash));del parent[request_key(sid,old_hash,len(old))]
        raw=envelope(instructions,memory);hashed=digest(raw);parent[value_key('P',sid,hashed)]=raw
        parent[request_key(sid,hashed,len(raw))]=request_wire((1,));wide,narrow=list(wide),list(narrow);wide[4]+=len(raw)-len(old)
        if sid==42:
            narrow[4]=77;narrow[5]=0 # This is the actual old supervisor incarnation, before any recreation.
        parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_service(255,77)]=account_wire((bytes(32),(7,11,0,0,0,0),(0,0,0,99,99,0)))
    parent[chapter_key(12)]=privileges_wire((0,0,99,[0,0],[]));return parent


def effects(result,parent,profile,slot):
    """Common prior authority refuses77 at6; only a retained explicit rebind permits the later foreign write at8."""
    first,second,third=programs(profile);child=envelope(*third);gas={};changed=False
    if slot==4:
        instructions,_=second;gas[99]=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+458+3855+3980+(2264*len(child)+1023)//1024
        if profile!='creator-panic':
            key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105);wide=list(wide);wide[0]+=18
            result[key]=account_wire((code,wide,narrow))
            result[chapter_service(255,77)]=account_wire((digest(child),(0,0,100,19,81+len(child),0),(2,4,0,99,99,0)))
            result[request_key(77,digest(child),len(child))]=request_wire((4,));result[value_key('P',77,digest(child))]=child
    if slot==6:
        instructions,_=first;gas[42]=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+1000*int(profile!='stale')+103*int(profile=='checkpoint-panic')
        if profile not in ('stale','panic'):
            key=chapter_service(255,42);code,wide,narrow=account_parse(parent[key],105);narrow=list(narrow)
            narrow[4]=77;narrow[5]=account_parse(parent[chapter_service(255,77)],105)[2][1]
            result[key]=account_wire((code,wide,narrow)) # Original42 self authority is valid after the actual old77 incarnation disappears.
    if slot in (6,8):
        code_ready=profile!='creator-panic';instructions,_=third
        gas[77]=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+2442+(3358+1023)//1024+(216*3+1023)//1024 if code_ready else 0
        key=chapter_service(255,42);code,wide,narrow=account_parse(parent[key],105);current77=account_parse(parent[chapter_service(255,77)],105)[2][1]
        allowed=code_ready and narrow[4]==77 and narrow[5]==current77
        if allowed:
            storage=value_key('S',42,b'\7');wide,narrow=list(wide),list(narrow)
            if storage not in parent:
                wide[4]+=38;narrow[0]+=1 # The actual later authorized write reserves the raw key exactly once.
            result[storage]=bytes([9,8,7]);result[key]=account_wire((code,wide,narrow));changed=True
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT);activity={row[0]:list(row) for row in services}
    for sid,used in sorted(gas.items()):
        key=chapter_service(255,sid);code,wide,narrow=account_parse(result[key],105);narrow=list(narrow);narrow[2]=slot
        result[key]=account_wire((code,wide,narrow));row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=1;row[11]+=used
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,foreign_write=changed,supervisor_created=account_parse(result[chapter_service(255,42)],105)[2][5])


def expected_observations(check_frozen=True):
    """Calculate40 full transitions with genuine old/new77 namespaces, simultaneous rebind/write and a later authorized retry."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={}
        requests.append('C '+str(index+171));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in range(2,10):
            targets=((1,99),) if slot==3 else (((0,42),(1,77)) if slot==5 else (((1,77),) if slot==7 else ()))
            gs=[pipeline.guarantee(parent,initial,core,slot,service=sid,accumulation_gas=100000) for core,sid in targets]
            for item in gs:
                reports[item['report'][:32]]=item['layout'] # All77 reports use the actual current metadata code hash, including the honest zero/missing control.
            ass=assurances(parent,5 if slot in (4,6,8) else 0,3 if slot==6 else 2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4,6,8) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False)
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                traces[-1].append(effects(result,parent,profile,slot))
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text());assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes and fixture['traces']==json.loads(json.dumps(traces))
    return requests,lines,dict(transitions=40,chains=5,roots=roots,checkpoint_sha256=hashes,traces=traces)
