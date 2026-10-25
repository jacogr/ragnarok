# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent entropy-derived/reserved creation, funded balance pools and exact-once retirement across6/9/6 rosters."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_service_creation_oracle as creation
import current_stf_reserved_creation_oracle as reserved
import current_stf_service_ejection_oracle as ejection
from state_layout_oracle import chapter_key, chapter_service
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration, encode

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-creation.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,
           creation.FIXTURE,reserved.FIXTURE,ejection.FIXTURE)
FAMILIES = (('basic',creation,creation.PROFILES),('reserved',reserved,reserved.PROFILES),
            ('ejection',ejection,ejection.PROFILES))
NATIVE_DEFINES = ('rotationHosts','rotationLifecycle')


def parameters(family):
    """Reserved creation alone uses the explicit7/1/100 deposit schedule; other authored profiles retain zero deposits."""
    result = bytearray(host.parameters())
    if family == 'reserved':
        for index,value in enumerate((7,1,100)):
            result[index*8:index*8+8] = value.to_bytes(8,'little')
    return bytes(result)


def cases(selected=None):
    """Real reports create/refuse/retire accounts at growth, within nine validators, at shrinkage and afterwards."""
    result = []
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            name = family+'-'+profile
            if selected is not None and name not in selected:
                continue # Focused diagnostic controls derive only their own complete mathematical input histories.
            services = oracle.original(profile)
            manager,delegator,registrar,assigners,allowances = host.privileges(services[chapter_key(12)],2)
            parent = host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial = dict(parent);reports = {};steps = [];ids = {42,77,99};births = []
            for slot in host.execution.SLOTS:
                gs = []
                if slot in (10,12,23,24):
                    item = host.execution.guarantee(parent,1,slot,99)
                    gs.append(item);reports[item['report'][:32]] = item['layout']
                count = {12:5,13:7,24:7,25:5}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,count,2) if count else []
                block,state = host.advance(parent,slot,gs,ass,reports)
                if count:
                    config = host.statistics_config(state)
                    if family == 'basic':
                        trace = oracle.effects(state,profile,slot,statistics_config=config)
                        ids.update(trace['created']);births.append((slot,trace['created']))
                    else:
                        oracle.effects(state,parent,profile,slot,100000,statistics_config=config)
                steps.append((block,state,[]));parent = state
            case = dict(name=name,parameters=parameters(family),initial=initial,steps=steps,births=births)
            case['inventory'],case['inventory_rows'] = declaration(case,ids,blobs=(creation.replacement(),))
            result.append(case)
    return result


def negative_inventory_cases():
    """Valid signed creation blocks must fail before installation if their complete logical inventory is withheld."""
    case = cases(('basic-halt',))[0]
    requests,expected,_ = collect([case],FIXTURE,SOURCES,False)
    target = case['births'][0][1][0]
    failing = next(index for index,(_,state,_) in enumerate(case['steps']) if chapter_service(255,target) in state)
    prefix = expected[:2*failing+2]
    inputs = requests[:failing+2]
    result = []
    rows = case['inventory_rows']
    removed = [(sid,keys,hashes) for sid,keys,hashes in rows if sid != target]
    missing_request = [(sid,keys,[] if sid==target else hashes) for sid,keys,hashes in rows]
    for name,packet in (('missing-child',encode(removed)),('missing-code-request',encode(missing_request))):
        fields = inputs[0].split();fields[-1] = packet.hex()
        result.append(dict(name=name,requests=[' '.join(fields)]+inputs[1:],
            expected=prefix+['[Assertion Failure] inventory/IncompleteNamespaces']))
    for name,packet in (('truncated-declaration',case['inventory'][:-1]),('too-many-services',(17).to_bytes(2,'little'))):
        fields = inputs[0].split();fields[-1] = packet.hex()
        result.append(dict(name=name,requests=[' '.join(fields)],expected=['[Assertion Failure] inventory/InvalidDeclaration']))
    return result


def expected_observations(check_frozen=True):
    """Freeze every signed block, complete map, root and logical-declaration identity before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
