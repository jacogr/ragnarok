# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Canonical finite resource quantities and fixed child address-space budgets."""
import re

MIB = 1024*1024
MIN_CAP = 128*MIB
MAX_CAP = 2*1024*MIB
CAPS = (128*MIB,512*MIB,1024*MIB)


def natural(value):
    """Reject signs, whitespace, booleans, leading zeros and unbounded imported counters."""
    if type(value) is not str or re.fullmatch(r'0|[1-9][0-9]{0,18}',value) is None or int(value) >= 1<<63:
        raise ValueError('Invalid canonical resource quantity')
    return int(value)


def budget(value):
    """Accept a fixed MiB-aligned cap; callers cannot request unbounded pressure allocations."""
    if type(value) is not int or not MIN_CAP <= value <= MAX_CAP or value%MIB:
        raise ValueError('Invalid bounded address-space ceiling')
    return value
