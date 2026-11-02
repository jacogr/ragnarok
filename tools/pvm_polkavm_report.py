# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Strict pinned PolkaVM backend and parent/worker CPU measurement receipts."""
import statistics
from pvm_benchmark_report import NAMES


def number(value):
    """Only canonical bounded unsigned counters can supply a timing or identity."""
    if (not value.isascii() or not value.isdecimal() or len(value)>20
            or len(value)>1 and value.startswith('0') or int(value)>=2**64):
        raise ValueError('invalid reference counter')
    return int(value)


def parse_clock_control(output):
    """Cross-check remote task CPU against independent self CPU before accepting timings."""
    fields=output.strip().split(',')
    if len(fields)!=5 or fields[0]!='REFERENCE_CLOCK_CONTROL':raise ValueError('missing child CPU control')
    parent,worker,total,own=map(number,fields[1:])
    if min(worker,own)<20000000 or worker<=parent*2 or total!=parent+worker or abs(worker-own)>max(1000000,own//20):
        raise ValueError('missing, duplicated or uncalibrated task CPU')
    return dict(parent=parent,worker=worker,total=total,child_self_cpu=own)


def parse(output, backend, family, limit=0, event_bytes=0, count=13):
    """Require actual compiler code/worker CPU and every fully validated legacy sample."""
    if backend not in ('interpreter','compiler'):
        raise ValueError('unknown reference backend')
    if count not in (1,13):raise ValueError('unsupported reference sample count')
    synthetic=family=='synthetic'
    if synthetic and count!=13:raise ValueError('synthetic corpus requires thirteen calls')
    doom=family in ('init','tick')
    if not synthetic and not doom and family not in ('sieve','minimal','memset','pinky'):
        raise ValueError('unknown reference family')
    labels=[f'synthetic-{i}' for i in range(len(NAMES))] if synthetic else [
        f'doom-{family}' if doom else f'{family}-{limit}']
    modules={};samples={label:[] for label in labels};legacy={label:[] for label in labels}
    guest=0;finished=0
    for line in output.splitlines():
        f=line.split(',')
        if f[0]=='REFERENCE_MODULE':
            if len(f)!=6 or f[2:4]!=[backend,backend]:
                raise ValueError('missing or substituted reference engine')
            key=f[1]
            expected=labels if synthetic else ['doom' if doom else 'guest']
            if key not in expected or key in modules:
                raise ValueError('foreign or duplicate module')
            code,cpu=map(number,f[4:])
            if not cpu or (code>0)!=(backend=='compiler'):
                raise ValueError('compiler code or preparation missing')
            modules[key]=dict(code_bytes=code,prepare_parent_cpu_ns=cpu)
        elif f[0]=='REFERENCE_CPU':
            if len(f)!=7 or f[1] not in samples:
                raise ValueError('foreign reference sample')
            label=f[1];sample,parent,worker,total,used=map(number,f[2:])
            module=label if synthetic else 'doom' if doom else 'guest'
            if module not in modules or finished:
                raise ValueError('CPU sample without prior module or after terminal receipt')
            if sample!=len(samples[label]) or sample>=count or parent<=0 or total!=parent+worker:
                raise ValueError('duplicate, unordered or incorrect CPU sample')
            if used!=int(backend=='compiler') or (worker>0)!=(backend=='compiler'):
                raise ValueError('sandbox guest CPU missing or duplicated')
            samples[label].append(dict(parent_cpu_ns=parent,worker_cpu_ns=worker,cpu_ns=total))
        elif synthetic:
            f=line.split('\t')
            if f[0]=='unavailable':raise ValueError('required reference profile unavailable: '+line)
            if len(f)!=5 or f[0]!='sample':raise ValueError('unexpected synthetic reference output')
            row,sample,wall,prepare=map(number,f[1:])
            if row>=len(labels):raise ValueError('foreign synthetic workload')
            label=labels[row]
            if sample!=len(legacy[label]) or sample>=count or not wall or not prepare:
                raise ValueError('incomplete synthetic execution')
            legacy[label].append(dict(wall_ns=wall,prepare_wall_ns=prepare))
        elif doom:
            if f[:3]==['DOOM_SAMPLE','reference',family] and len(f)==6:
                sample,cpu,wall=map(number,f[3:]);label=labels[0]
                if sample!=len(legacy[label]) or sample>=count or not cpu or not wall:
                    raise ValueError('incomplete DOOM execution')
                legacy[label].append(dict(cpu_ns=cpu,wall_ns=wall))
            elif f==['DOOM_OK','reference',family,str(event_bytes)]:finished+=1
            else:raise ValueError('unexpected DOOM reference output')
        elif f==['GUEST',family] and family!='sieve':guest+=1
        elif len(f)==6 and f[:3]==['SIEVE','polkavm_'+backend,str(limit)]:
            sample,wall,cpu=map(number,f[3:]);label=labels[0]
            if sample!=len(legacy[label]) or sample>=count or not cpu or not wall:
                raise ValueError('incomplete guest execution')
            legacy[label].append(dict(cpu_ns=cpu,wall_ns=wall))
        else:raise ValueError('unexpected guest reference output')
    if len(modules)!=(len(labels) if synthetic else 1) or finished!=int(doom) or guest!=int(not synthetic and not doom and family!='sieve'):
        raise ValueError('incomplete module, guest or terminal receipt')
    result={}
    for i,label in enumerate(labels):
        if len(samples[label])!=count or len(legacy[label])!=count:
            raise ValueError('incomplete reference sample sequence')
        for cpu,old in zip(samples[label],legacy[label]):
            if 'cpu_ns' in old and old['cpu_ns']!=cpu['cpu_ns']:
                raise ValueError('legacy CPU and worker accounting disagree')
            cpu['wall_ns']=old['wall_ns']
        key=NAMES[i] if synthetic else f'doom-{family}' if doom else f'{family}-{limit}'
        result[key]=dict(samples=samples[label],module=modules[label if synthetic else 'doom' if doom else 'guest'],
            warm_cpu_ns=statistics.median(x['cpu_ns'] for x in (samples[label][3:] if count==13 else samples[label])),
            warm_wall_ns=statistics.median(x['wall_ns'] for x in (samples[label][3:] if count==13 else samples[label])))
    return result


def summarize(runs):
    """Keep per-pair ratios, cold calls and separate parent/worker distributions."""
    result={}
    names=sorted(set().union(*(row['cases'] for row in runs)))
    for name in names:
        rows=[row for row in runs if name in row['cases']]
        pairs={}
        for row in rows:
            pair=pairs.setdefault(row['pair'],{})
            if row['backend'] in pair:raise ValueError('duplicate reference backend in process pair')
            pair[row['backend']]=row['cases'][name]
        if any(set(pair)!={'interpreter','compiler'} for pair in pairs.values()):
            raise ValueError('unpaired reference observations')
        ratios=[pair['compiler']['warm_cpu_ns']/pair['interpreter']['warm_cpu_ns'] for pair in pairs.values()]
        wall=[pair['compiler']['warm_wall_ns']/pair['interpreter']['warm_wall_ns'] for pair in pairs.values()]
        result[name]=dict(native_per_interpreted=statistics.median(ratios),
            ratio_of_process_medians=statistics.median(row['cases'][name]['warm_cpu_ns'] for row in rows if row['backend']=='compiler')/statistics.median(row['cases'][name]['warm_cpu_ns'] for row in rows if row['backend']=='interpreter'),
            interpreted_per_native=1/statistics.median(ratios),pair_cpu_ratios=ratios,
            native_per_interpreted_wall=statistics.median(wall),pair_wall_ratios=wall,
            process_cpu={backend:[row['cases'][name]['warm_cpu_ns'] for row in rows if row['backend']==backend]
                         for backend in ('interpreter','compiler')})
    return result
