# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent forwarded transfer reentry and active-supervisor held credits through actual-gas continuation across rotation."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_forwarded_transfers_oracle as forwarded
import current_stf_supervised_transfers_oracle as held
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-transfer-waves.json'
SOURCES=(host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,forwarded.FIXTURE,held.FIXTURE)
FAMILIES=(('forwarded',forwarded,forwarded.PROFILES),('held',held,held.PROFILES))
NATIVE_DEFINES=('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')


def guarantee(parent,core,slot,budget):
    """Real declared budgets force separate source rounds without changing any report's authenticated service/code identity."""
    item=host.execution.guarantee(parent,core,slot,99)
    row=list(item['layout']['digests'][0]);row[3]=budget;item['layout']['digests']=[tuple(row)]
    host.execution.population.resign(item,host.execution.rotation.credentials(parent,slot,slot)[0])
    return item


def cases():
    """Quorum releases exercise all transfer rounds at growth, within nine validators, at shrinkage and afterwards."""
    result=[]
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            services=oracle.original(profile)
            manager,delegator,registrar,assigners,allowances=host.privileges(services[chapter_key(12)],2)
            parent=host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial=dict(parent);reports={};steps=[];events=[]
            for slot in host.execution.SLOTS:
                gs=[]
                if slot in (10,12,23,24):
                    for core in ((0,1) if family=='held' else (1,)):
                        item=guarantee(parent,core,slot,200000 if family=='held' else 100000)
                        gs.append(item);reports[item['report'][:32]]=item['layout']
                votes={12:5,13:7,24:7,25:5}.get(slot,0)
                ass=host.execution.rotation.assurances(parent,votes,3 if family=='held' else 2) if votes else []
                block,state=host.advance(parent,slot,gs,ass,reports)
                if votes:
                    events.append(oracle.effects(state,profile,slot,statistics_config=host.statistics_config(state)))
                steps.append((block,state,[]));parent=state
            case=dict(name=family+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows']=declaration(case,(42,99))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete mathematical outputs before native execution; original fixed-population answers remain unchanged."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
