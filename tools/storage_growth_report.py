# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate sustained storage observations independently of native success and render matched work."""
import json
import math
import re
import statistics

ENGINES=('memory','journal','managed')
COUNTS=(1024,8192)
PUBLICATIONS=(64,256)
CASES=tuple((count,steps) for count in COUNTS for steps in PUBLICATIONS)
PHASES=('publication','reopen','retention','maintenance')
METRICS=('stored_nodes','retained_nodes','current_nodes','snapshot_bytes','journal_bytes',
         'compacted_snapshot_bytes','compacted_journal_bytes')
LABELS=('Sustained publication','Strict disk reopen','Nine-root reclamation','Current-root reclamation')


def unavailable(engine,phase):
    """Unavailable public operations retain one exact sentinel and never acquire fabricated ratios."""
    return (engine=='memory' and phase=='reopen') or (engine=='journal' and phase in ('retention','maintenance'))


def parse_growth(output,engine,count,steps):
    """Require exact identities, complete ordered samples and bounded typed timings/physical metrics."""
    if engine not in ENGINES or type(count) is not int or count not in COUNTS or type(steps) is not int or steps not in PUBLICATIONS:
        raise ValueError('Unknown sustained storage configuration')
    rows=[]
    for line in output.splitlines():
        fields=line.split('\t')
        if len(fields)!=4+len(PHASES)+len(METRICS) or fields[0]!='growth' or any(
                re.fullmatch(r'-1|0|[1-9][0-9]{0,18}',value) is None for value in fields[1:]):
            raise ValueError('Invalid sustained storage output')
        size,publications,sample,*values=map(int,fields[1:])
        if size!=count or publications!=steps or sample!=len(rows) or sample>=13:
            raise ValueError('Invalid sustained sample identity')
        row=dict(items=size,publications=publications,sample=sample,**dict(zip((*PHASES,*METRICS),values)))
        for phase in PHASES:
            value=row[phase]
            if (unavailable(engine,phase) and value!=-1) or (not unavailable(engine,phase) and not 0<value<(1<<63)):
                raise ValueError('Invalid sustained operation timing')
        if not 0<row['stored_nodes']<(1<<63):
            raise ValueError('Invalid sustained record count')
        if engine=='journal':
            if row['retained_nodes']!=-1 or row['current_nodes']!=-1:
                raise ValueError('Journal has no reclamation record count')
        elif not 0<row['current_nodes']<row['retained_nodes']<=row['stored_nodes']:
            raise ValueError('Invalid sustained reclamation counts')
        for metric in METRICS[3:]:
            value=row[metric]
            missing=engine=='memory' or (engine=='journal' and metric.startswith('compacted_'))
            zero=engine=='journal' and metric=='snapshot_bytes'
            if (missing and value!=-1) or (zero and value!=0) or (not missing and not zero and not 0<value<(1<<63)):
                raise ValueError('Invalid sustained selected-file extent')
        rows.append(row)
    if len(rows)!=13:
        raise ValueError('Incomplete sustained sample coverage')
    return rows


def aggregate_growth(passes):
    """Revalidate all raw values before deriving matched operation distributions and paired ratios."""
    orders=(ENGINES,tuple(reversed(ENGINES)))
    if type(passes) is not list or len(passes)!=2:
        raise ValueError('Two sustained passes required')
    for order,observations in zip(orders,passes):
        expected=[f'{e}-{n}-{s}' for e in order for n,s in CASES]
        if type(observations) is not dict or list(observations)!=expected:
            raise ValueError('Incomplete sustained backend order')
    cases=[]
    for count,steps in CASES:
        observations={}
        for engine in ENGINES:
            groups=[p[f'{engine}-{count}-{steps}'] for p in passes]
            for group in groups:
                if type(group) is not list or any(type(r) is not dict or set(r)!=set(('items','publications','sample',*PHASES,*METRICS)) or any(type(v) is not int for v in r.values()) for r in group):
                    raise ValueError('Invalid structured sustained sample')
                encoded=''.join('growth\t'+'\t'.join(str(row[k]) for k in ('items','publications','sample',*PHASES,*METRICS))+'\n' for row in group)
                if parse_growth(encoded,engine,count,steps)!=group:
                    raise ValueError('Noncanonical sustained samples')
            if any(any(r[k]!=groups[0][0][k] for k in METRICS) for group in groups for r in group):
                raise ValueError('Unstable sustained physical work')
            observations[engine]=groups
        for phase in PHASES:
            engines={}
            for engine,groups in observations.items():
                if unavailable(engine,phase):
                    engines[engine]=None
                    continue
                values=sorted(r[phase] for group in groups for r in group[3:])
                medians=[statistics.median(r[phase] for r in group[3:]) for group in groups]
                engines[engine]=dict(median_ns=statistics.median(values),min_ns=min(values),max_ns=max(values),
                    pass_medians_ns=medians,noisy=max(medians)/min(medians)>1.25 or values[18]/values[1]>2,
                    metrics={k:groups[0][0][k] for k in METRICS})
            ratios={}
            for engine in ENGINES[1:]:
                memory=engines['memory'];other=engines[engine]
                if memory is None or other is None:
                    ratios[engine]=None
                else:
                    paired=[other['pass_medians_ns'][i]/memory['pass_medians_ns'][i] for i in range(2)]
                    ratios[engine]=dict(pooled=other['median_ns']/memory['median_ns'],pass_ratios=paired,
                        unstable=max(paired)/min(paired)>1.25)
            cases.append(dict(items=count,publications=steps,phase=phase,engines=engines,ratios=ratios))
    return cases


def validate_growth(report):
    """Native completion, source-bound binary identity and raw-derived statistics all remain mandatory."""
    if type(report) is not dict or report.get('status')!='checks-passed' or type(report.get('schema_version')) is not int or report['schema_version']!=1:
        raise ValueError('Invalid sustained report status/schema')
    if re.fullmatch('[0-9a-f]{64}',str(report.get('native_binary_sha256'))) is None:
        raise ValueError('Invalid sustained native identity')
    checks=report.get('checks')
    if type(checks) is not list or len(checks)!=25:
        raise ValueError('Incomplete sustained native execution')
    logs=[]
    for check in checks:
        if type(check) is not dict or type(check.get('exit_code')) is not int or check['exit_code']!=0:
            raise ValueError('Failed sustained native execution')
        duration=check.get('elapsed_seconds');log=check.get('log')
        if type(duration) not in (int,float) or not math.isfinite(duration) or duration<0 or type(log) is not str or not 0<len(log)<=4096:
            raise ValueError('Invalid sustained native evidence')
        logs.append(log)
    if len(set(logs))!=len(logs) or report.get('error'):
        raise ValueError('Duplicate or failed sustained evidence')
    cases=aggregate_growth(report.get('passes'))
    if json.dumps(cases,sort_keys=True,allow_nan=False)!=json.dumps(report.get('cases'),sort_keys=True,allow_nan=False):
        raise ValueError('Sustained statistics differ from raw samples')
    return cases


def summarize_growth(report):
    """Render only validated matching work; parent provenance supplies source/compiler/profile authority."""
    cases=validate_growth(report)
    lines=['### Sustained storage workload','','256-byte values, leading keys, four writes per publication; 20 measured samples in opposite backend orders.',
        'Microseconds per operation batch: median [min–max]. Preparation and complete-map validation are outside timing.','',
        '| Entries | Publications | Operation | Memory | Journal | Managed | Journal / memory | Managed / memory |',
        '| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |']
    for case in cases:
        cells=[]
        for engine in ENGINES:
            item=case['engines'][engine]
            cells.append('—' if item is None else f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]'+(' †' if item['noisy'] else ''))
        for engine in ENGINES[1:]:
            ratio=case['ratios'][engine]
            cells.append('—' if ratio is None else f'{ratio["pooled"]:.2f}×'+(' ‡' if ratio['unstable'] else ''))
        lines.append(f'| {case["items"]} | {case["publications"]} | {LABELS[PHASES.index(case["phase"])]} | '+' | '.join(cells)+' |')
    lines+=['','Selected physical records and files (not total directory usage or reader memory):','',
        '| Entries | Publications | Backend | Stored / nine-root / current records | Selected bytes before / current-only |',
        '| ---: | ---: | --- | ---: | ---: |']
    for case in cases:
        if case['phase']!='publication':
            continue
        for engine in ENGINES:
            m=case['engines'][engine]['metrics']
            counts=' / '.join('—' if m[k]==-1 else str(m[k]) for k in METRICS[:3])
            before='—' if engine=='memory' else str(m['snapshot_bytes']+m['journal_bytes'])
            after='—' if engine!='managed' else str(m['compacted_snapshot_bytes']+m['compacted_journal_bytes'])
            lines.append(f'| {case["items"]} | {case["publications"]} | {engine} | {counts} | {before} / {after} |')
    lines+=['','† Absolute timing noise and ‡ paired-ratio order sensitivity use the same thresholds as the short workload.',
        'Disk publication synchronizes each revision; memory publication is not durable. Reopen uses the live OS cache.',
        'Nine-root reclamation retains the seed plus the final eight revisions, then current-only reclamation runs separately.']
    return '\n'.join(lines)+'\n'
