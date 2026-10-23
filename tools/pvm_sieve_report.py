# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete sieve observations and retain CPU/wall distributions without filtering noise."""
import statistics
import re

ENGINES=('ragnarok','ragnarok_planned','polkavm_interpreter')
LIMITS=(1000,100000)
SAMPLES=13


def parse_output(output,engine,limit):
    """Accept one ordered, complete pass; reject extra output, duplicate and nonpositive samples."""
    if engine not in ENGINES or limit not in LIMITS:
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
    if len(rows)!=SAMPLES:
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


def parse_process_output(output,engine,limit):
    """Require an explicit bounded preparation record only for planned native execution."""
    preparation=None
    lines=output.splitlines()
    if engine=='ragnarok_planned':
        fields=lines.pop(0).split(',') if lines else []
        if len(fields)!=7 or fields[0]!='GAS_PLAN' or any(re.fullmatch(r'[1-9][0-9]{0,18}',v) is None for v in fields[1:]):
            raise ValueError('Missing or malformed gas-plan preparation')
        cpu,wall,code,blocks,payload,cycles=map(int,fields[1:])
        preparation=dict(cpu_ns=cpu,wall_ns=wall,code_bytes=code,block_count=blocks,
                         payload_bytes=payload,cycle_limit=cycles)
        validate_preparation(preparation)
    return dict(samples=parse_output('\n'.join(lines),engine,limit),preparation=preparation)


def summarize(report):
    """Render complete observations, separate plan preparation and retain every noisy sample."""
    if report['status']!='checks-passed':
        return 'Sieve comparison: '+report['status']+'. '+report.get('error','')+'\n'
    identities=[(item['limit'],item['engine'],item['pass_index']) for item in report['passes']]
    if len(identities)!=len(set(identities)) or set(identities)!={(limit,engine,p) for limit in LIMITS for engine in ENGINES for p in range(2)}:
        raise ValueError('Missing or duplicate sieve report pass')
    lines=['Sieve interpreter comparison (process CPU medians; all samples retained).','',
           '| Limit | Dynamic ms | Planned ms | PolkaVM ms | Dynamic/ref | Planned/ref | Plan prep ms | Payload MiB | Quality |',
           '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |']
    if any(p.get('preparation') is not None for p in report['passes'] if p['engine']!='ragnarok_planned'):
        raise ValueError('Unplanned engine supplied plan metadata')
    resources=set()
    amortization=[]
    for limit in LIMITS:
        medians={};noisy=False
        for engine in ENGINES:
            # Every measured process has three warmups followed by ten validated observations.
            passes=[[row['cpu_ns'] for row in item['samples'][3:]] for item in report['passes']
                    if item['limit']==limit and item['engine']==engine]
            if len(passes)!=2 or any(len(values)!=10 for values in passes):
                raise ValueError('Incomplete sieve report')
            values=sorted(sum(passes,[]));centers=[statistics.median(p) for p in passes]
            medians[engine]=statistics.median(values)
            noisy|=max(centers)>1.25*min(centers) or values[17]>2*values[2]
        planned=[p.get('preparation') for p in report['passes'] if p['limit']==limit and p['engine']=='ragnarok_planned']
        if len(planned)!=2 or any(not isinstance(p,dict) for p in planned):
            raise ValueError('Incomplete gas-plan preparation evidence')
        for p in planned:
            validate_preparation(p)
            # The same immutable linked program has identical resource usage for both input limits and process orders.
            resources.add(tuple(p[key] for key in ('code_bytes','block_count','payload_bytes','cycle_limit')))
        if len(resources)!=1:raise ValueError('Inconsistent gas-plan resource identity')
        dynamic,prepared,reference=(medians[e] for e in ENGINES)
        prep=statistics.median(p['cpu_ns'] for p in planned)
        payload=planned[0]['payload_bytes']
        lines.append(f'| {limit} | {dynamic/1e6:.3f} | {prepared/1e6:.3f} | {reference/1e6:.3f} | {dynamic/reference:.2f}x | {prepared/reference:.2f}x | {prep/1e6:.3f} | {payload/(1024*1024):.2f} | '+
                     ('noisy; inspect raw samples' if noisy else 'within dispersion guard')+' |')
        saving=dynamic-prepared
        if saving>0:
            amortization.append(f'{limit}: about {prep/saving:.2f} executions')
    if amortization:lines+=['','Additional plan preparation amortization from current medians: '+ '; '.join(amortization)+'.']
    lines.extend(['','Execution only; complete state validation occurs outside timing.',
                  'Planned mode additionally prepares an immutable price table once; its CPU cost and payload are shown separately.',
                  'A single cold execution also pays preparation; reuse is needed to amortize that cost.',
                  'Checked release ARC/Clang ThinLTO; PolkaVM Interpreter JamV1 Sync/Full/L2Hit.',
                  'These two guests do not establish general interpreter or full JAM performance.'])
    return '\n'.join(lines)+'\n'
