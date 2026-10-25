# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent foreign-source funding, direct balance transfer and common-prior junior-write annulment across6/9/6 rosters."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_foreign_creation_oracle as creation
import current_stf_foreign_transfers_oracle as transfers
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-funding.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,creation.FIXTURE,transfers.FIXTURE)
FAMILIES = (('creation',creation,creation.PROFILES),('transfer',transfers,transfers.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle','rotationCode','rotationRequests')


def parameters():
    """Both funding families carry the explicit7/1/100 deposit schedule, independent of their selected liquid/protected pools."""
    wire = bytearray(host.parameters())
    for index,value in enumerate((7,1,100)):
        wire[index*8:index*8+8] = value.to_bytes(8,'little')
    return bytes(wire)


def cases():
    """Two real services run from one prior at each release; selected foreign modification alone annuls the junior's own write."""
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
                    for core,sid in ((0,42),(1,99)):
                        item = host.execution.guarantee(parent,core,slot,sid)
                        gs.append(item);reports[item['report'][:32]] = item['layout']
                votes = {12:5,13:7,24:7,25:5}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,votes,3) if votes else []
                block,state = host.advance(parent,slot,gs,ass,reports)
                if votes:
                    events.append(oracle.effects(state,parent,profile,slot,100000,statistics_config=host.statistics_config(state)))
                steps.append((block,state,[]));parent = state
            case = dict(name=family+'-'+profile,parameters=parameters(),initial=initial,steps=steps,events=events)
            case['inventory'],case['inventory_rows'] = declaration(case,(42,77,99),blobs=(creation.replacement(),))
            result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze signed complete maps, exact gas/namespace effects and independently calculated commitments before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
