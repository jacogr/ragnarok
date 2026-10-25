# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact residual admission, retained deferred work and expiry under changing code availability."""
from pathlib import Path
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_population_waves_oracle as waves
import current_stf_population_gas_oracle as gas
from state_layout_oracle import digest
from state_service_values_oracle import key as value_key
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-retention.json'
SOURCES=(late.FIXTURE,gas.FIXTURE,gas.retention.FIXTURE)
NATIVE_DEFINES=(*late.NATIVE_DEFINES,'lateRetention')


@owned_histories
def cases():
    """One declared unit separates immediate admission from retention; code availability controls subsequent actual budget."""
    result=[]
    for mode in ('create','checkpoint-panic'):
        for profile in gas.retention.PROFILES:
            for supplied in (11,12,13):
                parent=late.original(mode);initial=dict(parent);reports={};steps=[];events=[]
                for slot in waves.SLOTS:
                    gs,ass=waves.inputs(parent,slot,True,reports,gas_limits=gas.gas_limits('prefix',profile))
                    available=value_key('P',99,digest(late.late.code(mode))) in parent
                    def charge(sid,amount):
                        """Full-budget literals charge once per actual prefix; missing code consumes zero without changing declared admission."""
                        return 22 if sid==42 else late.late.pipeline.guest_gas(mode) if available else 0
                    plan=waves.projection(parent,mode,slot,ass,reports,charge=charge)
                    effects=[{sid:({} if sid!=99 or available else dict(charge=0,retained=False)) for sid in group} for group in plan['batches']]
                    payloads=((99,late.late.code(mode)),) if slot==supplied else ()
                    block,state=late.advance(parent,mode,slot,gs,ass,reports,payloads,processed=plan['processed'],
                        batches=plan['batches'],ready=plan['ready'],effects=effects)
                    events.append(dict(slot=slot,code_available_before=available,
                        **{key:plan[key] for key in ('prefixes','remaining_gas')},processed=[wire[:32].hex() for wire in plan['processed']]))
                    steps.append((block,state,[]));parent=state
                case=dict(name=mode+'-'+profile+'-supply-'+str(supplied),parameters=late.host.parameters(),
                    initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.late.code(mode),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Bind all complete maps and genuine signed inputs to pre-execution Gray Paper expectations."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
