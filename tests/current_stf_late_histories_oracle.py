# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent longer histories compose delayed code, cancellation, sparse allowances and repeated real population promotions."""
from pathlib import Path
from owned_history_cache import owned_histories
import current_stf_late_offenders_oracle as excluded
import current_stf_late_allowances_oracle as allowances
import current_stf_rotation_histories_oracle as history
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as metadata
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-histories.json'
SOURCES=(excluded.FIXTURE,allowances.FIXTURE,history.FIXTURE)
NATIVE_DEFINES=(*excluded.NATIVE_DEFINES,'lateRetention','lateHistories')


def guarantees(parent,slot,family,offenders):
    """Later work uses actual surviving credentials and current service-code identities, with no rewritten earlier reports."""
    if family=='allowances':return [allowances.late.host.execution.guarantee(parent,0,slot,42)]
    result=[]
    for core in excluded.offender.eligible(parent,slot,slot,offenders):
        item=excluded.offender.population.guarantee(parent,core,slot,slot,slot,offenders=offenders)
        sid=42 if core==0 else 99;row=list(item['layout']['digests'][0]);row[0]=sid
        row[1]=metadata(parent[chapter_service(255,sid)],105)[0];row[3]=100000
        item['layout']['digests']=[tuple(row)];item['layout']['prerequisites']=b''
        excluded.offender.population.resign(item,excluded.offender.rotation.credentials(parent,slot,slot)[0]);result.append(item)
    return result


@owned_histories
def cases():
    """Continue eight actual mixed source histories through two more full promotions without native successor seeding."""
    result=[]
    sources=[('offenders',case) for case in excluded.cases() if case['name'].startswith(('create-','checkpoint-panic-')) and case['name'].endswith('-supply-17')]
    sources.extend(('allowances',case) for case in allowances.cases() if case['name'].startswith(('halt-','checkpoint-panic-')) and case['name'].endswith(('-source-12','-source-24')))
    for family,source in sources:
        steps=list(source['steps']);events=list(source['events']);parent=dict(steps[-1][1]);reports={};later=[]
        mode=source['name'].split('-timing-' if family=='offenders' else '-source-')[0]
        for phase,window in enumerate(history.LATER_WINDOWS):
            slot=next(slot for slot in window if history.signing_key(parent,slot) in excluded.offender.epoch.PUBLIC)
            offenders=excluded.offender.verdict.sets(parent[chapter_key(5)])[3]
            gs=guarantees(parent,slot,family,offenders) if phase%3 in (0,1) else []
            for item in gs:reports[item['report'][:32]]=item['layout']
            pending=excluded.offender.reporting.pending(parent[chapter_key(10)],3,9)
            bits=sum(1<<core for core,item in enumerate(pending) if item is not None)
            count=2*len(excluded.offender.epoch.roster(parent[chapter_key(8)]))//3+1
            ass=excluded.offender.assurances(parent,count,bits) if phase%3 in (1,2) and bits else []
            if family=='offenders':
                block,state,event=excluded.advance(parent,mode,slot,gs,ass,excluded.offender.verdict.payload(),reports,())
            else:
                block,state,event=allowances.advance(parent,mode,slot,gs,ass,reports,())
            steps.append((block,state,[]));events.append(event);later.append(event);parent=state
        case=dict(source,name=family+'-continued-'+source['name'],steps=steps,events=events,family=family,later=later)
        case['inventory'],case['inventory_rows']=declaration(case,(42,99))
        result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze all extended signed inputs and exact maps before any native execution observes the new histories."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
