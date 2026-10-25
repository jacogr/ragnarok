# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map strict preimage aging, restoration and selected full-map deletion cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-preimage-aging.json'
PROFILES = ('expire','restore','live','panic','checkpoint-panic')
PAYLOAD = b'R'


from state_requests_oracle import parse as request_parse
from current_stf_epoch_lifecycle_oracle import foundation

SLOTS = (4799,4800,4801,4802,4803,4804)
EXPUNGE = 4800 # Explicit maxLookupAnchorAge0 plus the pinned safety margin4800.


def program(profile):
    """Forget at exact expiry and later strictly past expiry; restoration first appends the actual invocation time."""
    operations=(25,26) if profile=='restore' else (26,)
    instructions=[]
    for operation in operations:
        instructions += [immediate(7,2**64-1),immediate(8,196608),immediate(9,1),bytes([10,operation])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Retain the precise forgotten namespace version on panic.
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,digest(PAYLOAD),operations


def original(profile):
    """An honestly stored R preimage starts available or removed at1; its request and reservation predate every release."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory,_=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    parent[value_key('P',99,digest(PAYLOAD))]=PAYLOAD
    parent[request_key(99,digest(PAYLOAD),1)]=request_wire((0,) if profile=='live' else (0,1))
    wide,narrow=list(wide),list(narrow);wide[4]+=len(raw)-len(old)+82;narrow[0]+=2
    parent[key]=account_wire((hashed,wide,narrow));return parent


def effects(result,parent,profile,slot,budget,*,lookup_age=0):
    """Use widened integer strict age equations; only expired two-slot removal releases the entire82-byte/two-item reservation."""
    key=request_key(99,digest(PAYLOAD),1);before=None if key not in parent else request_parse(parent[key],(3,13))[0]
    after=before;deleted=False
    if profile!='panic' and before is not None:
        if profile=='restore' and len(after)==2:
            after=after+(slot,) # Solicit restores an unavailable history even at the exact expiry boundary.
        if len(after)==1:
            after=after+(slot,)
        elif len(after) in (2,3) and after[1]+EXPUNGE+lookup_age<slot:
            if len(after)==2:
                after=None;deleted=True
            else:
                after=(after[2],slot) # A restored preimage keeps its bytes and reservation when compacted.
    if after is None:
        result.pop(key,None)
        if deleted: result.pop(value_key('P',99,digest(PAYLOAD)),None)
    else: result[key]=request_wire(after)
    account=chapter_service(255,99);code,wide,narrow=account_parse(parent[account],105)
    wide,narrow=list(wide),list(narrow);wide[4]-=82*int(deleted);narrow[0]-=2*int(deleted);narrow[2]=slot
    result[account]=account_wire((code,wide,narrow))
    instructions,_,operations=program(profile)
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+sum({25:2193,26:3250}[op] for op in operations)+103*int(profile=='checkpoint-panic')
    assert gas<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(99,[99]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,before=before,after=after,deleted=deleted,footprint_delta=-82*int(deleted))


def expected_observations(check_frozen=True):
    """Calculate thirty signed transitions across a real epoch jump and two exact aging-boundary releases."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={};budgets={}
        requests.append('C '+str(index+136));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in SLOTS:
            budget=100000
            gs=[pipeline.guarantee(parent,parent,1,slot,service=99,accumulation_gas=budget)] if slot in (4800,4802) else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'];budgets[item['report'][:32]]=budget
            ass=assurances(parent,5 if slot in (4801,4803) else 0,2)
            released=[item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4801,4803) else []
            plan=dict(available=released,processed=released,batches=[],ready=[[] for _ in range(12)],reports=reports,yielded=False,foundation=foundation(parent,slot))
            wire,result=pipeline.advance(parent,initial,'create',slot,gs,ass,plan=plan)
            if released:
                assert len(released)==1
                traces[-1].append(effects(result,parent,profile,slot,budgets[released[0][:32]]))
            parent=result;encoded=checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs,ass)[0].hex());lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture=json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256']==hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots']==roots and fixture['successor_checkpoint_sha256']==hashes
        assert fixture['traces']==json.loads(json.dumps(traces))
        assert fixture['max_lookup_anchor_age']==0
    return requests,lines,dict(transitions=30,chains=5,roots=roots,checkpoint_sha256=hashes,traces=traces)
