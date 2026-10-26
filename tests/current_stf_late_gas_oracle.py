# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent missing-code skips versus genuine pooled gas exhaustion through deferred waves and population boundaries."""
from pathlib import Path
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_population_waves_oracle as waves
import current_stf_population_gas_oracle as gas
from state_layout_oracle import digest
from state_service_values_oracle import key as value_key
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-gas.json'
SOURCES=(late.FIXTURE,gas.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES


@owned_histories
def cases():
    """Same operands either skip unavailable code or spend their genuine pooled budget; code integration is strictly later."""
    result=[]
    for mode in late.late.pipeline.MODES:
        for supplied in (11,12):
            for budget in (1,1377):
                parent=late.original(mode);initial=dict(parent);reports={};steps=[];events=[]
                limits=gas.gas_limits('exit',budget)
                for slot in waves.SLOTS:
                    gs,ass=waves.inputs(parent,slot,True,reports,gas_limits=limits)
                    available=value_key('P',99,digest(late.late.code(mode))) in parent
                    def outcome(sid,amount):
                        """Use the pinned literal exit model only when code exists in the actual prior state."""
                        return gas.outcome(mode,sid,amount) if sid==42 or available else dict(charge=0,retained=False,exit='unavailable')
                    plan=waves.projection(parent,mode,slot,ass,reports,charge=lambda sid,amount:outcome(sid,amount)['charge'])
                    effects=[];exits=[];yielded=False
                    for prefix in plan['prefixes']:
                        budgets={}
                        for hashed in prefix:
                            for row in reports[bytes.fromhex(hashed)]['digests']:budgets[row[0]]=budgets.get(row[0],0)+row[3]
                        selected={sid:outcome(sid,amount) for sid,amount in budgets.items()}
                        effects.append({sid:{key:value[key] for key in ('charge','retained')} for sid,value in selected.items()})
                        exits.append(selected);yielded=yielded or any(sid==99 and value['retained'] for sid,value in selected.items())
                    payloads=((99,late.late.code(mode)),) if slot==supplied else ()
                    block,state=late.advance(parent,mode,slot,gs,ass,reports,payloads,processed=plan['processed'],
                        batches=plan['batches'],ready=plan['ready'],effects=effects,yielded=yielded)
                    events.append(dict(slot=slot,code_available_before=available,exits=exits,
                        **{key:plan[key] for key in ('prefixes','remaining_gas')},yielded=yielded))
                    steps.append((block,state,[]));parent=state
                case=dict(name=mode+'-supply-'+str(supplied)+'-budget-'+str(budget),parameters=late.host.parameters(),
                    initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.late.code(mode),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze full signed inputs and mathematical state maps before native gas/exit observations exist."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
