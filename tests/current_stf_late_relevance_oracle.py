# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent prior admission versus posterior relevance of a code extrinsic under selected foreign request effects."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_supervised_requests_oracle as requests
from current_stf_effects_oracle import immediate,envelope,simulate,gas_definitions
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata,wire as metadata_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_privileges_oracle import wire as privilege_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-relevance.json'
SOURCES=(late.FIXTURE,requests.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES
PROFILES=('forget','forget-panic','forget-checkpoint-panic','forget-checkpoint-solicit-panic','forget-solicit-checkpoint-panic')


def target_code():
    """The exact authored halt preimage already qualified by the original service pipeline."""
    state=requests.transfers.original('halt')
    code,_,_=metadata(state[chapter_service(255,42)],105)
    return state[value_key('P',42,code)]


def program(profile):
    """Literal foreign forget/solicit operations address the real target code identity and reset registers per call."""
    operations={'forget':(26,),'forget-panic':(26,),'forget-checkpoint-panic':(26,19),
        'forget-checkpoint-solicit-panic':(26,19,25),'forget-solicit-checkpoint-panic':(26,25,19)}[profile]
    instructions=[]
    for operation in operations:
        if operation==19:
            instructions.append(bytes([10,19])) # Exceptional selection retains the precise request version at this point.
        else:
            instructions.extend((immediate(7,42),immediate(8,196608),immediate(9,len(target_code())),bytes([10,operation])))
    instructions.append(bytes([50,0]) if profile=='forget' else b'\0')
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+sum({26:3250,25:2193,19:103}[item] for item in operations)
    return envelope(instructions,digest(target_code())),gas


def original(profile):
    """Keep the pending code reservation, remove only its payload and authorize99 to edit42's requests."""
    services=requests.transfers.original('halt');target=chapter_service(255,42)
    code,wide,narrow=metadata(services[target],105);narrow=list(narrow);narrow[4]=99;narrow[5]=0
    services[target]=metadata_wire((code,wide,narrow));del services[value_key('P',42,code)]
    services[request_key(42,code,len(target_code()))]=request_wire(())
    source=chapter_service(255,99);old_hash,wide,narrow=metadata(services[source],105)
    old=services.pop(value_key('P',99,old_hash));del services[request_key(99,old_hash,len(old))]
    raw,_=program(profile);hashed=digest(raw);services[value_key('P',99,hashed)]=raw
    services[request_key(99,hashed,len(raw))]=request_wire((1,));wide=list(wide);wide[4]+=len(raw)-len(old)
    services[source]=metadata_wire((hashed,wide,narrow))
    manager,delegator,registrar,assigners,allowances=late.host.privileges(services[chapter_key(12)],2)
    return late.host.original(services,privilege_wire((manager,delegator,registrar,assigners+[0],allowances)))


def advance(parent,profile,slot,gs,ass,reports,payloads):
    """Admit against prior Q, execute selected guest effects, then reevaluate actual provision relevance against posterior Q."""
    raw,commitment=late.host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """Authenticate every supplied byte and count it for the actual author even if posterior integration ignores it."""
        return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    old,released,_,_=late.host.execution.population.validate(parent,slot,gs,ass)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes]
    block,state=late.host.advance(parent,slot,gs,ass,reports,foundation=foundation)
    invoked=[row[0] for wire in selected for row in reports[wire[:32]]['digests']]
    before=value_key('P',42,digest(target_code())) in parent
    if 42 in invoked:late.host.charge(state,42,slot,22 if before else 0,operands=invoked.count(42))
    if 99 in invoked:
        assert invoked.count(99)==1
        late.host.charge(state,99,slot,program(profile)[1],operands=1)
        retained=profile in ('forget-panic','forget-solicit-checkpoint-panic')
        if not retained:
            target=chapter_service(255,42);code,wide,narrow=metadata(state[target],105)
            wide=list(wide);narrow=list(narrow);wide[4]-=81+len(target_code());narrow[0]-=2
            state[target]=metadata_wire((code,wide,narrow));del state[request_key(42,code,len(target_code()))]
    relevant=[(sid,blob) for sid,blob in payloads if state.get(request_key(sid,digest(blob),len(blob)))==request_wire(())]
    late.integrate(state,relevant,slot)
    if payloads and not relevant:
        # GP activity counts all actual extrinsic bytes even if fnprovide ignores the now-dropped request.
        from state_statistics_oracle import wire as statistics_wire
        current,previous,cores,activity=late.host.statistics(state);rows={row[0]:list(row) for row in activity}
        for sid,blob in payloads:
            row=rows.setdefault(sid,[sid]+[0]*11);row[1]+=1;row[2]+=len(blob)
        state[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(rows[sid]) for sid in sorted(rows)]))
    return block,state,dict(slot=slot,invoked=invoked,code_available_before=before,integrated=bool(relevant),supplied=bool(payloads))


@owned_histories
def cases():
    """Cancellation at either growth or shrink admits the same prior request but selects actual posterior relevance independently."""
    result=[]
    for profile in PROFILES:
        for cancelled in (12,24):
            parent=original(profile);initial=dict(parent);reports={};steps=[];events=[]
            for slot in late.host.execution.SLOTS:
                gs=[]
                if slot in (10,12,23,24):
                    ids=[(0,42)]+([(1,99)] if (slot==10 and cancelled==12) or (slot==23 and cancelled==24) else [])
                    for core,sid in ids:
                        item=late.host.execution.guarantee(parent,core,slot,sid);gs.append(item);reports[item['report'][:32]]=item['layout']
                count={12:5,13:7,24:7,25:5}.get(slot,0)
                pending=late.host.execution.reporting.pending(parent[chapter_key(10)],3,9)
                bits=sum(1<<core for core,item in enumerate(pending) if item is not None)
                ass=late.host.execution.rotation.assurances(parent,count,bits) if count else []
                payloads=((42,target_code()),) if slot==cancelled else ()
                block,state,event=advance(parent,profile,slot,gs,ass,reports,payloads)
                steps.append((block,state,[]));events.append(event);parent=state
            case=dict(name=profile+'-at-'+str(cancelled),parameters=late.host.parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(target_code(),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze every signed body, full state and request-relevance decision before consulting native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
