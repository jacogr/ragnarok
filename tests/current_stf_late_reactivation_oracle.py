# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent code expunge, exact-age restoration and later code reactivation after selected foreign effects."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_relevance_oracle as relevance
from current_stf_effects_oracle import immediate,envelope,simulate,gas_definitions
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata,wire as metadata_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

late=relevance.late
FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-reactivation.json'
SOURCES=(relevance.FIXTURE,late.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES
SLOTS=late.host.execution.SLOTS+(4799,4800,4801,4802,4803,4804,4805,4806)


def program(mode):
    """Forget then solicit the exact foreign halt-code identity; checkpoint selection can retain the recreated reservation."""
    instructions=[]
    for operation in (26,25):
        instructions.extend((immediate(7,42),immediate(8,196608),immediate(9,len(relevance.target_code())),bytes([10,operation])))
    if mode=='checkpoint-panic':instructions.append(bytes([10,19])) # Capture actual expunge and recreation before terminal panic.
    instructions.append(bytes([50,0]) if mode=='halt' else b'\0')
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+3250+2193+103*int(mode=='checkpoint-panic')
    return envelope(instructions,digest(relevance.target_code())),gas


def original(mode):
    """An exact two-slot removed history retains real code bytes and the original reservation before any aging invocation."""
    state=relevance.original('forget-solicit-checkpoint-panic')
    raw=relevance.target_code();hashed=digest(raw);state[value_key('P',42,hashed)]=raw
    state[request_key(42,hashed,len(raw))]=request_wire((0,1))
    key=chapter_service(255,99);old_hash,wide,narrow=metadata(state[key],105)
    old=state.pop(value_key('P',99,old_hash));del state[request_key(99,old_hash,len(old))]
    code,_=program(mode);hashed=digest(code);state[value_key('P',99,hashed)]=code
    state[request_key(99,hashed,len(code))]=request_wire((1,));wide=list(wide);wide[4]+=len(code)-len(old)
    state[key]=metadata_wire((hashed,wide,narrow));return state


def guarantee(parent,slot,stamp,core,sid):
    """Keep package stamps bounded independently of real large E4 times and sign actual current-roster credentials."""
    item=late.host.execution.population.guarantee(parent,core,stamp,slot,slot)
    item['layout']['prerequisites']=b''
    row=list(item['layout']['digests'][0]);row[0]=sid;row[1]=metadata(parent[chapter_service(255,sid)],105)[0];row[3]=100000
    item['layout']['digests']=[tuple(row)];late.host.execution.population.resign(item,late.host.execution.rotation.credentials(parent,slot,slot)[0])
    return item


def advance(parent,mode,slot,gs,ass,reports,payloads):
    """Execute all services against prior code, merge selected foreign history effects, then integrate later extrinsics."""
    raw,commitment=late.host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """The real body and actual supplied bytes determine signing and author activity before native execution."""
        return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    old,released,_,_=late.host.execution.population.validate(parent,slot,gs,ass)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes]
    block,state=late.host.advance(parent,slot,gs,ass,reports,foundation=foundation)
    invoked=[row[0] for wire in selected for row in reports[wire[:32]]['digests']]
    raw=relevance.target_code();hashed=digest(raw);payload=value_key('P',42,hashed);request=request_key(42,hashed,len(raw))
    available=payload in parent;expunged=False
    if 42 in invoked:late.host.charge(state,42,slot,22 if available else 0,operands=invoked.count(42))
    if 99 in invoked:
        assert invoked.count(99)==1
        late.host.charge(state,99,slot,program(mode)[1],operands=1)
        if mode!='panic':
            assert parent[request]==request_wire((0,1))
            expunged=1+4800<slot
            state[request]=request_wire(()) if expunged else request_wire((0,1,slot))
            if expunged:del state[payload] # Recreation preserves the full reservation but never the expunged bytes.
    late.integrate(state,payloads,slot)
    return block,state,dict(slot=slot,invoked=invoked,code_available_before=available,expunged=expunged,supplied=bool(payloads))


@owned_histories
def cases():
    """Compare exact4801 versus one-past4802, rollback/checkpoint selection and one/two-block code-arrival delays."""
    result=[]
    for mode in ('halt','panic','checkpoint-panic'):
        for edited in (4801,4802):
            for supplied in ((4803,4804) if edited==4802 and mode!='panic' else (None,)):
                parent=original(mode);initial=dict(parent);reports={};steps=[];events=[]
                for index,slot in enumerate(SLOTS):
                    gs=[]
                    if slot in (10,12,23,24,4799,4800,4801,4802,4803,4804,4805):
                        item=guarantee(parent,slot,150+index,0,42);gs.append(item);reports[item['report'][:32]]=item['layout']
                    if slot==edited-1:
                        item=guarantee(parent,slot,150+index,1,99);gs.append(item);reports[item['report'][:32]]=item['layout']
                    pending=late.host.execution.reporting.pending(parent[chapter_key(10)],3,9)
                    bits=sum(1<<core for core,item in enumerate(pending) if item is not None)
                    released=slot in (12,13,24,25,4800,4801,4802,4803,4804,4805,4806)
                    count=2*len(late.host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
                    ass=late.host.execution.rotation.assurances(parent,count,bits) if released else []
                    payloads=((42,relevance.target_code()),) if slot==supplied else ()
                    block,state,event=advance(parent,mode,slot,gs,ass,reports,payloads)
                    steps.append((block,state,[]));events.append(event);parent=state
                parameters=bytearray(late.host.parameters());parameters[74:78]=bytes(4)
                case=dict(name=mode+'-edit-'+str(edited)+'-supply-'+str(supplied),parameters=bytes(parameters),initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(relevance.target_code(),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze every complete signed history and independently derived availability lifetime before native replay."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
