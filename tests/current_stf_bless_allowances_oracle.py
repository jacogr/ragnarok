# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map nonempty bless allowance publication and later always-accumulate scheduling cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-bless-allowances.json'
PROFILES = ('publish','panic','checkpoint-panic','identical-pairs','unsorted-pairs','unauthorized')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire


def pairs(profile):
    """Raw ordered input is distinct from the canonical dictionary; duplicate identical pairs still pay the raw-item price."""
    return [(99,6000),(42,100)] if profile=='unsorted-pairs' else [(42,100)]*(2 if profile=='identical-pairs' else 1)


def program(profile):
    """Bless preserves manager99 while replacing the entire allowance dictionary with literal E4/E8 input pairs."""
    raw=pairs(profile);memory=bytes(8)+b''.join(sid.to_bytes(4,'little')+gas.to_bytes(8,'little') for sid,gas in raw)
    instructions=[immediate(7,99),immediate(8,196608),immediate(9,0),immediate(10,0),immediate(11,196616),immediate(12,len(raw)),bytes([10,16])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Only this selected prefix keeps nonempty allowances after panic.
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,memory


def original(profile):
    """Every original has an empty allowance dictionary, so publication cannot schedule its new members in the same invocation."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((42 if profile=='unauthorized' else 99,0,0,[0,0],[]))
    return parent


def effects(result,parent,profile,slot,report):
    """Initial-block allowances select participants; newly blessed entries start with the next block, with zero report operands."""
    retained=profile not in ('panic','unauthorized');prior=slot>4 and retained
    active42=prior;active99=report or prior and profile=='unsorted-pairs'
    instructions,_=program(profile);gas99=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+422+20*len(pairs(profile))+103*int(profile=='checkpoint-panic')
    if active99 and retained:
        result[chapter_key(12)]=privileges_wire((99,0,0,[0,0],sorted(set(pairs(profile)))))
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services}
    for sid,active,gas,count in ((42,active42,22,0),(99,active99,gas99,int(report))):
        if not active:
            continue # An output allowance alone cannot create same-block participation.
        key=chapter_service(255,sid);code,wide,narrow=account_parse(parent[key],105);narrow=list(narrow);narrow[2]=slot
        result[key]=account_wire((code,wide,narrow));row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=count;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,report=report,active42=active42,active99=active99,gas42=22*int(active42),gas99=gas99*int(active99))


def expected_observations(check_frozen=True):
    """Calculate36 complete signed transitions through actual dictionary replacement and next-block free execution."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={}
        requests.append('C '+str(index+155));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in range(2,8):
            gs=[pipeline.guarantee(parent,initial,1,slot,service=99,accumulation_gas=100000)] if slot in (3,5) else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'] # Actual report bytes own the independent layout used for admission/statistics.
            ass=assurances(parent,5 if slot in (4,6) else 0,2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4,6) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False)
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            traces[-1].append(effects(result,parent,profile,slot,bool(released)))
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes and fixture['traces']==traces
    return requests,lines,dict(transitions=36,chains=6,roots=roots,checkpoint_sha256=hashes,traces=traces)
