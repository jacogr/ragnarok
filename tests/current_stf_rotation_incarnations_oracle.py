# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent retired/recreated supervisor authority and unchanged old-code report identity through validator rotation."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_incarnation_authority_oracle as authority
import current_stf_queued_incarnation_oracle as queued
from current_stf_effects_oracle import envelope
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-incarnations.json'
SOURCES=(host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,authority.FIXTURE,queued.FIXTURE)
NATIVE_DEFINES=('rotationHosts','rotationLifecycle','rotationCode','rotationRequests','rotationIncarnations')


def cases():
    """Recreation and rebind use actual prior authority; an old queued report retains its signed zero code hash."""
    result=[]
    for queue_old in (False,True):
        for profile in authority.PROFILES:
            services=authority.original(profile)
            manager,delegator,registrar,assigners,allowances=host.privileges(services[chapter_key(12)],2)
            parent=host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial=dict(parent);reports={};steps=[];events=[];old_report=None
            for slot in host.execution.SLOTS:
                if queue_old:
                    targets=((0,99),(1,77)) if slot==12 else (((0,42),) if slot==13 else (((1,77),) if slot==23 else ()))
                    bits={13:1,14:3,24:2}.get(slot,0);creation=13
                else:
                    targets=((0,99),) if slot==10 else (((0,42),(1,77)) if slot==13 else (((1,77),) if slot==23 else ()))
                    bits={12:1,14:3,24:2}.get(slot,0);creation=12
                gs=[]
                for core,sid in targets:
                    item=host.execution.guarantee(parent,core,slot,sid)
                    gs.append(item);reports[item['report'][:32]]=item['layout']
                    if queue_old and slot==12 and sid==77:
                        old_report=item['report'];assert item['layout']['digests'][0][1]==bytes(32)
                votes=2*len(host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
                ass=host.execution.rotation.assurances(parent,votes,bits) if bits else []
                if queue_old and slot==14:
                    pending=host.execution.reporting.pending(parent[chapter_key(10)],3,9)
                    assert any(item is not None and item['guarantee']['report']==old_report for item in pending)
                block,state=host.advance(parent,slot,gs,ass,reports)
                if bits:
                    events.append(authority.effects(state,parent,profile,slot,creation_slot=creation,rebind_slot=14,write_slot=24,
                        statistics_config=host.statistics_config(state)))
                steps.append((block,state,[]));parent=state
            child=envelope(*authority.programs(profile)[2]);assert len(child)<=512
            case=dict(name=('queued-' if queue_old else 'direct-')+profile,parameters=host.parameters(),initial=initial,
                steps=steps,events=events,old_report=None if old_report is None else old_report.hex())
            case['inventory'],case['inventory_rows']=declaration(case,(42,77,99),blobs=(child,))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze all complete maps and authenticated wire bytes before executing the native candidate path."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
