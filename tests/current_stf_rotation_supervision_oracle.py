# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent supervised storage/request effects, common-prior conflict yields and surviving provisions across changing populations."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_supervised_storage_oracle as storage
import current_stf_supervised_requests_oracle as requests
import current_stf_supervised_conflicts_oracle as conflicts
from current_stf_rotation_transfers_oracle import foundation
from state_layout_oracle import chapter_key,digest
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-supervision.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,storage.FIXTURE,requests.FIXTURE,conflicts.FIXTURE)
FAMILIES = (('storage',storage,storage.PROFILES),('requests',requests,requests.PROFILES),('conflicts',conflicts,conflicts.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')


def cases():
    """Quorum releases real supervisor/junior guests at both boundaries, with independently selected MMR yields and actual namespaces."""
    result = []
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            services = oracle.original(profile)
            manager,delegator,registrar,assigners,allowances = host.privileges(services[chapter_key(12)],2)
            parent = host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial = dict(parent);reports = {};steps = [];events = []
            for slot in host.execution.SLOTS:
                gs = []
                if slot in (10,12,23,24):
                    for core,sid in (((0,42),(1,99)) if family=='conflicts' else ((1,99),)):
                        item = host.execution.guarantee(parent,core,slot,sid)
                        gs.append(item);reports[item['report'][:32]] = item['layout']
                votes = {12:5,13:7,24:7,25:5}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,votes,3 if family=='conflicts' else 2) if votes else []
                outputs = ((42,conflicts.COMMITMENT),) if votes and family=='conflicts' and profile in ('supervisor-panic','stale-supervisor') else ()
                block,state = host.advance(parent,slot,gs,ass,reports,foundation=foundation(parent,slot,outputs))
                if votes:
                    events.append(oracle.effects(state,parent,profile,slot,100000,statistics_config=host.statistics_config(state)))
                steps.append((block,state,[]));parent = state
            case = dict(name=family+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps,events=events)
            pairs = ((digest(b'I'),1),(digest(b'Q'),1),(digest(requests.PAYLOAD),1))
            case['inventory'],case['inventory_rows'] = declaration(case,(42,99),request_pairs=pairs)
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete signed maps, roots, yields/provisions and logical identity declarations before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
