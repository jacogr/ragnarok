# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Complete independently authored replay chains cover each dynamic-roster state family; no native observation participates."""
import current_stf_offender_reporting_oracle as offenders
import current_stf_population_guests_oracle as guests
import current_stf_ticket_reporting_oracle as tickets
import current_stf_population_waves_oracle as waves
import current_stf_population_gas_oracle as gas
import current_stf_population_anchors_oracle as anchors

FAMILIES=(('offenders',offenders,(0,)),('guests',guests,(0,1,2)),('tickets',tickets,(0,)),
          ('waves',waves,(0,1)),('gas',gas,(2,)),('anchors',anchors,(1,)))
SOURCES=tuple(module.FIXTURE for _,module,_ in FAMILIES)


def cases():
    """Select whole qualified chains, preserving all their transitions/refusals and explicit parameters."""
    result=[]
    for family,module,selection in FAMILIES:
        selected=module.cases(selection) if module in (waves,gas) else [case for i,case in enumerate(module.cases()) if i in selection]
        assert len(selected)==len(selection)
        for case in selected:result.append(dict(case,name=family+'-'+case['name']))
    return result


def origins():
    """Return fixed source-case identities so replay cannot quietly skip difficult transitions within a chain."""
    return [(family,index) for family,_,selection in FAMILIES for index in selection]
