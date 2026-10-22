# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Resolve the current unified cgroup namespace and parse read-only local memory controls."""
from pathlib import PurePosixPath
from storage_limit_budget import natural

FILES=('memory.current','memory.max','memory.high','memory.swap.current','memory.swap.max','memory.events')


def scalar(raw,unlimited=False):
    """Only the kernel's literal max token denotes unlimited; zero remains a measured bound."""
    if type(raw) is not str or len(raw)>128 or not raw.endswith('\n') or raw.count('\n')!=1:
        raise ValueError('Invalid cgroup scalar')
    value=raw[:-1]
    return None if unlimited and value=='max' else natural(value)


def events(raw):
    """Require the stable memory event counters while accepting new canonical kernel counters."""
    if type(raw) is not str or len(raw)>4096:
        raise ValueError('Invalid cgroup event extent')
    result={}
    for line in raw.splitlines():
        parts=line.split()
        if len(parts)!=2 or not parts[0].replace('_','').isalpha() or parts[0] in result:
            raise ValueError('Invalid cgroup event row')
        result[parts[0]]=natural(parts[1])
    if not {'low','high','max','oom','oom_kill'}<=set(result):
        raise ValueError('Incomplete cgroup memory events')
    return result


def resolve(membership,mountinfo):
    """Resolve one cgroup2 mount, respecting mount roots; reject escaping or ambiguous namespaces."""
    if any(type(v) is not str or len(v)>131072 for v in (membership,mountinfo)):
        raise ValueError('Invalid cgroup namespace extent')
    rows=[line[3:] for line in membership.splitlines() if line.startswith('0::')]
    if len(rows)!=1:
        raise ValueError('Unavailable unified cgroup membership')
    member=PurePosixPath(rows[0])
    if not member.is_absolute() or '..' in member.parts or str(member)!=rows[0]:
        raise ValueError('Invalid cgroup member path')
    candidates=[]
    for line in mountinfo.splitlines():
        left,sep,right=line.partition(' - ')
        kind=right.split()
        if sep and not kind:
            raise ValueError('Missing cgroup mount filesystem')
        if sep and kind[0]=='cgroup2':
            fields=left.split()
            if len(fields)<6:
                raise ValueError('Invalid cgroup mount fields')
            root,mount=map(PurePosixPath,fields[3:5])
            # Escaped mount paths are explicitly unavailable rather than guessed or unescaped.
            if any(not p.is_absolute() or '..' in p.parts or '\\' in str(p) for p in (root,mount)):
                raise ValueError('Unsupported cgroup mount path')
            if member==root or root in member.parents:
                candidates.append(str(mount/member.relative_to(root)))
    if len(candidates)!=1:
        raise ValueError('Ambiguous or unavailable cgroup2 mount')
    return candidates[0]


def parse_files(raw):
    """Local memory limits may be weaker than ancestor limits; do not infer effective headroom."""
    if type(raw) is not dict or set(raw)!=set(FILES):
        raise ValueError('Incomplete cgroup memory context')
    return {name: events(value) if name=='memory.events' else scalar(value,name in ('memory.max','memory.high','memory.swap.max'))
            for name,value in raw.items()}
