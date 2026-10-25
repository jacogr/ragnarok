# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent child provision/readiness and current-code activation for reports admitted around an epoch-boundary upgrade."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_child_readiness_oracle as children
import current_stf_service_upgrades_oracle as upgrades
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from report_oracle import encode as report_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-code.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,children.FIXTURE,upgrades.FIXTURE)
FAMILIES = (('child',children,children.PROFILES),('upgrade',upgrades,upgrades.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode')


def guarantee(parent,slot,sid,budget):
    """Sign a real report under its admission parent's code hash, including a pending old-code report before upgrade publication."""
    item = host.execution.guarantee(parent,1,slot,sid)
    row = list(item['layout']['digests'][0]);row[3] = budget;item['layout']['digests'] = [tuple(row)]
    host.execution.population.resign(item,host.execution.rotation.credentials(parent,slot,slot)[0])
    return item


def cases():
    """Code-ready children run within the larger epoch and across shrinkage; old reports use the current account program."""
    assert len(upgrades.replacement()) == 29
    result = []
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            services = oracle.original(profile)
            manager,delegator,registrar,assigners,allowances = host.privileges(services[chapter_key(12)],2)
            parent = host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial = dict(parent);reports = {};budgets = {};steps = [];child = None;ids = {42,99};events = []
            for slot in host.execution.SLOTS:
                gs = []
                budget = 500 if family=='upgrade' and profile=='host-oog' and slot==10 else 100000
                sid = 99 if family=='upgrade' or slot==10 else child
                admitted = slot in ((10,12,23,24) if family=='upgrade' else (10,13,23,24))
                if admitted and sid is not None:
                    item = guarantee(parent,slot,sid,budget);gs.append(item)
                    reports[item['report'][:32]] = item['layout'];budgets[item['report'][:32]] = budget
                released = slot in ((12,13,24,25) if family=='upgrade' else (12,14,24,25)) and (family=='upgrade' or slot==12 or child is not None)
                votes = 2*len(host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
                ass = host.execution.rotation.assurances(parent,votes,2) if released else []
                pending = host.execution.reporting.pending(parent[chapter_key(10)],3,9)
                available = [item['guarantee']['report'] for item in pending if item is not None] if released else []
                block,state = host.advance(parent,slot,gs,ass,reports)
                if released:
                    assert len(available) == 1
                    offered = budgets[available[0][:32]];config = host.statistics_config(state)
                    if family == 'child':
                        event = children.effects(state,parent,profile,slot,offered,child,
                            creation_slot=12,execution_slots=(14,24,25),statistics_config=config)
                        child = event['child']
                        if child is not None:ids.add(child)
                    else:
                        event = upgrades.effects(state,parent,profile,slot,offered,statistics_config=config)
                    events.append(event)
                steps.append((block,state,[]));parent = state
            case = dict(name=family+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps,events=events,reports=reports)
            case['inventory'],case['inventory_rows'] = declaration(case,ids,blobs=(upgrades.replacement(),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze signed wires, complete maps and logical identities independently before executing any native client code."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
