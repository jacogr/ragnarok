# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact-residual report retention and pooled guest gas exits across changing rosters."""
from pathlib import Path
import current_stf_population_waves_oracle as waves
import current_stf_gas_exits_oracle as exits
import current_stf_budget_retention_oracle as retention
from reporting_scenario_oracle import collect

FIXTURE=Path(__file__).parent/'fixtures/current-stf-population-gas.json'
SOURCES=(*waves.SOURCES,exits.FIXTURE,retention.FIXTURE)
CASES=tuple((mode,'prefix',profile) for mode in ('create','checkpoint-panic') for profile in retention.PROFILES)+tuple(
    (mode,'exit',budget) for mode in waves.guests.MODES for budget in (1,1377))


def gas_limits(family,profile):
    """Literal budgets isolate299978/299979 residual admission or one/two/three pooled underfunded operands."""
    if family=='prefix':return retention.gas_limits(profile)
    limits={name:profile for name in ('B','C','D','E',*(f'{slot}-{core}' for slot in (12,23,24) for core in range(3)))}
    limits['A']=22;limits['24-0']=22
    return limits


def outcome(mode,sid,budget):
    """Halt costs22; literal write/yield/checkpoint charges and exceptional implication selection come from pinned GP equations."""
    return dict(charge=22,retained=False,exit='halt') if sid==42 else exits.outcome(mode,budget)


def effects(mode,plan,reports):
    """Each actual prefix pools service budgets once; output union retains any selected yielded commitment."""
    rows=[];yielded=False
    for prefix in plan['prefixes']:
        budgets={}
        for encoded in prefix:
            for row in reports[bytes.fromhex(encoded)]['digests']:
                budgets[row[0]]=budgets.get(row[0],0)+row[3]
        selected={sid:outcome(mode,sid,budget) for sid,budget in budgets.items()}
        yielded=yielded or any(sid==99 and result['retained'] for sid,result in selected.items())
        rows.append({sid:{key:result[key] for key in ('charge','retained')} for sid,result in selected.items()})
    return rows,yielded


def cases():
    """All reports enter through genuine guarantees/assurances; only mathematical successors become expected parents."""
    result=[]
    for mode,family,profile in CASES:
        parent=waves.guests.original(mode);initial=dict(parent);steps=[];reports={}
        for slot in waves.SLOTS:
            gs,ass=waves.inputs(parent,slot,True,reports,gas_limits=gas_limits(family,profile))
            plan=waves.projection(parent,mode,slot,ass,reports,charge=lambda sid,budget:outcome(mode,sid,budget)['charge'])
            selected,yielded=effects(mode,plan,reports)
            wire,after=waves.guests.advance(parent,mode,slot,gs,ass,reports,
                processed=plan['processed'],batches=plan['batches'],ready=plan['ready'],effects=selected,yielded=yielded)
            steps.append((wire,after,[]));parent=after
        result.append(dict(name=mode+'-'+family+'-'+str(profile),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Freeze exact maps, roots, gas-sensitive metadata, ready rings and outputs before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
