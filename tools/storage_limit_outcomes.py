# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Classify actual limited-child exits without guessing OOM, paging or allocation causality."""
from storage_limit_receipts import validate_limit
from storage_resource_validation import validate_counters


def classify(value,cap):
    """A successful exit still needs independent native parsing; SIGKILL never proves an OOM kill."""
    if type(value) is not dict or set(value)!= {'exit_code','limit','resources'}:
        raise ValueError('Invalid limited-child observation')
    code=value['exit_code'];limit=validate_limit(value['limit'],cap);validate_counters(value['resources'])
    if type(code) is not int or not -127<=code<=255:
        raise ValueError('Invalid limited-child exit code')
    if limit['status'] not in ('unchanged','applied'):
        if code!=77:
            raise ValueError('Unavailable child limit executed a workload')
        return 'unavailable'
    if code<0:
        return 'signal'
    if code==0:
        return 'completed'
    return 'nonzero-exit'
