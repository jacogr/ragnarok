# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent repeated offender-filtered population epochs preserve actual credentials and complete reporting state."""
from pathlib import Path
import current_stf_offender_reporting_oracle as offender
import rotation_host_oracle as host
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration
from state_layout_oracle import chapter_key

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-histories.json'
SOURCES=(offender.FIXTURE,)
NATIVE_DEFINES=('rotationHosts','rotationLifecycle','rotationCode','rotationRequests','rotationIncarnations')
LATER_WINDOWS=((34,35),(36,37),(38,39),(46,47),(48,49),(50,51))


def signing_key(parent,slot):
    """Derive fallback selection directly; a null record has no secret and cannot author a valid block."""
    epoch=offender.epoch
    if slot//12>int.from_bytes(parent[chapter_key(11)],'little')//12:
        active=epoch.consensus(parent[chapter_key(4)])[0]
        seed=parent[chapter_key(6)][32:64]
        index=int.from_bytes(offender.digest(seed+(slot%12).to_bytes(4,'little'))[:4],'little')%len(active)
        return active[index][:32]
    pending,root,kind,schedule,accumulated=epoch.consensus(parent[chapter_key(4)])
    assert kind==1
    return schedule[slot%12]


def cases():
    """Continue both genuine offence timings into two more promotions of the honestly filtered staging roster."""
    result=[]
    for original in offender.cases():
        steps=list(original['steps']);parent=steps[-1][1]
        for phase,window in enumerate(LATER_WINDOWS):
            slot=next(slot for slot in window if signing_key(parent,slot) in offender.epoch.PUBLIC)
            disputes=offender.verdict.payload()
            offenders=offender.verdict.sets(parent[chapter_key(5)])[3]
            gs=[]
            if phase%3 in (0,1):
                for core in offender.eligible(parent,slot,slot,offenders):
                    gs.append(offender.population.guarantee(parent,core,slot,slot,slot,offenders=offenders))
            pending=offender.reporting.pending(parent[chapter_key(10)],3,9)
            bits=sum(1<<core for core,item in enumerate(pending) if item is not None)
            ass=offender.assurances(parent,5,bits) if phase%3 in (1,2) and bits else []
            block,state=offender.advance(parent,slot,gs,ass,disputes)
            steps.append((block,state,[]));parent=state
        case=dict(original,name='continued-'+original['name'],steps=steps,parameters=host.parameters())
        case['inventory'],case['inventory_rows']=declaration(case,(42,99))
        result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze full maps and genuine signatures before native execution; no null signing secret is invented."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
