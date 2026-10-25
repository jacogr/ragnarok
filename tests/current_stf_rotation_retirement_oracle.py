# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent newborn refusal, reservation cleanup, funded retirement and fresh same-ID incarnations across6/9/6 rosters."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_child_retirement_oracle as retirement
import current_stf_child_recreation_oracle as recreation
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-retirement.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,retirement.FIXTURE,recreation.FIXTURE)
FAMILIES = (('retirement',retirement,retirement.PROFILES),('recreation',recreation,recreation.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')


def parameters():
    """Every funded child carries the explicit complete7/1/100 deposit schedule and three-core/twelve-slot tuple."""
    wire = bytearray(host.parameters())
    for index,value in enumerate((7,1,100)):
        wire[index*8:index*8+8] = value.to_bytes(8,'little')
    return bytes(wire)


def cases():
    """Birth/cleanup at growth must survive newborn eject; the prior-nine quorum retires/recreates at shrinkage."""
    result = []
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            services = oracle.original(profile)
            manager,delegator,registrar,assigners,allowances = host.privileges(services[chapter_key(12)],2)
            parent = host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial = dict(parent);reports = {};steps = [];events = []
            for slot in host.execution.SLOTS:
                gs = []
                if slot in (10,23):
                    item = host.execution.guarantee(parent,1,slot,99)
                    gs.append(item);reports[item['report'][:32]] = item['layout']
                votes = {12:5,24:7}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,votes,2) if votes else []
                block,state = host.advance(parent,slot,gs,ass,reports)
                if votes:
                    events.append(oracle.effects(state,parent,profile,slot,100000,
                        creation_slot=12,retirement_slot=24,statistics_config=host.statistics_config(state)))
                steps.append((block,state,[]));parent = state
            case = dict(name=family+'-'+profile,parameters=parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows'] = declaration(case,(42,77,99),blobs=(retirement.replacement(),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Bind all signed blocks/maps/roots and complete logical inventories before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
