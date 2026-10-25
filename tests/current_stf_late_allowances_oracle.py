# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent always-accumulate code arrival, zero-participant statistics and deferred credits to unavailable recipient code."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import envelope,simulate,gas_definitions
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata,wire as metadata_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_privileges_oracle import wire as privilege_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-allowances.json'
SOURCES=(late.FIXTURE,transfers.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES
SLOTS=late.host.execution.SLOTS+(26,)


def source_code(mode):
    """Use the original literal deferred transfer, with halt, rollback panic or retained checkpoint behavior."""
    instructions,memory,_,_=transfers.program(mode)
    return envelope(instructions,memory)


def target_code():
    """The original authored42 halt is an actual independent code payload and request identity."""
    state=transfers.original('halt');code,_,_=metadata(state[chapter_service(255,42)],105)
    return state[value_key('P',42,code)]


def original(mode):
    """Both code reservations are honestly pending; the explicit prior privilege grants99 a100000-unit empty-operand allowance."""
    services=transfers.original(mode)
    for sid,raw in ((42,target_code()),(99,source_code(mode))):
        hashed=digest(raw);del services[value_key('P',sid,hashed)];services[request_key(sid,hashed,len(raw))]=request_wire(())
    manager,delegator,registrar,assigners,_=late.host.privileges(services[chapter_key(12)],2)
    return late.host.original(services,privilege_wire((manager,delegator,registrar,assigners+[0],[(99,100000)])))


def balance(state,sid,delta):
    """Only a retained actual outgoing transfer debits99 and credits42; code absence does not discard accepted funds."""
    key=chapter_service(255,sid);code,wide,narrow=metadata(state[key],105);wide=list(wide);wide[0]+=delta
    assert wide[0]>=0
    state[key]=metadata_wire((code,wide,narrow))


def advance(parent,mode,slot,gs,ass,reports,payloads):
    """Execute prior allowances once, then actual deferred recipient inputs, and integrate code after all accumulation rounds."""
    raw,commitment=late.host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """All actual supplied bytes affect body authentication and author statistics, independently of guest availability."""
        return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    old,released,_,_=late.host.execution.population.validate(parent,slot,gs,ass)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes]
    block,state=late.host.advance(parent,slot,gs,ass,reports,foundation=foundation)
    target_available=value_key('P',42,digest(target_code())) in parent
    source_available=value_key('P',99,digest(source_code(mode))) in parent
    count=sum(row[0]==42 for wire in selected for row in reports[wire[:32]]['digests'])
    if count:late.host.charge(state,42,slot,22 if target_available else 0,operands=count)
    delivered=source_available and mode!='panic'
    if source_available:
        instructions,_,amount,offer=transfers.program(mode)
        used=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+575+offer+103*int(mode=='checkpoint-panic')
        assert used<=100000
        late.host.charge(state,99,slot,used)
        if delivered:
            balance(state,99,-amount);balance(state,42,amount)
            late.host.charge(state,42,slot,22 if target_available else 0,transfers=1)
    late.integrate(state,payloads,slot)
    return block,state,dict(slot=slot,source_available=source_available,target_available=target_available,
        operands=count,delivered=int(delivered),supplied=[sid for sid,_ in payloads])


@owned_histories
def cases():
    """Empty-operand zero-gas skips leave no accumulation timestamp; actual transfers still credit unavailable recipients exactly once."""
    result=[]
    for mode in ('halt','panic','checkpoint-panic'):
        for supplied in (11,12,23,24):
            parent=original(mode);initial=dict(parent);reports={};steps=[];events=[]
            for slot in SLOTS:
                gs=[]
                if slot in (10,12,23,24,25):
                    item=late.host.execution.guarantee(parent,0,slot,42);gs.append(item);reports[item['report'][:32]]=item['layout']
                votes={12:5,13:7,24:7,25:5,26:5}.get(slot,0)
                ass=late.host.execution.rotation.assurances(parent,votes,1) if votes else []
                payloads=((99,source_code(mode)),) if slot==supplied else ((42,target_code()),) if slot==supplied+1 else ()
                block,state,event=advance(parent,mode,slot,gs,ass,reports,payloads)
                steps.append((block,state,[]));events.append(event);parent=state
            case=dict(name=mode+'-source-'+str(supplied),parameters=late.host.parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(source_code(mode),target_code()))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze every complete mathematical map, true participant statistic and signed body before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
