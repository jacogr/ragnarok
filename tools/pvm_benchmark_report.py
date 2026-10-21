# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate raw benchmark observations and render one complete three-engine comparison table."""
import statistics

ENGINES=('ragnarok','polkavm_interpreter','polkavm_compiler')
NAMES=('arithmetic-10000','memory-aligned-1000','memory-crossing-1000',
       'hosts-aligned-1000','hosts-crossing-1000')


# A successful process with missing/duplicate samples is not a successful benchmark.
def parse_output(output, engine, *, require_compiled=False):
    if engine not in ENGINES:raise ValueError('Unknown benchmark engine')
    rows={i:dict(samples=[],reason=None) for i in range(len(NAMES))}
    for line in output.splitlines():
        fields=line.split('\t')
        if fields[0]=='sample' and len(fields)==5:
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
            if require_compiled:raise ValueError('Required compiled backend unavailable: '+row['reason'])
        elif sorted(item['sample'] for item in row['samples'])!=list(range(13)):
            raise ValueError('Missing or duplicate benchmark samples')
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
        raise ValueError('Benchmark needs two complete three-engine passes')
    cases=[]
    for index,name in enumerate(NAMES):
        engines={}
        for engine in ENGINES:
            observations=[item[engine][index] for item in passes]
            unavailable=[item['reason'] is not None for item in observations]
            if any(unavailable):
                if not all(unavailable) or engine!='polkavm_compiler':
                    raise ValueError('Inconsistent backend availability between passes')
                engines[engine]=dict(status='unavailable',reason='; '.join(sorted({item['reason'] for item in observations})))
            else:
                raw=[dict(item,pass_index=p) for p,row in enumerate(observations) for item in row['samples']]
                samples=[item['execution_ns'] for item in raw if item['sample']>=3]
                if len(samples)!=20:raise ValueError('Expected twenty validated measured samples')
                engines[engine]=dict(status='measured',samples=raw,median_ns=statistics.median(samples),
                    min_ns=min(samples),max_ns=max(samples),stdev_ns=statistics.pstdev(samples),
                    quality=quality(raw))
        cases.append(dict(name=name,engines=engines))
    return cases


# Only execution medians are compared; preparation/compilation observations remain in raw artifacts.
def summarize_benchmark(report):
    if report['status'] not in ('running','failed','checks-passed'):raise ValueError('Unknown benchmark status')
    lines=['## PVM speed comparison','','**Status: '+report['status']+'**','',
        'Execution µs per fixed guest: median [min–max], 20 validated samples in two opposite-order passes.',
        'Three warmups per pass; setup/compilation, input reset and result validation are excluded.','',
        '| Workload | Ragnarök PVM | PolkaVM interpreted | PolkaVM compiled | Ragnarök / interpreted |',
        '| --- | ---: | ---: | ---: | ---: |']
    cases=report.get('cases',[])
    if report['status']=='checks-passed' and [item['name'] for item in cases]!=list(NAMES):
        raise ValueError('Incomplete benchmark marked successful')
    noisy_rows=[]
    for case in cases:
        cells=[]
        noisy=False
        for engine in ENGINES:
            item=case['engines'][engine]
            if item['status']=='unavailable':
                if engine!='polkavm_compiler' or not item.get('reason'):raise ValueError('Required baseline unavailable')
                if report.get('required_compiled') and report['status']=='checks-passed':
                    raise ValueError('Required compiled backend unavailable')
                cells.append('Unavailable')
            else:
                if ({(s['pass_index'],s['sample']) for s in item['samples']}
                        !={(p,i) for p in range(2) for i in range(13)} or len(item['samples'])!=26):
                    raise ValueError('Incomplete benchmark sample identities')
                samples=[s['execution_ns'] for s in item['samples'] if s['sample']>=3]
                if (len(samples)!=20 or any(type(s) is not int or s<=0 for s in samples)
                        or statistics.median(samples)!=item['median_ns']
                        or min(samples)!=item['min_ns'] or max(samples)!=item['max_ns']):
                    raise ValueError('Unverified benchmark statistics')
                noisy=noisy or quality(item['samples'])['noisy']
                cells.append(f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]')
        ratio=case['engines']['ragnarok']['median_ns']/case['engines']['polkavm_interpreter']['median_ns']
        if noisy:noisy_rows.append(case['name'])
        lines.append('| '+case['name']+(' †' if noisy else '')+' | '+' | '.join(cells)+f' | {ratio:.1f}× |')
    if noisy_rows:
        lines+=['','† Noisy: per-pass medians differ by more than 25% or central sample spread exceeds 2×. Ratios are provisional; no samples were discarded.']
    reasons={item['engines']['polkavm_compiler'].get('reason') for item in cases
             if item['engines']['polkavm_compiler']['status']=='unavailable'}
    for reason in sorted(reasons):
        # Kernel/backend errors are diagnostics, not instructions or Markdown table content.
        safe=' '.join(reason.split())[:500].replace('<','&lt;').replace('>','&gt;')
        lines+=['','Compiled unavailable: '+safe]
    if report.get('error'):lines+=['','Failure: '+str(report['error']).replace('\n',' ')[:500]]
    lines+=['','These are observations on one recorded host, without affinity/frequency isolation. '
            'Small differences within the sample spread are not established performance changes.',
            'Native uses checked release ARC/Clang LTO; PolkaVM uses the pinned upstream Rust release/LTO profile, JamV1 and Sync/Full/L2Hit.',
            'Download `results.json`, `samples.csv`, `summary.md` and logs for raw samples, preparation times and source/toolchain/hardware metadata.']
    return '\n'.join(lines)+'\n'
