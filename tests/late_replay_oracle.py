# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Select explicitly named complete independent late-code histories for checkpoint, trace and operator qualification."""
from owned_history_cache import owned_histories
import current_stf_late_dependencies_oracle as dependencies
import current_stf_late_gas_oracle as gas
import current_stf_late_retention_oracle as retention
import current_stf_late_cycles_oracle as cycles
import current_stf_late_relevance_oracle as relevance
import current_stf_late_reactivation_oracle as reactivation
import current_stf_late_upgrades_oracle as upgrades
import current_stf_late_incarnations_oracle as incarnations
import current_stf_late_allowances_oracle as allowances
import current_stf_late_offenders_oracle as offenders
import current_stf_late_histories_oracle as histories

FAMILIES=(('dependencies',dependencies,'checkpoint-panic-release-12'),
    ('gas',gas,'create-supply-12-budget-1377'),('retention',retention,'create-serial-supply-13'),
    ('cycles',cycles,'checkpoint-panic-cycle-supply-24'),('relevance',relevance,'forget-checkpoint-solicit-panic-at-12'),
    ('reactivation',reactivation,'halt-edit-4802-supply-4804'),
    ('upgrades',upgrades,'missing-target-code-exact-residual-fit-supply-11'),
    ('incarnations',incarnations,'rebind-supply-24'),('allowances',allowances,'checkpoint-panic-source-24'),
    ('offenders',offenders,'create-timing-0-supply-17'),
    ('histories-offenders',histories,'offenders-continued-checkpoint-panic-timing-1-supply-17'),
    ('histories-allowances',histories,'allowances-continued-halt-source-12'))
SOURCES=tuple(dict.fromkeys(module.FIXTURE for _,module,_ in FAMILIES))
NATIVE_DEFINES=histories.NATIVE_DEFINES


@owned_histories
def cases():
    """Select whole named histories without dropping unfinished work, rewriting inputs or exposing cached mutable expected parents."""
    result=[]
    for family,module,name in FAMILIES:
        selected=[(index,case) for index,case in enumerate(module.cases()) if case['name']==name]
        assert len(selected)==1
        index,case=selected[0]
        result.append(dict(case,name=family+'-'+name,source_index=index,source_name=case['name']))
    return result


def origins():
    """Freeze exact source identities rather than relying on a mutable ordinal or implying arbitrary-history coverage."""
    return [[family,name] for family,_,name in FAMILIES]
