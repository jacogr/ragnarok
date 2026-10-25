# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Select complete independently authored host/lifecycle histories for restart, trace and operator qualification."""
from functools import lru_cache
from copy import deepcopy
import current_stf_rotation_privileges_oracle as privileges
import current_stf_rotation_creation_oracle as creation
import current_stf_rotation_code_oracle as code
import current_stf_rotation_preimages_oracle as preimages
import current_stf_rotation_transfer_waves_oracle as waves
import current_stf_rotation_incarnations_oracle as incarnations
import current_stf_rotation_histories_oracle as histories

FAMILIES=(('privileges',privileges,0),('creation',creation,0),('code',code,0),
          ('preimages',preimages,11),('waves',waves,5),('incarnations',incarnations,6),('histories',histories,0))
SOURCES=tuple(module.FIXTURE for _,module,_ in FAMILIES)
NATIVE_DEFINES=incarnations.NATIVE_DEFINES


@lru_cache(maxsize=1)
def _selected_cases():
    """Derive the finite source selection once per process; cached maps stay private to this module."""
    result=[]
    for family,module,index in FAMILIES:
        case=module.cases()[index]
        result.append(dict(case,name=family+'-'+case['name']))
    return tuple(result)


def cases():
    """Return independently owned copies of whole derived histories; callers cannot mutate the cached expectations."""
    return deepcopy(_selected_cases())


def origins():
    """Make finite source selection explicit and frozen rather than implying arbitrary-operation coverage."""
    return [[family,index] for family,_,index in FAMILIES]
