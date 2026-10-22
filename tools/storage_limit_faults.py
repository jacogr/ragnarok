# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Parse a single Linux proc stat record despite spaces and parentheses in the process name."""
from storage_limit_budget import natural


def parse_stat(raw):
    """Read self-only minor/major faults; child totals and unrelated proc counters stay separate."""
    if type(raw) is not str or len(raw)>131072:
        raise ValueError('Invalid proc stat extent')
    first=raw.find(' ('); last=raw.rfind(') ')
    if first<1 or last<first+2:
        raise ValueError('Invalid proc stat process identity')
    pid=natural(raw[:first]); fields=raw[last+2:].split()
    if pid==0 or len(fields)<22 or len(fields[0])!=1 or fields[0] not in 'RSDZTWtXxKPI':
        raise ValueError('Invalid proc stat fields')
    return dict(pid=pid,minor_faults=natural(fields[7]),major_faults=natural(fields[9]))
