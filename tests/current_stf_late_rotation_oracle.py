# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map late code-extrinsic ordering at validator growth and shrinkage."""
from pathlib import Path
import json
import rotation_host_oracle as host
import current_stf_late_code_oracle as late
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration
from state_layout_oracle import chapter_key,digest
from state_privileges_oracle import wire as privilege_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_statistics_oracle import wire as statistics_wire

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-rotation.json'
SOURCES=(late.FIXTURE,host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE)
NATIVE_DEFINES=('rotationHosts','rotationLifecycle','rotationCode','rotationRequests','rotationIncarnations')
SUPPLIES=(12,13,23,24)


def original(mode):
    """Preserve the exact reservation and metadata code hash; only its genuinely absent preimage is unavailable."""
    services=late.original(mode)
    manager,delegator,registrar,assigners,allowances=host.privileges(services[chapter_key(12)],2)
    return host.original(services,privilege_wire((manager,delegator,registrar,assigners+[0],allowances)))


def integrate(state,payloads,slot):
    """GP extrinsic integration follows every guest; fulfilled requests retain their reservation and gain actual time."""
    for sid,raw in payloads:
        state[value_key('P',sid,digest(raw))]=raw
        state[request_key(sid,digest(raw),len(raw))]=request_wire((slot,))
    if payloads:
        current,previous,cores,activity=host.statistics(state)
        rows={row[0]:list(row) for row in activity}
        for sid,raw in payloads:
            row=rows.setdefault(sid,[sid]+[0]*11);row[1]+=1;row[2]+=len(raw)
        state[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(rows[s]) for s in sorted(rows)]))


def advance(parent,mode,slot,gs,ass,reports,payloads,*,processed=None,batches=None,ready=None,effects=None,yielded=None):
    """Authenticate actual extrinsic bytes and author statistics while execution reads only the prior code availability."""
    available=value_key('P',99,digest(late.code(mode))) in parent
    if effects is None:
        effects=[{42:{},99:({} if available else dict(charge=0,retained=False))}]
    raw,commitment=host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """Use the exact independent full body commitment, never a native header or observed posterior map."""
        return host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    old,released,_,_=host.execution.population.validate(parent,slot,gs,ass)
    selected=[item['guarantee']['report'] for item,yes in zip(old,released) if item is not None and yes] if processed is None else processed
    invoked=any(any(row[0]==99 for row in reports[wire[:32]]['digests']) for wire in selected) if batches is None else any(99 in group for group in batches)
    block,state=host.execution.advance(parent,mode,slot,gs,ass,reports,processed=processed,batches=batches,
        ready=ready,effects=effects,yielded=available and invoked and mode!='panic-rollback' if yielded is None else yielded,
        foundation_override=foundation)
    integrate(state,payloads,slot)
    return block,state


def cases():
    """Four fulfillment positions distinguish same-block skips from later new report executions at both boundaries."""
    result=[]
    for mode in late.pipeline.MODES:
        for supplied in SUPPLIES:
            parent=original(mode);initial=dict(parent);reports={};steps=[];events=[]
            for slot in host.execution.SLOTS:
                gs=[]
                if slot in (10,12,23,24):
                    for core,sid in ((0,42),(1,99)):
                        item=host.execution.guarantee(parent,core,slot,sid)
                        gs.append(item);reports[item['report'][:32]]=item['layout']
                count={12:5,13:7,24:7,25:5}.get(slot,0)
                ass=host.execution.rotation.assurances(parent,count,3) if count else []
                payloads=((99,late.code(mode)),) if slot==supplied else ()
                block,state=advance(parent,mode,slot,gs,ass,reports,payloads)
                events.append(dict(slot=slot,supplied=bool(payloads),code_available_before=value_key('P',99,digest(late.code(mode))) in parent))
                steps.append((block,state,[]));parent=state
            case=dict(name=mode+'-supply-'+str(supplied),parameters=host.parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.code(mode),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete signed wires, maps and exact roots before actual candidate execution sees its inputs."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
