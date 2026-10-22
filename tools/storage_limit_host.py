# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bounded read-only host/process memory snapshots with explicit unavailable receipts."""
import json
from pathlib import Path
import platform
from storage_limit_status import parse_status
from storage_limit_faults import parse_stat
from storage_limit_psi import parse_psi
from storage_limit_cgroup import FILES,resolve,parse_files


def read(path):
    """Cap pseudo-file reads before parsing; no kernel control is opened for writing."""
    with Path(path).open('r') as stream:
        raw=stream.read(131073)
    if len(raw)>131072:
        raise ValueError('Memory telemetry extent exceeded')
    return raw


def capture(path,parser):
    """An absent, refused or malformed interface remains unavailable rather than zero."""
    try:
        raw=read(path)
        return dict(status='available',raw=raw,value=parser(raw))
    except OSError as error:
        return dict(status='unavailable',reason='os-error',errno=error.errno)
    except ValueError:
        return dict(status='unavailable',reason='malformed')


def cgroup():
    """Only the currently visible unified cgroup is observed; ancestors are not mutated or inferred."""
    try:
        membership=read('/proc/self/cgroup'); mounts=read('/proc/self/mountinfo')
        scope=resolve(membership,mounts)
        raw={name:read(Path(scope)/name) for name in FILES}
        return dict(status='available',membership=membership,mountinfo=mounts,scope=scope,raw=raw,value=parse_files(raw))
    except OSError as error:
        return dict(status='unavailable',reason='os-error',errno=error.errno)
    except ValueError:
        return dict(status='unavailable',reason='malformed')


def snapshot():
    """Linux process and shared pressure context is optional; other hosts state unsupported explicitly."""
    system=platform.system()
    if system!='Linux':
        return dict(system=system,status='unsupported')
    return dict(system=system,status='observed',process=capture('/proc/self/status',parse_status),
                faults=capture('/proc/self/stat',parse_stat),psi=capture('/proc/pressure/memory',parse_psi),cgroup=cgroup())


def unavailable(value):
    """Only bounded source-owned refusal categories may stand in for unavailable observations."""
    if type(value) is not dict or value.get('status')!='unavailable':
        raise ValueError('Invalid unavailable telemetry receipt')
    reason=value.get('reason'); expected={'status','reason'}|({'errno'} if reason=='os-error' else set())
    if set(value)!=expected or reason not in ('os-error','malformed') or ('errno' in value and
            (type(value['errno']) is not int or not 1<=value['errno']<=4096)):
        raise ValueError('Invalid unavailable telemetry reason')


def validate_snapshot(value):
    """Reparse each raw available interface and validate unavailable categories without opening report paths."""
    if type(value) is not dict or value.get('system') not in ('Linux','Darwin'):
        raise ValueError('Invalid memory telemetry host')
    if value['system']!='Linux':
        if value!={'system':'Darwin','status':'unsupported'}:
            raise ValueError('Invalid unsupported telemetry')
        return value
    if set(value)!= {'system','status','process','faults','psi','cgroup'} or value['status']!='observed':
        raise ValueError('Incomplete Linux memory telemetry')
    for key,parser in (('process',parse_status),('faults',parse_stat),('psi',parse_psi),('cgroup',parse_files)):
        row=value[key]
        if type(row) is not dict:
            raise ValueError('Invalid telemetry interface')
        if row.get('status')!='available':
            unavailable(row)
            continue
        expected={'status','raw','value'}|({'membership','mountinfo','scope'} if key=='cgroup' else set())
        if set(row)!=expected or json.dumps(parser(row['raw']),sort_keys=True)!=json.dumps(row['value'],sort_keys=True):
            raise ValueError('Substituted memory telemetry')
        if key=='cgroup' and resolve(row['membership'],row['mountinfo'])!=row['scope']:
            raise ValueError('Substituted cgroup namespace')
    return value
