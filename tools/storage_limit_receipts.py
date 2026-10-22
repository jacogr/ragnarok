# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Strict admission of read-back child limit receipts and actual allocation probe witnesses."""
from storage_limit_budget import budget,MIB


def pair(value):
    """Infinity is None; finite inherited bounds reject booleans, negatives and overflows."""
    if type(value) is not list or len(value)!=2 or any(v is not None and (type(v) is not int or not 0<=v<1<<63) for v in value):
        raise ValueError('Invalid inherited memory limits')
    if value[1] is not None and (value[0] is None or value[0]>value[1]):
        raise ValueError('Invalid memory limit ordering')


def validate_limit(value,cap):
    """An applied receipt is Linux-only, retains the hard limit and cannot relax inherited bounds."""
    if cap is not None:
        budget(cap)
    if type(value) is not dict or value.get('system') not in ('Linux','Darwin') or type(value.get('requested')) is not type(cap) or value['requested']!=cap:
        raise ValueError('Invalid child limit identity')
    pair(value.get('inherited')); pair(value.get('effective'))
    status=value.get('status'); extra={'reason'} if status=='refused' else set()
    if set(value)!= {'system','requested','inherited','effective','status'}|extra:
        raise ValueError('Invalid child limit fields')
    before=value['inherited']; after=value['effective']
    if status=='applied':
        if cap is None or value['system']!='Linux' or after!=[cap,before[1]] or any(v is not None and cap>v for v in before):
            raise ValueError('Unproven child limit application')
    elif status=='unchanged':
        if cap is not None or after!=before:
            raise ValueError('Changed unrestricted child limit')
    elif status=='unsupported':
        if cap is None or value['system']=='Linux' or after!=before:
            raise ValueError('Invalid unsupported child limit')
    elif status=='refused':
        if cap is None or value['system']!='Linux' or value['reason'] not in ('inherited-bound','setrlimit','readback'):
            raise ValueError('Invalid refused child limit')
        if value['reason']!='readback' and after!=before:
            raise ValueError('Refused limit altered bounds')
    else:
        raise ValueError('Unknown child limit status')
    return value


def validate_probe(value,cap):
    """Only both a touched positive map and a failed over-ceiling map establish probe enforcement."""
    if type(value) is not dict:
        raise ValueError('Invalid memory probe')
    limit=validate_limit(value.get('limit'),cap); status=value.get('status')
    page=value.get('page_bytes')
    if type(value.get('positive_bytes')) is not int or value['positive_bytes']!=MIB or type(page) is not int or not 1024<=page<=MIB or page&(page-1):
        raise ValueError('Invalid memory probe positive extent')
    base={'limit','positive_bytes','page_bytes','status'}
    if status=='enforced':
        if set(value)!=base|{'refusal','negative_bytes'} or limit['status']!='applied' or value['refusal'] not in ('ENOMEM','MemoryError') or type(value['negative_bytes']) is not int or value['negative_bytes']!=cap:
            raise ValueError('Invalid memory probe refusal')
    elif status=='not-enforced':
        if set(value)!=base|{'negative_bytes'} or limit['status']!='applied' or type(value['negative_bytes']) is not int or value['negative_bytes']!=cap:
            raise ValueError('Invalid unproven enforcement')
    elif status=='unavailable':
        if limit['status']=='applied':
            if set(value)!=base|{'reason'} or value['reason']!='positive-allocation':
                raise ValueError('Missing positive allocation failure')
        elif set(value)!=base:
            raise ValueError('Invalid unavailable memory probe fields')
    else:
        raise ValueError('Unknown memory probe status')
    return value
