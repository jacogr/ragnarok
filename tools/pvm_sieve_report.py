# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete sieve observations and retain CPU/wall distributions without filtering noise."""
import statistics
import re

from pvm_benchmark_report import ACTIVE_ENGINES

ENGINES=ACTIVE_ENGINES
LIMITS=(1000,10000,100000,10000000)
SAMPLES=13


def limits_for_guest(guest):
    """Keep workload sizes explicit: full sieve range, bounded loops, and one complete Pinky frame."""
    if guest=='sieve':return LIMITS
    if guest in ('minimal','memset'):return (1000,100000)
    if guest=='pinky':return (1,)
    raise ValueError('Unknown checked guest family')


def parse_output(output,engine,limit,samples=SAMPLES):
    """Accept one ordered, complete pass; reject extra output, duplicate and nonpositive samples."""
    if type(samples) is not int or samples not in (1, SAMPLES):
        raise ValueError("Unsupported sieve sample count")
    if engine not in ENGINES or limit not in (*LIMITS,1):
        raise ValueError("Unknown sieve engine or limit")
    rows=[]
    for line in output.splitlines():
        # Native output is a strict protocol, not an opportunistic scan of successful-looking lines.
        fields=line.split(',')
        if len(fields)!=6 or fields[:3]!=['SIEVE',engine,str(limit)]:
            raise ValueError('Unexpected sieve sample: '+line[:120])
        if any(not value.isascii() or not value.isdecimal() for value in fields[3:]):
            raise ValueError('Invalid sieve sample integer')
        sample,wall,cpu=map(int,fields[3:])
        if sample!=len(rows) or wall<=0 or cpu<=0:
            raise ValueError('Unordered or nonpositive sieve sample')
        rows.append(dict(sample=sample,wall_ns=wall,cpu_ns=cpu))
    if len(rows)!=samples:
        raise ValueError('Incomplete sieve sample pass')
    return rows


def validate_preparation(item):
    """Revalidate typed structured preparation evidence before rendering cold-cost claims."""
    keys={'cpu_ns','wall_ns','code_bytes','block_count','payload_bytes','cycle_limit'}
    if (not isinstance(item,dict) or set(item)!=keys or any(type(v) is not int or v<=0 for v in item.values())
            or max(item['cpu_ns'],item['wall_ns'])>=(1<<63)
            or item['block_count']>min(item['code_bytes'],100000)
            or item['payload_bytes']!=item['code_bytes']*8 or item['payload_bytes']>8*1024*1024
            or item['cycle_limit']!=1000000):
        raise ValueError('Invalid gas-plan resource/preparation identity')


def validate_memo_preparation(item):
    """Validate bounded lazy initialization and complete final occupancy; zero CPU initialization may be below clock resolution."""
    keys={'cpu_ns','wall_ns','code_bytes','payload_bytes','cycle_limit','priced_blocks'}
    if (not isinstance(item,dict) or set(item)!=keys or any(type(v) is not int for v in item.values())
            or item['cpu_ns']<0 or item['wall_ns']<=0 or max(item['cpu_ns'],item['wall_ns'])>=(1<<63)
            or not 0<item['priced_blocks']<=item['code_bytes']
            or item['payload_bytes']!=item['code_bytes']*8 or not 0<item['payload_bytes']<=8*1024*1024
            or item['cycle_limit']!=1000000):
        raise ValueError('Invalid gas-memo resource/occupancy identity')


def parse_process_output(output,engine,limit,guest='sieve',samples=SAMPLES):
    """Require complete policy-specific initialization/occupancy framing in addition to every measured execution."""
    limits=limits_for_guest(guest)
    if limit not in limits:raise ValueError('Unknown guest workload size')
    preparation=None;lines=output.splitlines()
    if guest!='sieve':
        # A mandatory first witness prevents cross-family reuse or relabeling of valid samples.
        if not lines or lines.pop(0)!='GUEST,'+guest:raise ValueError('Missing or foreign guest family')
    if engine=='ragnarok_planned':
        fields=lines.pop(0).split(',') if lines else []
        if len(fields)!=7 or fields[0]!='GAS_PLAN' or any(re.fullmatch(r'[1-9][0-9]{0,18}',v) is None for v in fields[1:]):
            raise ValueError('Missing or malformed gas-plan preparation')
        cpu,wall,code,blocks,payload,cycles=map(int,fields[1:])
        preparation=dict(cpu_ns=cpu,wall_ns=wall,code_bytes=code,block_count=blocks,
                         payload_bytes=payload,cycle_limit=cycles)
        validate_preparation(preparation)
    elif engine=='ragnarok_memo':
        # A final occupancy record proves the reusable memo survived the complete cold/warm process.
        fields=lines.pop(0).split(',') if lines else []
        tail=lines.pop().split(',') if lines else []
        if (len(fields)!=6 or fields[0]!='GAS_MEMO'
                or any(re.fullmatch(r'(0|[1-9][0-9]{0,18})',v) is None for v in fields[1:])
                or len(tail)!=2 or tail[0]!='GAS_MEMO_END' or re.fullmatch(r'[1-9][0-9]{0,18}',tail[1]) is None):
            raise ValueError('Missing or malformed gas-memo initialization/occupancy')
        cpu,wall,code,payload,cycles=map(int,fields[1:])
        preparation=dict(cpu_ns=cpu,wall_ns=wall,code_bytes=code,payload_bytes=payload,
                         cycle_limit=cycles,priced_blocks=int(tail[1]))
        validate_memo_preparation(preparation)
    return dict(guest=guest,samples=parse_output('\n'.join(lines),engine,limit,samples),preparation=preparation)


def validate_samples(rows):
    """Cold-cost claims must validate sample zero as strictly as the warmed execution distribution."""
    if (len(rows)!=SAMPLES or any(set(row)!={'sample','wall_ns','cpu_ns'} for row in rows)
            or any(type(row[key]) is not int for row in rows for key in row)
            or [row['sample'] for row in rows]!=list(range(SAMPLES))
            or any(not 0<row[key]<(1<<63) for row in rows for key in ('wall_ns','cpu_ns'))):
        raise ValueError('Invalid complete sieve observations')


def summarize(report):
    """Show warmed runtime plus initialization/first-cold costs without hiding lazy work in discarded warmups."""
    guest=report.get('guest','sieve')
    limits=limits_for_guest(guest)
    title={'sieve':'Sieve','minimal':'Indirect calls','memset':'Memory fill','pinky':'Pinky (one initialized NES frame)'}[guest]
    if report['status']!='checks-passed':
        return title+' comparison: '+report['status']+'. '+report.get('error','')+'\n'
    if any(p.get('guest','sieve')!=guest for p in report['passes']):
        raise ValueError('Missing or foreign structured guest family')
    identities=[(p['limit'],p['engine'],p['pass_index']) for p in report['passes']]
    if (any(type(p['limit']) is not int or type(p['pass_index']) is not int for p in report['passes'])
            or len(identities)!=len(set(identities)) or set(identities)!={(limit,engine,p) for limit in limits for engine in ENGINES for p in range(2)}):
        raise ValueError('Missing or duplicate sieve report pass')
    lines=[title+' interpreter comparison (process CPU medians; all samples retained).','',
           '| Limit | Dynamic ms | Immutable plan ms | Lazy memo ms | PolkaVM ms | Dynamic/ref | Plan/ref | Memo/ref | Quality |',
           '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |']
    if any(p.get('preparation') is not None for p in report['passes'] if p['engine'] not in ('ragnarok_planned','ragnarok_memo')):
        raise ValueError('Unplanned engine supplied pricing metadata')
    resources=set();plan_counts=set();amortization=[];cold=[];dispersion=[]
    for limit in limits:
        medians={};noisy=False
        for engine in ENGINES:
            observed=[p for p in report['passes'] if p['limit']==limit and p['engine']==engine]
            for item in observed:validate_samples(item['samples'])
            groups=[[s['cpu_ns'] for s in p['samples'][3:]] for p in observed]
            values=sorted(sum(groups,[]));centers=[statistics.median(g) for g in groups]
            medians[engine]=statistics.median(values)
            # Retain a human-readable distribution beside median ratios, including wall-clock scheduling effects.
            walls=[s['wall_ns'] for p in observed for s in p['samples'][3:]]
            dispersion.append(f"| {limit} | {engine} | {statistics.mean(values)/1e6:.3f} ± {statistics.stdev(values)/1e6:.3f} | "
                f"{values[0]/1e6:.3f}–{values[-1]/1e6:.3f} | {statistics.median(walls)/1e6:.3f} |")
            noisy|=max(centers)>1.25*min(centers) or values[17]>2*values[2]
            if engine in ('ragnarok','polkavm_interpreter'):
                first=statistics.median(p['samples'][0]['cpu_ns'] for p in observed)
                cold.append(f'| {limit} | '+('Dynamic' if engine=='ragnarok' else 'PolkaVM interpreted')+
                    f' | — | {first/1e6:.3f} | {first/1e6:.3f} | — | — |')
            if engine in ('ragnarok_planned','ragnarok_memo'):
                # Occupancy depends on this input; immutable complete plans have one source-wide block count.
                preparations=[p.get('preparation') for p in observed]
                for item in preparations:
                    (validate_preparation if engine=='ragnarok_planned' else validate_memo_preparation)(item)
                    resources.add(tuple(item[k] for k in ('code_bytes','payload_bytes','cycle_limit')))
                count_key='block_count' if engine=='ragnarok_planned' else 'priced_blocks'
                counts={item[count_key] for item in preparations}
                if len(counts)!=1:raise ValueError('Inconsistent per-input pricing occupancy')
                if engine=='ragnarok_planned':plan_counts.update(counts)
                init=statistics.median(p['cpu_ns'] for p in preparations)
                first=statistics.median(p['samples'][0]['cpu_ns'] for p in observed)
                cold.append(f"| {limit} | "+('Immutable plan' if engine=='ragnarok_planned' else 'Lazy memo')+
                    f" | {init/1e6:.3f} | {first/1e6:.3f} | {(init+first)/1e6:.3f} | {preparations[0]['payload_bytes']/(1024*1024):.2f} | {next(iter(counts))} |")
                if engine=='ragnarok_planned' and medians['ragnarok']>medians[engine]:
                    amortization.append(f"{limit}: about {init/(medians['ragnarok']-medians[engine]):.2f} executions")
        dynamic,planned,memo,reference=(medians[e] for e in ENGINES)
        lines.append(f'| {limit} | {dynamic/1e6:.3f} | {planned/1e6:.3f} | {memo/1e6:.3f} | {reference/1e6:.3f} | {dynamic/reference:.2f}x | {planned/reference:.2f}x | {memo/reference:.2f}x | '+
                     ('noisy; inspect raw samples' if noisy else 'within dispersion guard')+' |')
    if len(resources)!=1 or len(plan_counts)!=1:raise ValueError('Inconsistent source/policy resource identity')
    lines+=['','Execution distributions (twenty measured observations; sample standard deviation).','',
            '| Limit | Engine | CPU mean ± SD ms | CPU min–max ms | Wall median ms |',
            '| --- | --- | ---: | ---: | ---: |',*dispersion,'',
            'Pricing initialization and first execution (two observations per cell; common program/module loading excluded).','',
            '| Limit | Policy | Init CPU ms | First exec CPU ms | Init + first ms | Payload MiB | Priced blocks |',
            '| --- | --- | ---: | ---: | ---: | ---: | ---: |',*cold]
    if amortization:lines+=['','Additional immutable-plan preparation amortization from current medians: '+ '; '.join(amortization)+'.']
    lines+=['','Warmed execution has twenty measured observations; every cold/warmup sample remains in the raw data.',
            'Lazy memo pricing work occurs in the first execution: include initialization plus that cold sample when assessing reuse.',
            'Initialization CPU below clock resolution may be zero; positive wall duration remains recorded.',
            'Common source capture/reset and full result validation are outside execution timing.',
            'Checked release ARC/Clang ThinLTO; PolkaVM Interpreter JamV1 Sync/Full/L2Hit.',
            'These workloads do not establish general interpreter or full JAM performance.']
    return '\n'.join(lines)+'\n'
