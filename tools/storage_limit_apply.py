# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Apply a finite Linux soft address-space limit only inside a dedicated disposable child."""
import platform
import resource
from storage_limit_budget import budget


def limits():
    """Represent inherited infinity explicitly rather than depending on its platform numeric sentinel."""
    return [None if v==resource.RLIM_INFINITY else v for v in resource.getrlimit(resource.RLIMIT_AS)]


def apply_cap(cap):
    """Never relax inherited bounds or alter the hard ceiling; unsupported hosts do not attempt mutation."""
    if cap is not None:
        budget(cap)
    before=limits(); system=platform.system()
    result=dict(system=system,requested=cap,inherited=before,effective=before)
    if cap is None:
        return dict(result,status='unchanged')
    if system!='Linux':
        return dict(result,status='unsupported')
    if any(value is not None and cap>value for value in before):
        return dict(result,status='refused',reason='inherited-bound')
    try:
        resource.setrlimit(resource.RLIMIT_AS,(cap,resource.RLIM_INFINITY if before[1] is None else before[1]))
    except (OSError,ValueError):
        return dict(result,status='refused',reason='setrlimit')
    result['effective']=limits()
    if result['effective']!=[cap,before[1]]:
        return dict(result,status='refused',reason='readback')
    return dict(result,status='applied')
