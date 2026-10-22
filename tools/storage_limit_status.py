# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Parse bounded Linux process memory status without treating missing fields as zero."""
from storage_limit_budget import natural

FIELDS = ('VmSize','VmRSS','VmHWM','VmSwap')


def parse_status(raw):
    """Linux status memory units are literal kB (1024 bytes); unknown fields are ignored."""
    if type(raw) is not str or len(raw)>131072:
        raise ValueError('Invalid process status extent')
    result = {}; seen = set()
    for line in raw.splitlines():
        key,sep,value=line.partition(':')
        if not sep or key in seen:
            raise ValueError('Invalid or duplicate process status field')
        seen.add(key)
        # Optional kernel fields do not alter the required observation domain.
        if key in FIELDS:
            fields=value.split()
            if len(fields)!=2 or fields[1]!='kB':
                raise ValueError('Invalid process memory units')
            amount=natural(fields[0])*1024
            if amount >= 1<<63:
                raise ValueError('Process memory byte overflow')
            result[key]=amount
    if set(result)!=set(FIELDS):
        raise ValueError('Incomplete process memory status')
    return result
