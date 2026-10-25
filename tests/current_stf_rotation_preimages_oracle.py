# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent request/provision lifecycle and exact strict preimage-age boundaries after validator growth/shrinkage."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_request_lifecycle_oracle as requests
import current_stf_preimage_provision_oracle as provision
import current_stf_preimage_aging_oracle as aging
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata_parse
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration
from state_privileges_oracle import wire as privileges_wire

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-preimages.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,requests.FIXTURE,provision.FIXTURE,aging.FIXTURE)
FAMILIES = (('requests',requests,requests.PROFILES),('provision',provision,provision.PROFILES),('aging',aging,aging.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')
AGING_SLOTS = host.execution.SLOTS+(4799,4800,4801,4802,4811,4812,4813,4814)


def guarantee(parent,slot,stamp):
    """Separate bounded authored package stamps from actual E4 slots at expiry boundaries, using genuine current credentials."""
    item = host.execution.population.guarantee(parent,1,stamp,slot,slot)
    item['layout']['prerequisites'] = b''
    row = list(item['layout']['digests'][0]);row[0] = 99
    row[1] = metadata_parse(parent[chapter_service(255,99)],105)[0];row[3] = 100000
    item['layout']['digests'] = [tuple(row)]
    host.execution.population.resign(item,host.execution.rotation.credentials(parent,slot,slot)[0])
    return item


def cases():
    """Four releases cross changing populations; aging cases continue to exact and one-past4801/4812 bounds without changing pins."""
    result=[]
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            services=oracle.original(profile)
            manager,delegator,registrar,assigners,allowances=host.privileges(services[chapter_key(12)],2)
            parent=host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial=dict(parent);reports={};steps=[];events=[]
            slots=AGING_SLOTS if family=='aging' else host.execution.SLOTS
            for index,slot in enumerate(slots):
                gs=[]
                if slot in (10,12,23,24) or family=='aging' and slot in (4799,4800,4801,4811,4812):
                    item=guarantee(parent,slot,200+index);gs.append(item);reports[item['report'][:32]]=item['layout']
                released=slot in (12,13,24,25) or family=='aging' and slot in (4800,4801,4802,4812,4813)
                votes=2*len(host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
                ass=host.execution.rotation.assurances(parent,votes,2) if released else []
                block,state=host.advance(parent,slot,gs,ass,reports)
                if released:
                    options=dict(statistics_config=host.statistics_config(state))
                    if family=='aging':options['lookup_age']=0
                    events.append(oracle.effects(state,parent,profile,slot,100000,**options))
                steps.append((block,state,[]));parent=state
            parameters=bytearray(host.parameters())
            if family=='aging':parameters[74:78]=bytes(4)
            case=dict(name=family+'-'+profile,parameters=bytes(parameters),initial=initial,steps=steps,events=events)
            known=((digest(b'I'),1),(digest(b'Q'),1),(digest(requests.PAYLOAD),1))
            case['inventory'],case['inventory_rows']=declaration(case,(42,99),request_pairs=known)
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze independent complete maps, literal gas, signed blocks and logical namespace declarations before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
