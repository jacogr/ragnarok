# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent deferred dependency waves, prior-roster release/clear and recursive guests across resizing."""
from pathlib import Path
import current_stf_population_guests_oracle as guests
import current_stf_dependency_waves_oracle as waves
from state_layout_oracle import chapter_key,digest
from reporting_scenario_oracle import collect

FIXTURE=Path(__file__).parent/'fixtures/current-stf-population-waves.json'
SOURCES=(*guests.SOURCES,waves.FIXTURE)
SLOTS=(2,8,9,10,11,12,13,14,22,23,24,25)


def guarantee(parent,core,slot,sid,name,prerequisites=(),lookups=(),gas=100000):
    """Author package/dependency/segment identities and re-sign the exact executable report with selected-roster keys."""
    item=guests.guarantee(parent,core,slot,sid)
    layout=item['layout'];package=waves.package(name)
    layout['header']=package+layout['header'][32:70]+digest(package+b'exports')+layout['header'][102:]
    layout['prerequisites']=b''.join(sorted(waves.package(n) for n in prerequisites))
    layout['lookup']=b''.join(waves.package(n)+digest(waves.package(n)+b'exports') for n in sorted(lookups,key=waves.package))
    row=list(layout['digests'][0]);row[3]=gas;layout['digests']=[tuple(row)]
    guests.population.resign(item,guests.rotation.credentials(parent,slot,slot)[0])
    return item


def inputs(parent,slot,release,reports, *, gas_limits=None):
    """B/C/D/E wait on a held A; later batches exercise three active cores and release-before-shrink."""
    specifications={8:[('A',0,42,(),()),('B',1,99,('A',),())],
        9:[('C',1,99,('A','B'),())],10:[('D',1,99,(),('C',))],
        11:[('E',1,99,('B','D'),('B',))]}.get(slot,[])
    if slot in (12,23,24):
        specifications=[(f'{slot}-{core}',core,42 if slot==24 and core==0 else 99,(),())
                        for core in range(2 if slot==24 else 3)]
    guaranteed=[]
    for name,core,sid,prerequisites,lookups in specifications:
        item=guarantee(parent,core,slot,sid,name,prerequisites,lookups,
                       100000 if gas_limits is None else gas_limits.get(name,100000))
        reports[item['report'][:32]]=item['layout'];guaranteed.append(item)
    count,bits={9:(5,2),10:(5,2),11:(5,2),12:(5 if release else 4,3),13:(7,7),
                24:(7 if release else 6,7),25:(5,3)}.get(slot,(0,0))
    assured=guests.rotation.assurances(parent,count,bits) if count else []
    return guaranteed,assured


def projection(parent,mode,slot,assured,reports, *, charge=None):
    """GP E/Q and actual-gas accseq use each distinct prior/current/previous population explicitly."""
    crossed=slot//12>int.from_bytes(parent[chapter_key(11)],'little')//12
    active=guests.population.active_after(parent,slot)
    previous=guests.epoch.roster(parent[chapter_key(8 if crossed else 9)])
    return waves.plan(parent,mode,slot,assured,reports,cores=3,current=len(active),
        previous=len(previous),prior=len(guests.epoch.roster(parent[chapter_key(8)])),charge=charge)


def cases():
    """Expected parents recurse through mathematical successors only; admitted reports alone populate the wave dictionary."""
    result=[]
    for mode in guests.MODES:
        for release in (True,False):
            parent=guests.original(mode);initial=dict(parent);steps=[];reports={}
            for slot in SLOTS:
                gs,ass=inputs(parent,slot,release,reports)
                plan=projection(parent,mode,slot,ass,reports)
                wire,after=guests.advance(parent,mode,slot,gs,ass,reports,
                    processed=plan['processed'],batches=plan['batches'],ready=plan['ready'])
                steps.append((wire,after,[]));parent=after
            result.append(dict(name=mode+('-release' if release else '-resize-clear'),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Freeze complete dependency/effect/history answers before the native candidate program starts."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
