# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent late-code availability through deferred dependency waves, resize clearing and actual-gas continuation."""
from pathlib import Path
import current_stf_late_rotation_oracle as late
import current_stf_population_waves_oracle as waves
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration
from state_layout_oracle import chapter_key,digest
from state_service_values_oracle import key as value_key

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-dependencies.json'
SOURCES=(late.FIXTURE,waves.FIXTURE)
NATIVE_DEFINES=late.NATIVE_DEFINES
SUPPLIES=(11,12,13)


def cases():
    """Whole dependency graphs wait for actual A release; code arrival cannot unblock or replay a report by itself."""
    result=[]
    for mode in late.late.pipeline.MODES:
        for release in (True,False):
            for supplied in SUPPLIES:
                parent=late.original(mode);initial=dict(parent);reports={};steps=[];events=[]
                for slot in waves.SLOTS:
                    gs,ass=waves.inputs(parent,slot,release,reports)
                    available=value_key('P',99,digest(late.late.code(mode))) in parent
                    def charge(sid,budget):
                        """A missing-code invocation consumes zero even when its complete operands are processed."""
                        return 22 if sid==42 else late.late.pipeline.guest_gas(mode) if available else 0
                    plan=waves.projection(parent,mode,slot,ass,reports,charge=charge)
                    effects=[{sid:({} if sid!=99 or available else dict(charge=0,retained=False)) for sid in group} for group in plan['batches']]
                    payloads=((99,late.late.code(mode)),) if slot==supplied else ()
                    block,state=late.advance(parent,mode,slot,gs,ass,reports,payloads,
                        processed=plan['processed'],batches=plan['batches'],ready=plan['ready'],effects=effects)
                    events.append(dict(slot=slot,code_available_before=available,
                        **{key:plan[key] for key in ('waves','prefixes','remaining_gas')},
                        processed=[wire[:32].hex() for wire in plan['processed']]))
                    steps.append((block,state,[]));parent=state
                case=dict(name=mode+('-release-' if release else '-clear-')+str(supplied),parameters=late.host.parameters(),
                    initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(late.late.code(mode),))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze every mathematical wave, signed block and complete map before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
