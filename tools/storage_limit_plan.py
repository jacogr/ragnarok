# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Fixed paired fresh-reopen experiments; no adaptive allocation growth or hidden sampling."""
from storage_limit_budget import CAPS

CASES=tuple((backend,count) for backend in ('journal','managed') for count in (32768,131072))
PHASES=(('before',None),*((str(cap),cap) for cap in CAPS),('after',None))
POLICY='child-local RLIMIT_AS soft ceiling; unchanged OS cache; no paging or OOM attribution'


def phases():
    """Every namespace has an unrestricted control before and after all declared bounded ceilings."""
    return [dict(name=name,cap=cap) for name,cap in PHASES]
