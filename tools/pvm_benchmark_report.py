# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate raw baseline observations and keep deferred compiled comparisons explicit."""
import statistics
import re

ENGINES=('ragnarok','ragnarok_planned','ragnarok_memo','polkavm_interpreter','polkavm_compiler')
ACTIVE_ENGINES=ENGINES[:4]
DEFERRED_COMPILER='Deferred by maintainer until the interpreter baseline is competitive'
NAMES=('arithmetic-10000','memory-aligned-1000','memory-crossing-1000',
       'hosts-aligned-1000','hosts-crossing-1000','arithmetic-1','arithmetic-16',
       'bits-mixed-1000','sparse-aligned-1000','sparse-crossing-1000','blocks-alternating-1000')


def native_pricing_mode(engine):
    """Select an explicit known native policy; reference backends ignore this environment field."""
    modes={'ragnarok':'dynamic','ragnarok_planned':'planned','ragnarok_memo':'memo',
           'polkavm_interpreter':'dynamic','polkavm_compiler':'dynamic'}
    if engine not in modes:raise ValueError('Unknown benchmark engine')
    return modes[engine]


def validate_memo(item):
    """Require bounded initialization and final occupancy for a complete lazy-price process."""
    keys={'prepare_once_ns','code_bytes','payload_bytes','cycle_limit','priced_blocks'}
    if (not isinstance(item,dict) or set(item)!=keys or any(type(v) is not int or v<=0 for v in item.values())
            or item['prepare_once_ns']>=(1<<63) or not 0<item['priced_blocks']<=item['code_bytes']
            or item['payload_bytes']!=item['code_bytes']*8 or item['payload_bytes']>8*1024*1024
            or item['cycle_limit']>=(1<<64)):
        raise ValueError('Invalid gas-memo benchmark metadata')


def validate_plan(item):
    """Check a complete bounded native price-plan witness independently of rendered tables."""
    keys={'prepare_once_ns','code_bytes','block_count','payload_bytes','cycle_limit'}
    if (not isinstance(item,dict) or set(item)!=keys or any(type(v) is not int or v<=0 for v in item.values())
            or item['prepare_once_ns']>=(1<<63) or item['block_count']>min(item['code_bytes'],100000)
            or item['payload_bytes']!=item['code_bytes']*8 or item['payload_bytes']>8*1024*1024
            or item['cycle_limit']>=(1<<64)):
        raise ValueError('Invalid gas-plan benchmark metadata')


# A successful process with missing/duplicate samples is not a successful benchmark.
def parse_output(output, engine):
    if engine not in ENGINES:raise ValueError('Unknown benchmark engine')
    rows={i:dict(samples=[],reason=None,plan=None,memo=None) for i in range(len(NAMES))}
    for line in output.splitlines():
        fields=line.split('\t')
        if fields[0]=='gas-plan' and len(fields)==7 and engine=='ragnarok_planned':
            row,prepare,code,blocks,payload,cycles=map(int,fields[1:])
            if (row not in rows or rows[row]['plan'] is not None or rows[row]['samples'] or
                    not 0<prepare<(1<<63) or not 0<blocks<=min(code,100000) or
                    payload!=code*8 or not 0<payload<=8*1024*1024 or not 0<cycles<(1<<64)):
                raise ValueError('Invalid gas-plan benchmark metadata')
            rows[row]['plan']=dict(prepare_once_ns=prepare,code_bytes=code,block_count=blocks,
                                   payload_bytes=payload,cycle_limit=cycles)
            validate_plan(rows[row]['plan'])
        elif fields[0]=='gas-memo' and len(fields)==6 and engine=='ragnarok_memo':
            # Initialization precedes all samples; the final occupancy witness must close this exact case.
            if (re.fullmatch(r'(0|[1-9][0-9]{0,18})',fields[1]) is None
                    or any(re.fullmatch(r'[1-9][0-9]{0,18}',v) is None for v in fields[2:])):
                raise ValueError('Invalid gas-memo integer')
            row,prepare,code,payload,cycles=map(int,fields[1:])
            if (row not in rows or rows[row]['memo'] is not None or rows[row]['samples']
                    or prepare>=(1<<63) or payload!=code*8 or payload>8*1024*1024 or cycles>=(1<<64)):
                raise ValueError('Invalid gas-memo benchmark metadata')
            rows[row]['memo']=dict(prepare_once_ns=prepare,code_bytes=code,payload_bytes=payload,
                                    cycle_limit=cycles,priced_blocks=None)
        elif fields[0]=='gas-memo-end' and len(fields)==3 and engine=='ragnarok_memo':
            # A suffix cannot close missing, truncated or already-closed warm/cold observations.
            if any(re.fullmatch(r'(0|[1-9][0-9]{0,18})',v) is None for v in fields[1:]):
                raise ValueError('Invalid gas-memo occupancy integer')
            row,blocks=map(int,fields[1:])
            if (row not in rows or rows[row]['memo'] is None or rows[row]['memo']['priced_blocks'] is not None
                    or len(rows[row]['samples'])!=13):
                raise ValueError('Missing or duplicate gas-memo occupancy')
            rows[row]['memo']['priced_blocks']=blocks
            validate_memo(rows[row]['memo'])
        elif fields[0]=='sample' and len(fields)==5:
            row,sample,elapsed,prepare=map(int,fields[1:])
            if row not in rows or not 0<=sample<13 or not 0<elapsed<(1<<63) or prepare<0:
                raise ValueError('Invalid benchmark sample')
            rows[row]['samples'].append(dict(sample=sample,execution_ns=elapsed,prepare_once_ns=prepare))
        elif fields[0]=='unavailable' and len(fields)==3 and engine=='polkavm_compiler':
            row=int(fields[1])
            if row not in rows or rows[row]['reason'] is not None or not fields[2]:
                raise ValueError('Invalid unavailable backend record')
            rows[row]['reason']=fields[2]
        else:
            raise ValueError('Unexpected benchmark output: '+line[:100])
    for row in rows.values():
        # Warmups must also complete validation; unavailable backends must not carry fallback timings.
        if row['reason'] is not None:
            if row['samples']:raise ValueError('Unavailable backend supplied timings')
        elif sorted(item['sample'] for item in row['samples'])!=list(range(13)):
            raise ValueError('Missing or duplicate benchmark samples')
        if row['samples'] and len({s['prepare_once_ns'] for s in row['samples']})!=1:
            raise ValueError('Inconsistent one-time preparation observations')
        if engine=='ragnarok_planned':
            if row['plan'] is None or row['reason'] is not None:
                raise ValueError('Missing gas-plan benchmark metadata')
            if any(s['prepare_once_ns']!=row['plan']['prepare_once_ns'] for s in row['samples']):
                raise ValueError('Gas-plan preparation mismatch')
        if engine=='ragnarok_memo':
            if row['memo'] is None or row['reason'] is not None:
                raise ValueError('Missing gas-memo benchmark metadata')
            validate_memo(row['memo'])
            if any(v['prepare_once_ns']!=row['memo']['prepare_once_ns'] for v in row['samples']):
                raise ValueError('Gas-memo preparation mismatch')
    return [rows[i] for i in range(len(NAMES))]


# Flag substantial pass disagreement or broad central spread; keep every sample, including outliers.
def quality(raw):
    values=sorted(item['execution_ns'] for item in raw if item['sample']>=3)
    medians=[statistics.median(item['execution_ns'] for item in raw
        if item['sample']>=3 and item['pass_index']==p) for p in range(2)]
    pass_ratio=max(medians)/min(medians)
    central_ratio=values[18]/values[1]
    return dict(per_pass_medians_ns=medians,pass_median_ratio=pass_ratio,
                central_spread_ratio=central_ratio,noisy=pass_ratio>1.25 or central_ratio>2)


# Merge two opposite-order passes, retaining warmups separately from execution statistics.
def aggregate(passes):
    if len(passes)!=2 or any(set(item)!=set(ENGINES) for item in passes):
        raise ValueError('Benchmark needs two complete interpreter/deferred passes')
    cases=[]
    for index,name in enumerate(NAMES):
        engines={}
        for engine in ENGINES:
            observations=[item[engine][index] for item in passes]
            unavailable=[item['reason'] is not None for item in observations]
            if any(unavailable):
                if not all(unavailable) or engine!='polkavm_compiler':
                    raise ValueError('Inconsistent backend availability between passes')
                deferred=[item.get('deferred',False) for item in observations]
                if any(deferred) and not all(deferred):raise ValueError('Inconsistent compiler deferral between passes')
                if any(item['samples'] for item in observations):raise ValueError('Unmeasured backend supplied timings')
                engines[engine]=dict(status='deferred' if all(deferred) else 'unavailable',
                    reason='; '.join(sorted({item['reason'] for item in observations})))
            else:
                raw=[dict(item,pass_index=p) for p,row in enumerate(observations) for item in row['samples']]
                samples=[item['execution_ns'] for item in raw if item['sample']>=3]
                if len(samples)!=20:raise ValueError('Expected twenty validated measured samples')
                engines[engine]=dict(status='measured',samples=raw,median_ns=statistics.median(samples),
                    min_ns=min(samples),max_ns=max(samples),stdev_ns=statistics.pstdev(samples),
                    quality=quality(raw))
                engines[engine]['preparation_median_ns']=statistics.median(row['samples'][0]['prepare_once_ns'] for row in observations)
                if engine=='ragnarok_planned':
                    plans=[row['plan'] for row in observations]
                    if any({k:v for k,v in p.items() if k!='prepare_once_ns'}!={k:v for k,v in plans[0].items() if k!='prepare_once_ns'} for p in plans):
                        raise ValueError('Inconsistent gas-plan resource observations')
                    engines[engine]['plans']=plans
                if engine=='ragnarok_memo':
                    memos=[row['memo'] for row in observations]
                    for item in memos:validate_memo(item)
                    if any({k:v for k,v in m.items() if k!='prepare_once_ns'}!={k:v for k,v in memos[0].items() if k!='prepare_once_ns'} for m in memos):
                        raise ValueError('Inconsistent gas-memo resource observations')
                    engines[engine]['memos']=memos
        cases.append(dict(name=name,engines=engines))
    return cases


# Only execution medians are compared; preparation/compilation observations remain in raw artifacts.
def summarize_benchmark(report):
    if report['status'] not in ('running','failed','checks-passed'):raise ValueError('Unknown benchmark status')
    lines=['## PVM speed comparison','','**Status: '+report['status']+'**','',
        'Execution µs per fixed guest: median [min–max], 20 validated samples in two opposite-order passes.',
        'Three warmups per pass; setup/compilation, input reset and result validation are excluded.','',
        '| Workload | Ragnarök PVM | Immutable plan | Lazy memo | PolkaVM interpreted | PolkaVM compiled | Dynamic / interpreted | Plan / interpreted | Memo / interpreted |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    cases=report.get('cases',[])
    if report['status']=='checks-passed' and [item['name'] for item in cases]!=list(NAMES):
        raise ValueError('Incomplete benchmark marked successful')
    noisy_rows=[]
    for case in cases:
        cells=[]
        noisy=False
        for engine in ENGINES:
            item=case['engines'][engine]
            if item['status'] in ('unavailable','deferred'):
                if engine!='polkavm_compiler' or not item.get('reason'):raise ValueError('Required baseline unavailable')
                if item.get('samples'):raise ValueError('Unmeasured backend supplied timings')
                cells.append('Deferred' if item['status']=='deferred' else 'Unavailable')
            else:
                if ({(s['pass_index'],s['sample']) for s in item['samples']}
                        !={(p,i) for p in range(2) for i in range(13)} or len(item['samples'])!=26):
                    raise ValueError('Incomplete benchmark sample identities')
                if any(type(s['execution_ns']) is not int or not 0<s['execution_ns']<(1<<63) for s in item['samples']):
                    raise ValueError('Invalid cold/warm execution durations')
                samples=[s['execution_ns'] for s in item['samples'] if s['sample']>=3]
                if (len(samples)!=20 or any(type(s) is not int or s<=0 for s in samples)
                        or statistics.median(samples)!=item['median_ns']
                        or min(samples)!=item['min_ns'] or max(samples)!=item['max_ns']):
                    raise ValueError('Unverified benchmark statistics')
                prepared=[]
                for p in range(2):
                    values={s['prepare_once_ns'] for s in item['samples'] if s['pass_index']==p}
                    if len(values)!=1 or any(type(v) is not int or not 0<=v<(1<<63) for v in values):
                        raise ValueError('Unverified preparation observations')
                    prepared.append(next(iter(values)))
                if statistics.median(prepared)!=item['preparation_median_ns']:
                    raise ValueError('Unverified preparation median')
                if engine=='ragnarok_planned':
                    plans=item.get('plans',[])
                    if len(plans)!=2:raise ValueError('Missing gas-plan preparation observations')
                    for p,plan in enumerate(plans):
                        validate_plan(plan)
                        if plan['prepare_once_ns']!=prepared[p]:raise ValueError('Gas-plan preparation mismatch')
                    if any({k:v for k,v in plan.items() if k!='prepare_once_ns'}!={k:v for k,v in plans[0].items() if k!='prepare_once_ns'} for plan in plans):
                        raise ValueError('Inconsistent gas-plan resource observations')
                if engine=='ragnarok_memo':
                    memos=item.get('memos',[])
                    if len(memos)!=2:raise ValueError('Missing gas-memo observations')
                    for p,memo in enumerate(memos):
                        validate_memo(memo)
                        if memo['prepare_once_ns']!=prepared[p]:raise ValueError('Gas-memo preparation mismatch')
                    if any({k:v for k,v in m.items() if k!='prepare_once_ns'}!={k:v for k,v in memos[0].items() if k!='prepare_once_ns'} for m in memos):
                        raise ValueError('Inconsistent gas-memo resource observations')
                noisy=noisy or quality(item['samples'])['noisy']
                cells.append(f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]')
        ratio=case['engines']['ragnarok']['median_ns']/case['engines']['polkavm_interpreter']['median_ns']
        planned_ratio=case['engines']['ragnarok_planned']['median_ns']/case['engines']['polkavm_interpreter']['median_ns']
        memo_ratio=case['engines']['ragnarok_memo']['median_ns']/case['engines']['polkavm_interpreter']['median_ns']
        if noisy:noisy_rows.append(case['name'])
        lines.append('| '+case['name']+(' †' if noisy else '')+' | '+' | '.join(cells)+f' | {ratio:.1f}× | {planned_ratio:.1f}× | {memo_ratio:.1f}× |')
    if cases:
        lines+=['','Native preparation/cold observations (two one-time wall observations; includes selected policy construction).','',
                '| Workload | Dynamic prep µs | Plan prep µs | Memo prep µs | Memo first exec µs | Memo payload bytes | Priced blocks |',
                '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
        for case in cases:
            dynamic=case['engines']['ragnarok'];planned=case['engines']['ragnarok_planned']
            memo=case['engines']['ragnarok_memo']
            first=statistics.median(s['execution_ns'] for s in memo['samples'] if s['sample']==0)
            lines.append(f"| {case['name']} | {dynamic['preparation_median_ns']/1000:.2f} | {planned['preparation_median_ns']/1000:.2f} | {memo['preparation_median_ns']/1000:.2f} | {first/1000:.2f} | {memo['memos'][0]['payload_bytes']} | {memo['memos'][0]['priced_blocks']} |")
        lines+=['','Immutable plans pay complete pricing before execution. Lazy memos learn during the first execution; include preparation and that cold sample when assessing reuse. Every warmup remains in raw data.']
    if noisy_rows:
        lines+=['','† Noisy: per-pass medians differ by more than 25% or central sample spread exceeds 2×. Ratios are provisional; no samples were discarded.']
    reasons={item['engines']['polkavm_compiler'].get('reason') for item in cases
             if item['engines']['polkavm_compiler']['status'] in ('unavailable','deferred')}
    for reason in sorted(reasons):
        # Kernel/backend errors are diagnostics, not instructions or Markdown table content.
        safe=' '.join(reason.split())[:500].replace('<','&lt;').replace('>','&gt;')
        lines+=['','Compiled comparison: '+safe]
    if report.get('error'):lines+=['','Failure: '+str(report['error']).replace('\n',' ')[:500]]
    lines+=['','These are observations on one recorded host, without affinity/frequency isolation. '
            'Small differences within the sample spread are not established performance changes.',
            'Native uses checked release ARC/Clang LTO; PolkaVM uses the pinned upstream Rust release/LTO profile, JamV1 and Sync/Full/L2Hit.',
            'Download `results.json`, `samples.csv`, `summary.md` and logs for raw samples, preparation times and source/toolchain/hardware metadata.']
    return '\n'.join(lines)+'\n'
