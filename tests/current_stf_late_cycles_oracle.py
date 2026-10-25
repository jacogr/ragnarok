# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent unresolved dependency cycles and absent anchors through code arrival, row expiry and population changes."""
from pathlib import Path
from copy import deepcopy
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_population_waves_oracle as waves
from state_layout_oracle import chapter_key,digest
from state_service_values_oracle import key as value_key
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-cycles.json'
SOURCES=(late.FIXTURE,waves.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES
SLOTS=(2,8,9,10,11,12,13,14,20,21,22,23,24,25)


def inputs(parent,slot,reports,kind):
    """Make held A depend on B or a published but unprocessed anchor, then authenticate the actual changed report."""
    gs,ass=waves.inputs(parent,slot,True,reports)
    if slot==8:
        item=gs[0]
        item['layout']['prerequisites']=waves.waves.package('B') if kind=='cycle' else late.host.execution.reporting.DEPENDENCY
        waves.guests.population.resign(item,waves.guests.rotation.credentials(parent,slot,slot)[0])
    return gs,ass


def validate_dependencies(parent,guaranteed):
    """GP requires prerequisites in this extrinsic or recent history; queue/accumulated presence alone cannot admit a dependency."""
    records=late.host.execution.population.history(parent[chapter_key(3)])[0]
    known={item['layout']['header'][:32] for item in guaranteed}
    known.update(pairs[offset:offset+32] for _,pairs in records for offset in range(0,len(pairs),64))
    for item in guaranteed:
        raw=item['layout']['prerequisites']
        assert all(raw[offset:offset+32] in known for offset in range(0,len(raw),32)),'package/MissingDependency'


def seal_refusal(parent,slot,guaranteed,assured):
    """Authenticate an intentionally inadmissible dependency without constructing any hypothetical reporting successor."""
    raw,commitment=late.host.execution.reporting.body(guaranteed,assured)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
        body_override=raw,extrinsic_override=commitment)[0]


@owned_histories
def cases():
    """Neither code nor expiry invents a processed prerequisite; later independent work retains genuine priority."""
    result=[]
    for mode in ('create','checkpoint-panic'):
        for kind in ('cycle','unresolved-anchor'):
            for supplied in (11,12,23,24):
                parent=late.original(mode);initial=dict(parent);reports={};steps=[];events=[]
                for slot in SLOTS:
                    gs,ass=inputs(parent,slot,reports,kind)
                    validate_dependencies(parent,gs)
                    refused=[]
                    if slot==8:
                        bad=deepcopy(gs);bad[0]['layout']['prerequisites']=waves.waves.package('never-published-anchor')
                        waves.guests.population.resign(bad[0],waves.guests.rotation.credentials(parent,slot,slot)[0])
                        try:validate_dependencies(parent,bad)
                        except AssertionError as error:assert str(error)=='package/MissingDependency'
                        else:raise AssertionError('unpublished dependency accepted')
                        refused.append((seal_refusal(parent,slot,bad,ass),'package/MissingDependency'))

                    available=value_key('P',99,digest(late.late.code(mode))) in parent
                    def charge(sid,amount):
                        """Only an actual selected prefix invokes a guest; unavailable code charges zero."""
                        return 22 if sid==42 else late.late.pipeline.guest_gas(mode) if available else 0
                    plan=waves.projection(parent,mode,slot,ass,reports,charge=charge)
                    effects=[{sid:({} if sid!=99 or available else dict(charge=0,retained=False)) for sid in group} for group in plan['batches']]
                    payloads=((99,late.late.code(mode)),) if slot==supplied else ()
                    block,state=late.advance(parent,mode,slot,gs,ass,reports,payloads,processed=plan['processed'],
                        batches=plan['batches'],ready=plan['ready'],effects=effects)
                    events.append(dict(slot=slot,code_available_before=available,
                        processed=[wire[:32].hex() for wire in plan['processed']],remaining_gas=plan['remaining_gas']))
                    steps.append((block,state,refused));parent=state
                case=dict(name=mode+'-'+kind+'-supply-'+str(supplied),parameters=late.host.parameters(),initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.late.code(mode),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze signed dependency changes and every complete mathematical map before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
