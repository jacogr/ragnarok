# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent late code with genuine offender exclusion, dispute cancellation, surviving reports and filtered population promotion."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_offender_reporting_oracle as offender
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata
from state_service_values_oracle import key as value_key
from disputes_oracle import wire as dispute_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-offenders.json'
SOURCES=(late.FIXTURE,offender.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES


def original(mode):
    """Combine actual missing-code services with the original offender fixture's independently authored entropy."""
    state=late.original(mode)
    state[chapter_key(6)]=bytes(32)+b''.join(digest(b'offender-reporting-eta'+bytes([i])) for i in (1,2,3))
    return state


def inputs(parent,case,slot):
    """Use actual surviving credentials and dispute targets, then independently sign executable report code identities."""
    gs,ass,disputes=offender.inputs(parent,case,slot)
    for item in gs:
        sid=42 if item['layout']['core']==0 else 99
        row=list(item['layout']['digests'][0]);row[0]=sid;row[1]=metadata(parent[chapter_service(255,sid)],105)[0];row[3]=100000
        item['layout']['digests']=[tuple(row)];item['layout']['prerequisites']=b''
        offender.population.resign(item,offender.rotation.credentials(parent,slot,item['slot'])[0])
    return gs,ass,disputes


def signed_foundation(parent,slot,gs,ass,disputes,payloads,marks,outputs=()):
    """Bind genuine disputes, code bytes, independently selected output commitments and actual offender marker into the signed header."""
    raw,commitment=offender.reporting.body(gs,ass,payloads,disputes=dispute_wire(disputes))
    roots=dict(staging=bytes.fromhex(json.loads(offender.population.population.FIXTURE.read_text())['filtered_staging_ring_root']))
    return offender.epoch.successor(parent,slot,[],[],roots,cores=3,new_offenders=marks,
        body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)


def advance(parent,mode,slot,gs,ass,disputes,reports,payloads):
    """Cancel bad/wonky assigned reports before assurances, execute only actual surviving operands, then integrate late code."""
    working,marks,excluded,(old,released,_,_)=offender.validate(parent,slot,gs,ass,disputes)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes]
    available=value_key('P',99,digest(late.late.code(mode))) in parent
    invoked=any(row[0]==99 for wire in selected for row in reports[wire[:32]]['digests'])
    def foundation(ignored_raw,ignored_commitment,outputs):
        """Header prior-state commitment uses the real original parent, while reporting sees independently canceled assignments."""
        block,state=signed_foundation(parent,slot,gs,ass,disputes,payloads,marks,outputs)
        state[chapter_key(5)]=working[chapter_key(5)]
        return block,state
    effects=[{42:{},99:({} if available else dict(charge=0,retained=False))}]
    block,state=late.host.execution.advance(working,mode,slot,gs,ass,reports,processed=selected,
        effects=effects,yielded=available and invoked and mode!='panic-rollback',foundation_override=foundation)
    late.integrate(state,payloads,slot)
    return block,state,dict(slot=slot,code_available_before=available,
        processed=[wire[:32].hex() for wire in selected],counts={sid:sum(row[0]==sid for wire in selected for row in reports[wire[:32]]['digests']) for sid in (42,99)},excluded=[key.hex() for key in excluded],marks=[key.hex() for key in marks])


@owned_histories
def cases():
    """Code before/in/after cancellation never restores a canceled report; actual surviving populations and package histories remain distinct."""
    result=[]
    for mode in ('create','panic-rollback','checkpoint-panic'):
        for timing in (0,1):
            for supplied in (16,17,18):
                parent=original(mode);initial=dict(parent);reports={};steps=[];events=[];cancelled=None
                for slot in offender.SLOTS:
                    gs,ass,disputes=inputs(parent,timing,slot)
                    if slot==17:
                        _,_,removed=offender.verdict.plan(parent,disputes)
                        assert len(removed)==1
                        old=offender.reporting.pending(parent[chapter_key(10)],3,9)
                        cancelled=next(item['guarantee']['report'] for item in old if item is not None and digest(item['guarantee']['report']) in removed)
                    for item in gs:reports[item['report'][:32]]=item['layout']
                    payloads=((99,late.late.code(mode)),) if slot==supplied else ()
                    block,state,event=advance(parent,mode,slot,gs,ass,disputes,reports,payloads)
                    steps.append((block,state,[]));events.append(event);parent=state
                assert cancelled is not None
                case=dict(name=mode+'-timing-'+str(timing)+'-supply-'+str(supplied),parameters=late.host.parameters(),initial=initial,
                    steps=steps,events=events,cancelled=cancelled.hex())
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.late.code(mode),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze actual cancellation witnesses and every complete mathematical state before native replay."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
