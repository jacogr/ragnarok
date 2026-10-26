# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent late code for actual recreated supervisors, queued old-incarnation reports and selected authority bindings."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_incarnation_authority_oracle as authority
from current_stf_effects_oracle import envelope,simulate,gas_definitions
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata,wire as metadata_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_privileges_oracle import wire as privilege_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-incarnations.json'
SOURCES=(late.FIXTURE,authority.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES


def creator(profile):
    """The original retire/create literal deliberately omits provide28, leaving the honest new child request pending."""
    instructions,memory=authority.programs(profile)[1]
    return instructions[:7]+instructions[-1:],memory


def original(profile):
    """Preserve the actual old77 and incarnation-bound42 authority; replace only creator99's program and its own reservation."""
    services=authority.original(profile);key=chapter_service(255,99)
    old_hash,wide,narrow=metadata(services[key],105);old=services.pop(value_key('P',99,old_hash))
    del services[request_key(99,old_hash,len(old))]
    raw=envelope(*creator(profile));hashed=digest(raw);services[value_key('P',99,hashed)]=raw
    services[request_key(99,hashed,len(raw))]=request_wire((1,));wide=list(wide);wide[4]+=len(raw)-len(old)
    services[key]=metadata_wire((hashed,wide,narrow))
    manager,delegator,registrar,assigners,allowances=late.host.privileges(services[chapter_key(12)],2)
    return late.host.original(services,privilege_wire((manager,delegator,registrar,assigners+[0],allowances)))


def effects(state,parent,profile,slot,invoked):
    """Apply actual creation, common-prior rebind and available foreign-write implications with exact source-owned gas."""
    first,_,third=authority.programs(profile);child=envelope(*third);written=False
    if 99 in invoked:
        assert slot==13
        instructions,_=creator(profile);used=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+458+3855
        if profile!='creator-panic':
            key=chapter_service(255,99);code,wide,narrow=metadata(state[key],105);wide=list(wide);wide[0]+=18
            state[key]=metadata_wire((code,wide,narrow))
            state[chapter_service(255,77)]=metadata_wire((digest(child),(0,0,100,19,81+len(child),0),(2,13,0,99,99,0)))
            state[request_key(77,digest(child),len(child))]=request_wire(())
        late.host.charge(state,99,slot,used,operands=1)
    if 42 in invoked:
        instructions,_=first;used=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+1000*int(profile!='stale')+103*int(profile=='checkpoint-panic')
        if profile not in ('stale','panic'):
            key=chapter_service(255,42);code,wide,narrow=metadata(state[key],105);narrow=list(narrow)
            narrow[4]=77;narrow[5]=metadata(parent[chapter_service(255,77)],105)[2][1]
            state[key]=metadata_wire((code,wide,narrow))
        late.host.charge(state,42,slot,used,operands=1)
    if 77 in invoked:
        available=value_key('P',77,digest(child)) in parent
        instructions,_=third;used=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+2442+(3358+1023)//1024+(216*3+1023)//1024 if available else 0
        key=chapter_service(255,42);code,wide,narrow=metadata(parent[key],105)
        allowed=available and narrow[4]==77 and narrow[5]==metadata(parent[chapter_service(255,77)],105)[2][1]
        if allowed:
            storage=value_key('S',42,b'\7');code,wide,narrow=metadata(state[key],105);wide=list(wide);narrow=list(narrow)
            if storage not in parent:
                wide[4]+=38;narrow[0]+=1 # Only the first authorized selected write reserves the raw namespace key.
            state[storage]=bytes([9,8,7]);state[key]=metadata_wire((code,wide,narrow));written=True
        late.host.charge(state,77,slot,used,operands=1)
    return written


def advance(parent,profile,slot,gs,ass,reports,payloads):
    """Actual old report identities survive recreation, while execution uses prior current code and prior supervisor incarnation."""
    raw,commitment=late.host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """Bind every actual code byte and author statistic independently before selected guest effects."""
        return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    old,released,_,_=late.host.execution.population.validate(parent,slot,gs,ass)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes]
    block,state=late.host.advance(parent,slot,gs,ass,reports,foundation=foundation)
    invoked=[row[0] for wire in selected for row in reports[wire[:32]]['digests']]
    written=effects(state,parent,profile,slot,invoked)
    late.integrate(state,payloads,slot)
    return block,state,dict(slot=slot,invoked=invoked,foreign_write=written,supplied=bool(payloads),
        processed=[wire[:32].hex() for wire in selected],report_codes=[row[1].hex() for wire in selected for row in reports[wire[:32]]['digests'] if row[0]==77])


@owned_histories
def cases():
    """Late child code cannot replay the old skipped77 report or restore stale42 authority; later reports require actual new bindings."""
    result=[]
    for profile in authority.PROFILES:
        for supplied in ((None,) if profile=='creator-panic' else (14,23,24)):
            parent=original(profile);initial=dict(parent);reports={};steps=[];events=[];old_report=None
            for slot in late.host.execution.SLOTS:
                targets=((0,99),(1,77)) if slot==12 else ((0,42),) if slot==13 else ((1,77),) if slot in (23,24) else ()
                gs=[]
                for core,sid in targets:
                    item=late.host.execution.guarantee(parent,core,slot,sid);gs.append(item);reports[item['report'][:32]]=item['layout']
                    if slot==12 and sid==77:old_report=item['report']
                bits={13:1,14:3,24:2,25:2}.get(slot,0)
                votes=2*len(late.host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
                ass=late.host.execution.rotation.assurances(parent,votes,bits) if bits else []
                payloads=((77,envelope(*authority.programs(profile)[2])),) if slot==supplied else ()
                block,state,event=advance(parent,profile,slot,gs,ass,reports,payloads)
                steps.append((block,state,[]));events.append(event);parent=state
            assert old_report is not None
            case=dict(name=profile+'-supply-'+str(supplied),parameters=late.host.parameters(),initial=initial,steps=steps,events=events,old_report=old_report.hex())
            case['inventory'],case['inventory_rows']=declaration(case,(42,77,99),blobs=(envelope(*authority.programs(profile)[2]),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete maps, unchanged old report wires and selected incarnation decisions before native observations."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
