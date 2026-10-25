# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map scheduled manager takeover and actual allowance revocation cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-allowance-revocation.json'
PROFILES = ('revoke','panic','checkpoint-panic','retain-self','unauthorized')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire


def programs(profile):
    """The original manager installs42's free allowance;42's own later invocation either revokes it or keeps its authority."""
    first=[immediate(7,99 if profile=='unauthorized' else 42),immediate(8,196608),immediate(9,0),immediate(10,0),immediate(11,196616),immediate(12,1),bytes([10,16]),bytes([50,0])]
    keep=profile=='retain-self';memory=bytes(8)+(42).to_bytes(4,'little')+(6000).to_bytes(8,'little')
    second=[immediate(7,42 if keep else 99),immediate(8,196608),immediate(9,0),immediate(10,0),immediate(11,196616),immediate(12,int(keep)),bytes([10,16])]
    if profile=='checkpoint-panic':
        second.append(bytes([10,19])) # Capture the actual empty dictionary and manager return before panic.
    second.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return (first,memory),(second,memory)


def original(profile):
    """Both literal programs and original manager99 are committed before signing; no original free execution exists."""
    parent=transfers.original('halt')
    for sid,(instructions,memory) in zip((99,42),programs(profile)):
        key=chapter_service(255,sid);old_hash,wide,narrow=account_parse(parent[key],105)
        old=parent.pop(value_key('P',sid,old_hash));del parent[request_key(sid,old_hash,len(old))]
        raw=envelope(instructions,memory);hashed=digest(raw)
        parent[value_key('P',sid,hashed)]=raw;parent[request_key(sid,hashed,len(raw))]=request_wire((1,))
        wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((99,0,0,[0,0],[]));return parent


def effects(result,parent,profile,slot,report):
    """Original manager selection governs simultaneous outputs, while the original free dictionary alone schedules42."""
    prior=parent[chapter_key(12)];manager=int.from_bytes(prior[:4],'little');assert prior[20] in (0,1)
    free42=bool(prior[20]);(first,_),(second,_)=programs(profile)
    gas99=simulate(first,gas_definitions(),prefix=[b'\0']*5)[0]+442
    gas42=simulate(second,gas_definitions(),prefix=[b'\0']*5)[0]+422+20*int(profile=='retain-self')+103*int(profile=='checkpoint-panic')
    if manager==99 and report:
        result[chapter_key(12)]=privileges_wire((99 if profile=='unauthorized' else 42,0,0,[0,0],[(42,6000)]))
    elif manager==42 and free42 and profile!='panic':
        keep=profile=='retain-self';result[chapter_key(12)]=privileges_wire((42 if keep else 99,0,0,[0,0],[(42,6000)] if keep else []))
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services}
    for sid,active,gas,count in ((42,free42,gas42,0),(99,report,gas99,int(report))):
        if not active:
            continue # Revoking the dictionary prevents later free participation without erasing this invocation's actual gas.
        key=chapter_service(255,sid);code,wide,narrow=account_parse(parent[key],105);narrow=list(narrow);narrow[2]=slot
        result[key]=account_wire((code,wide,narrow));row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=count;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,manager_before=manager,manager_after=int.from_bytes(result[chapter_key(12)][:4],'little'),free42=free42,gas42=gas42*int(free42),gas99=gas99*int(report))


def expected_observations(check_frozen=True):
    """Calculate30 complete maps through delayed manager takeover, revocation and fresh report-driven reauthorization."""
    requests,lines,roots,hashes,traces=[],[],[],[],[];pipeline=transfers.pipeline
    for index,profile in enumerate(PROFILES):
        parent=original(profile);initial=dict(parent);reports={}
        requests.append('C '+str(index+161));lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([]);traces.append([])
        for slot in range(2,8):
            gs=[pipeline.guarantee(parent,initial,1,slot,service=99,accumulation_gas=100000)] if slot in (3,5) else []
            for item in gs:
                reports[item['report'][:32]]=item['layout'] # Preserve exact independently signed admission/statistics inputs.
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
    return requests,lines,dict(transitions=30,chains=5,roots=roots,checkpoint_sha256=hashes,traces=traces)
