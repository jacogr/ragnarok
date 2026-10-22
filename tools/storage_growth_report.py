# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate sustained storage observations independently of native success and render matched work."""
import json
import math
import re
import statistics

ENGINES=('memory','journal','managed')
COUNTS=(1024,8192,32768)
PUBLICATIONS=(64,256)
PATTERNS=('sweep','hot')
CASES=tuple((count,steps,pattern) for count in COUNTS for steps in PUBLICATIONS for pattern in PATTERNS if count!=32768 or pattern=='sweep')
PHASES=('publication','reopen','retention','maintenance','retained_reopen','compacted_reopen','extraction_before','extraction_after','reads_before','reads_after','snapshots')
METRICS=('stored_nodes','retained_nodes','current_nodes','snapshot_bytes','journal_bytes',
         'retained_snapshot_bytes','retained_journal_bytes','compacted_snapshot_bytes','compacted_journal_bytes')
LABELS=('Sustained publication','Strict disk reopen','Nine-root reclamation','Current-root reclamation','Strict nine-root reopen','Strict current-root reopen','Complete-map extraction before reclamation','Current-only complete-map extraction','4096 spread resident reads before reclamation','4096 current-only spread resident reads','4096 retained snapshots')


def unavailable(engine,phase):
    """Unavailable public operations retain one exact sentinel and never acquire fabricated ratios."""
    return (engine=='memory' and phase=='reopen') or (engine=='journal' and phase in ('retention','maintenance','extraction_after','reads_after')) or (engine!='managed' and phase in ('retained_reopen','compacted_reopen'))


def parse_growth(output,engine,count,steps,pattern='sweep',*,samples=13):
    """Require exact identities, complete ordered samples and bounded typed timings/physical metrics."""
    if engine not in ENGINES or type(count) is not int or count not in COUNTS or type(steps) is not int or steps not in PUBLICATIONS or pattern not in PATTERNS or (count,steps,pattern) not in CASES:
        raise ValueError('Unknown sustained storage configuration')
    # Resource controls accept one validated trajectory; speed callers retain exactly thirteen.
    if type(samples) is not int or samples not in (1,13):
        raise ValueError('Invalid sustained sample plan')
    rows=[]
    durations=[]
    for line in output.splitlines():
        fields=line.split('\t')
        if fields[0]=='publication':
            # Every native call has one bounded ordered witness, tied to the enclosing sample identity.
            if len(fields)!=7 or fields[3]!=pattern or any(re.fullmatch(r'0|[1-9][0-9]{0,18}',v) is None for v in (*fields[1:3],*fields[4:])):
                raise ValueError('Invalid publication latency output')
            size,publications,sample,revision,duration=map(int,(*fields[1:3],*fields[4:]))
            if (size,publications,sample)!=(count,steps,len(rows)) or revision!=len(durations)+1 or revision>steps or not 0<duration<(1<<63):
                raise ValueError('Invalid publication latency identity')
            durations.append(duration)
            continue
        if len(fields)!=5+len(PHASES)+len(METRICS) or fields[0]!='growth' or fields[3]!=pattern or any(
                re.fullmatch(r'-1|0|[1-9][0-9]{0,18}',value) is None for value in (*fields[1:3],*fields[4:])):
            raise ValueError('Invalid sustained storage output')
        size,publications,sample,*values=map(int,(*fields[1:3],*fields[4:]))
        if size!=count or publications!=steps or sample!=len(rows) or sample>=samples:
            raise ValueError('Invalid sustained sample identity')
        row=dict(items=size,publications=publications,pattern=pattern,sample=sample,**dict(zip((*PHASES,*METRICS),values)))
        if len(durations)!=steps or sum(durations)>row['publication']:
            raise ValueError('Incomplete or impossible publication latency coverage')
        row['publication_samples']=durations
        durations=[]
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
            missing=engine=='memory' or (engine=='journal' and metric.startswith(('retained_','compacted_')))
            zero=engine=='journal' and metric=='snapshot_bytes'
            if (missing and value!=-1) or (zero and value!=0) or (not missing and not zero and not 0<value<(1<<63)):
                raise ValueError('Invalid sustained selected-file extent')
        rows.append(row)
    if len(rows)!=samples or durations:
        raise ValueError('Incomplete sustained sample coverage')
    return rows


def _encode_rows(rows):
    """Reconstruct canonical native evidence so structured reports retain every ordered call witness."""
    output=[]
    for row in rows:
        for revision,duration in enumerate(row['publication_samples'],1):
            output.append('publication\t'+'\t'.join(map(str,(row['items'],row['publications'],row['pattern'],row['sample'],revision,duration)))+'\n')
        output.append('growth\t'+'\t'.join(str(row[k]) for k in ('items','publications','pattern','sample',*PHASES,*METRICS))+'\n')
    return ''.join(output)


def aggregate_growth(passes):
    """Revalidate all raw values before deriving matched operation distributions and paired ratios."""
    orders=(ENGINES,tuple(reversed(ENGINES)))
    if type(passes) is not list or len(passes)!=2:
        raise ValueError('Two sustained passes required')
    for order,observations in zip(orders,passes):
        expected=[f'{e}-{n}-{s}-{pattern}' for e in order for n,s,pattern in CASES]
        if type(observations) is not dict or list(observations)!=expected:
            raise ValueError('Incomplete sustained backend order')
    cases=[]
    for count,steps,pattern in CASES:
        observations={}
        for engine in ENGINES:
            groups=[p[f'{engine}-{count}-{steps}-{pattern}'] for p in passes]
            for group in groups:
                if type(group) is not list:
                    raise ValueError('Invalid structured sustained sample group')
                for row in group:
                    # Lists and scalar fields are typed before canonical text is reconstructed.
                    if type(row) is not dict or set(row)!=set(('items','publications','pattern','sample',*PHASES,*METRICS,'publication_samples')):
                        raise ValueError('Invalid structured sustained sample')
                    if row['pattern']!=pattern or any(type(v) is not int for k,v in row.items() if k not in ('pattern','publication_samples')):
                        raise ValueError('Invalid structured sustained scalar')
                    if type(row['publication_samples']) is not list or any(type(v) is not int for v in row['publication_samples']):
                        raise ValueError('Invalid structured publication latencies')
                encoded=_encode_rows(group)
                if parse_growth(encoded,engine,count,steps,pattern)!=group:
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
                if phase=='publication':
                    # Nearest-rank p95 describes correlated calls; each measured run still contributes one batch.
                    calls=sorted(t for group in groups for row in group[3:] for t in row['publication_samples'])
                    pass_p95=[]
                    for group in groups:
                        ordered=sorted(t for row in group[3:] for t in row['publication_samples'])
                        pass_p95.append(ordered[(95*len(ordered)+99)//100-1])
                    engines[engine]['latency']=dict(calls=len(calls),median_ns=statistics.median(calls),
                        p95_ns=calls[(95*len(calls)+99)//100-1],max_ns=max(calls),pass_p95_ns=pass_p95,
                        p95_unstable=max(pass_p95)/min(pass_p95)>1.25,
                        mean_call_ns=engines[engine]['median_ns']/steps,
                        writes_per_second=4*steps*1e9/engines[engine]['median_ns'])
            ratios={}
            for engine in ENGINES[1:]:
                memory=engines['memory'];other=engines[engine]
                if memory is None or other is None:
                    ratios[engine]=None
                else:
                    paired=[other['pass_medians_ns'][i]/memory['pass_medians_ns'][i] for i in range(2)]
                    ratios[engine]=dict(pooled=other['median_ns']/memory['median_ns'],pass_ratios=paired,
                        unstable=max(paired)/min(paired)>1.25)
            cases.append(dict(items=count,publications=steps,pattern=pattern,phase=phase,engines=engines,ratios=ratios))
    for count in COUNTS:
        if (count,64,'hot') not in CASES:
            continue # The bounded largest-map plan intentionally contains sweep trajectories only.
        # At 64 publications both patterns perform exactly the same writes: physical work is a positive control.
        for engine in ENGINES:
            sweep=passes[0][f'{engine}-{count}-64-sweep'][0]
            hot=passes[0][f'{engine}-{count}-64-hot'][0]
            if any(sweep[k]!=hot[k] for k in METRICS):
                raise ValueError('Locality positive-control work differs')
    return cases


def _validate_commands(checks):
    """Tie every measured run to the checked native build and its exact declared thirteen-sample plan."""
    commands=[check.get('command') for check in checks]
    for command in commands:
        if type(command) is not list or not 0<len(command)<=128 or any(type(v) is not str or not 0<len(v)<=4096 or '\x00' in v for v in command):
            raise ValueError('Invalid sustained command provenance')
    build=commands[0]
    required=['--mm:arc','--cc:clang','-d:release','--opt:speed','--boundchecks:on','--passC:-flto','--passL:-flto']
    if len(build)<11 or build[1]!='c' or build[2:9]!=required or tuple(build[-1].replace('\\','/').split('/')[-3:])!=('tests','performance','storage_growth_workload.nim'):
        raise ValueError('Invalid sustained checked build plan')
    forbidden=('--checks:off','--boundchecks:off','--rangechecks:off','--assertions:off','-d:danger','--define:danger','-d:storageIoCounts','--define:storageIoCounts')
    if any(v in forbidden or any(v.startswith(prefix) and v!=expected for prefix,expected in (('--mm:','--mm:arc'),('--cc:','--cc:clang'),('--opt:','--opt:speed'))) for v in build):
        raise ValueError('Unchecked or observed profile cannot supply speed samples')
    outputs=[v.removeprefix('--out:') for v in build if v.startswith('--out:')]
    if len(outputs)!=1:
        raise ValueError('Ambiguous sustained native executable')
    expected=[(e,n,steps,p) for order in (ENGINES,tuple(reversed(ENGINES))) for e in order for n,steps,p in CASES]
    for command,(engine,count,steps,pattern) in zip(commands[1:],expected):
        if len(command)!=7 or command[0]!=outputs[0] or command[1:4]!=[engine,str(count),str(steps)] or command[5:]!=['13',pattern]:
            raise ValueError('Sustained command differs from measured case/sample plan')


def validate_growth(report):
    """Native completion, source-bound binary identity and raw-derived statistics all remain mandatory."""
    if type(report) is not dict or report.get('status')!='checks-passed' or type(report.get('schema_version')) is not int or report['schema_version']!=11:
        raise ValueError('Invalid sustained report status/schema')
    if re.fullmatch('[0-9a-f]{64}',str(report.get('native_binary_sha256'))) is None:
        raise ValueError('Invalid sustained native identity')
    from storage_growth_io import validate_io
    validate_io(report.get('io'))
    checks=report.get('checks')
    if type(checks) is not list or len(checks)!=1+2*len(ENGINES)*len(CASES):
        raise ValueError('Incomplete sustained native execution')
    logs=[]
    for check in checks:
        if type(check) is not dict or type(check.get('exit_code')) is not int or check['exit_code']!=0:
            raise ValueError('Failed sustained native execution')
        duration=check.get('elapsed_seconds');log=check.get('log')
        if type(duration) not in (int,float) or not math.isfinite(duration) or duration<0 or type(log) is not str or not 0<len(log)<=4096:
            raise ValueError('Invalid sustained native evidence')
        logs.append(log)
    _validate_commands(checks)
    if len(set(logs))!=len(logs) or report.get('error'):
        raise ValueError('Duplicate or failed sustained evidence')
    cases=aggregate_growth(report.get('passes'))
    if json.dumps(cases,sort_keys=True,allow_nan=False)!=json.dumps(report.get('cases'),sort_keys=True,allow_nan=False):
        raise ValueError('Sustained statistics differ from raw samples')
    return cases


def _growth_scaling(cases):
    """Compare equal case/backend work at 64 and 256 revisions, retaining paired-order uncertainty."""
    rows=[]
    for count in COUNTS:
        for pattern in PATTERNS:
            if any((count,steps,pattern) not in CASES for steps in PUBLICATIONS):
                continue # Only explicitly configured matching trajectory pairs can produce a growth ratio.
            pair=[next(c for c in cases if c['items']==count and c['publications']==steps and
                c['pattern']==pattern and c['phase']=='publication') for steps in PUBLICATIONS]
            for engine in ENGINES:
                short=pair[0]['engines'][engine];long=pair[1]['engines'][engine]
                ratio=long['median_ns']/short['median_ns']/4
                paired=[long['pass_medians_ns'][i]/short['pass_medians_ns'][i]/4 for i in range(2)]
                before=short['metrics'];after=long['metrics']
                byte_growth=None if engine=='memory' else after['snapshot_bytes']+after['journal_bytes']-before['snapshot_bytes']-before['journal_bytes']
                rows.append(dict(items=count,pattern=pattern,backend=engine,normalized_ratio=ratio,
                    unstable=max(paired)/min(paired)>1.25,record_growth=after['stored_nodes']-before['stored_nodes'],
                    selected_byte_growth=byte_growth,payload_bytes=(256-64)*4*256))
    return rows


def summarize_growth(report):
    """Render only validated matching work; parent provenance supplies source/compiler/profile authority."""
    cases=validate_growth(report)
    lines=['### Sustained storage workload','','256-byte values, leading keys, four writes per publication; 20 measured samples in opposite backend orders.',
        'Microseconds per operation batch: median [min–max]. Preparation and complete-map validation are outside timing.','',
        '| Entries | Publications | Updates | Operation | Memory | Journal | Managed | Journal / memory | Managed / memory |',
        '| ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |']
    for case in cases:
        cells=[]
        for engine in ENGINES:
            item=case['engines'][engine]
            cells.append('—' if item is None else f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]'+(' †' if item['noisy'] else ''))
        for engine in ENGINES[1:]:
            ratio=case['ratios'][engine]
            cells.append('—' if ratio is None else f'{ratio["pooled"]:.2f}×'+(' ‡' if ratio['unstable'] else ''))
        lines.append(f'| {case["items"]} | {case["publications"]} | {case["pattern"]} | {LABELS[PHASES.index(case["phase"])]} | '+' | '.join(cells)+' |')
    lines+=['','Per-publication latency and normalized work (warmups excluded):','',
        '| Entries | Publications | Updates | Backend | Batch mean µs/call | Call p50 / p95 / max µs | Writes/s |',
        '| ---: | ---: | --- | --- | ---: | ---: | ---: |']
    for case in cases:
        if case['phase']!='publication':
            continue
        for engine in ENGINES:
            latency=case['engines'][engine]['latency']
            tail=' / '.join(f'{latency[k]/1000:.2f}' for k in ('median_ns','p95_ns','max_ns'))
            if latency['p95_unstable']:
                tail+=' ‡'
            lines.append(f'| {case["items"]} | {case["publications"]} | {case["pattern"]} | {engine} | '+
                f'{latency["mean_call_ns"]/1000:.2f} | {tail} | {latency["writes_per_second"]:.1f} |')
    lines+=['','Call p95 uses nearest rank over measured calls; calls within a run are correlated, not independent trials.',
        'Batch means and writes/s derive from matching batch medians, including loop/clock overhead; each call writes four keys.',
        '‡ on a call tail marks >25% opposite-order p95 drift. No fixed throughput or latency threshold is imposed.']
    lines+=['','Growth from 64 to 256 publications (four times the authored work):','',
        '| Entries | Updates | Backend | Per-call batch cost ratio | Added stored records | Selected-file growth bytes | File growth / authored value bytes |',
        '| ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for row in _growth_scaling(cases):
        selected='—' if row['selected_byte_growth'] is None else str(row['selected_byte_growth'])
        amplification='—' if row['selected_byte_growth'] is None else f'{row["selected_byte_growth"]/row["payload_bytes"]:.2f}×'
        ratio=f'{row["normalized_ratio"]:.2f}×'+(' ‡' if row['unstable'] else '')
        lines.append(f'| {row["items"]} | {row["pattern"]} | {row["backend"]} | {ratio} | '+
            f'{row["record_growth"]} | {selected} | {amplification} |')
    lines+=['','The time ratio divides the 256/64 batch-median ratio by 4; 1× means equal average cost per publication.',
        'File growth includes selected snapshot/journal framing; it is not device write amplification, allocated blocks or total directory usage.',
        'The comparison associates elapsed work with a longer trajectory; it does not isolate OS cache or host effects.']
    lines+=['','Selected physical records and files (not total directory usage or reader memory):','',
        '| Entries | Publications | Updates | Backend | Stored / nine-root / current records | Selected bytes initial / nine-root / current-only |',
        '| ---: | ---: | --- | --- | ---: | ---: |']
    for case in cases:
        if case['phase']!='publication':
            continue
        for engine in ENGINES:
            m=case['engines'][engine]['metrics']
            counts=' / '.join('—' if m[k]==-1 else str(m[k]) for k in METRICS[:3])
            before='—' if engine=='memory' else str(m['snapshot_bytes']+m['journal_bytes'])
            retained='—' if engine!='managed' else str(m['retained_snapshot_bytes']+m['retained_journal_bytes'])
            after='—' if engine!='managed' else str(m['compacted_snapshot_bytes']+m['compacted_journal_bytes'])
            lines.append(f'| {case["items"]} | {case["publications"]} | {case["pattern"]} | {engine} | {counts} | {before} / {retained} / {after} |')
    lines+=['','† Absolute timing noise and ‡ paired-ratio order sensitivity use the same thresholds as the short workload.',
        'Sweep advances across keys; hot revisits 256 keys with distinct complete revision payloads.',
        'Disk publication synchronizes each revision; memory publication is not durable. Reopen uses the live OS cache.',
        'Nine-root reclamation retains the seed plus the final eight revisions, then current-only reclamation runs separately.']
    from storage_growth_io import summarize_io
    lines+=['',summarize_io(report['io']).rstrip()]
    return '\n'.join(lines)+'\n'
