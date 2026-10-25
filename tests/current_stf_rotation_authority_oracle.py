# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent immediate supervisor authority, protected funding and later foreign-code selection across changing populations."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_supervised_handoff_oracle as handoff
import current_stf_supervisor_lifecycle_oracle as lifecycle
import current_stf_supervised_upgrades_oracle as upgrades
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-authority.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,handoff.FIXTURE,lifecycle.FIXTURE,upgrades.FIXTURE)
FAMILIES = (('handoff',handoff,handoff.PROFILES),('lifecycle',lifecycle,lifecycle.PROFILES),('upgrades',upgrades,upgrades.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')


def cases():
    """Four real releases test same-invocation authority changes and later receiver/current-code behavior at growth and shrinkage."""
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
                    sid = 42 if family=='upgrades' and slot in (12,24) else 99
                    item = host.execution.guarantee(parent,1,slot,sid)
                    gs.append(item);reports[item['report'][:32]] = item['layout']
                votes = {12:5,13:7,24:7,25:5}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,votes,2) if votes else []
                block,state = host.advance(parent,slot,gs,ass,reports)
                if votes:
                    options = dict(statistics_config=host.statistics_config(state))
                    if family=='upgrades':options['recipient_slots']=(13,25)
                    events.append(oracle.effects(state,parent,profile,slot,100000,**options))
                steps.append((block,state,[]));parent = state
            case = dict(name=family+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows'] = declaration(case,(42,99),blobs=(upgrades.replacement(),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze complete wires, maps, namespaces and roots before native execution; original references stay frozen."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
