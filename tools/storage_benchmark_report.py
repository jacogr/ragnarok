# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete storage samples and render truthful memory/journal/managed speed tables."""
import statistics

ENGINES=('memory','journal','managed')
COUNTS=(1024,8192)
TOPOLOGIES=('leading','trailing')
VALUE_BYTES=(16,256)
BATCH_WIDTHS=(1,4)
CASES=tuple((count,topology,value_bytes,batch_width) for count in COUNTS for topology in TOPOLOGIES for value_bytes in VALUE_BYTES for batch_width in BATCH_WIDTHS)
PHASES=('publication','reads','extraction','reopen','maintenance','retention','snapshots','misses')
METRICS=('stored_nodes','selected_nodes','snapshot_bytes','journal_bytes','compacted_snapshot_bytes','compacted_journal_bytes')
LABELS=('16 publications','4,096 warm-view reads','Complete-map extraction','Strict disk reopen','Current-root reclamation','Nine-root reclamation','4,096 retained snapshots','4,096 missing-address lookups')


# Native success alone cannot substitute for all warmup/sample identities and positive timings.
def parse_output(output, engine, count, topology='leading', value_bytes=256, batch_width=1):
    if engine not in ENGINES or count not in COUNTS or topology not in TOPOLOGIES or value_bytes not in VALUE_BYTES or batch_width not in BATCH_WIDTHS:
        raise ValueError('Unknown storage benchmark configuration')
    rows=[]
    for line in output.splitlines():
        fields=line.split('\t')
        if len(fields)!=6+len(PHASES)+len(METRICS) or fields[0]!='sample':
            raise ValueError('Unexpected storage benchmark output')
        size=int(fields[1])
        if fields[2]!=topology:
            raise ValueError('Wrong storage key topology')
        if int(fields[3])!=value_bytes:
            raise ValueError('Wrong storage value representation')
        if int(fields[4])!=batch_width:
            raise ValueError('Wrong storage publication batch width')
        sample=int(fields[5])
        values=list(map(int,fields[6:]))
        times=values[:len(PHASES)]
        physical=dict(zip(METRICS,values[len(PHASES):]))
        if size!=count or not 0<=sample<13 or any(not 0<t<(1<<63) for t in times[:3]):
            raise ValueError('Invalid storage benchmark sample')
        for phase,duration in zip(PHASES,times):
            # Unsupported operations have exactly one sentinel; no fabricated duration or ratio is accepted.
            missing=(engine=='memory' and phase=='reopen') or (engine=='journal' and phase in ('maintenance','retention'))
            if (missing and duration!=-1) or (not missing and not 0<duration<(1<<63)):
                raise ValueError('Invalid storage operation observation')
        if not 0<physical['selected_nodes']<=physical['stored_nodes']<(1<<63):
            raise ValueError('Invalid physical record observation')
        for metric in METRICS[2:]:
            # File metrics describe only selected files; unavailable operations have exact sentinels.
            duration=physical[metric]
            missing=engine=='memory' or (engine=='journal' and metric.startswith('compacted_'))
            zero=engine=='journal' and metric=='snapshot_bytes'
            if (missing and duration!=-1) or (zero and duration!=0) or (not missing and not zero and not 0<duration<(1<<63)):
                raise ValueError('Invalid selected-file extent observation')
        rows.append(dict(items=size,topology=topology,value_bytes=value_bytes,batch_width=batch_width,sample=sample,**dict(zip(PHASES,times)),**physical))
    if sorted(r['sample'] for r in rows)!=list(range(13)):
        raise ValueError('Missing or duplicate storage samples')
    return sorted(rows,key=lambda r:r['sample'])


# Recompute every statistic from complete opposite-order passes; never accept substituted medians.
def aggregate(passes):
    if len(passes)!=2:
        raise ValueError('Two complete storage passes required')
    expected={f'{engine}-{count}-{topology}-{value_bytes}-{batch_width}' for engine in ENGINES for count,topology,value_bytes,batch_width in CASES}
    if any(set(p)!=expected for p in passes):
        raise ValueError('Incomplete storage backend/size coverage')
    cases=[]
    for count,topology,value_bytes,batch_width in CASES:
        for phase in PHASES:
            engines={}
            for engine in ENGINES:
                rows=[p[f'{engine}-{count}-{topology}-{value_bytes}-{batch_width}'] for p in passes]
                for group in rows:
                    # Reparse structured evidence through the same strict native-output contract.
                    encoded=''.join('sample\t'+str(r['items'])+'\t'+r['topology']+'\t'+str(r['value_bytes'])+'\t'+str(r['batch_width'])+'\t'+str(r['sample'])+'\t'+
                        '\t'.join(str(r[k]) for k in (*PHASES,*METRICS))+'\n' for r in group)
                    if parse_output(encoded,engine,count,topology,value_bytes,batch_width)!=group:
                        raise ValueError('Noncanonical storage samples')
                if any(any(row[k]!=rows[0][0][k] for k in METRICS) for group in rows for row in group):
                    raise ValueError('Physical observations changed across identical samples')
                if (phase=='reopen' and engine=='memory') or (phase in ('maintenance','retention') and engine=='journal'):
                    engines[engine]=None
                else:
                    groups=[[r[phase] for r in group if r['sample']>=3] for group in rows]
                    values=sorted(groups[0]+groups[1])
                    medians=[statistics.median(group) for group in groups]
                    engines[engine]=dict(median_ns=statistics.median(values),min_ns=min(values),
                        max_ns=max(values),metrics={k:rows[0][0][k] for k in METRICS},noisy=max(medians)/min(medians)>1.25 or values[18]/values[1]>2)
            cases.append(dict(items=count,topology=topology,value_bytes=value_bytes,batch_width=batch_width,phase=phase,engines=engines))
    return cases


# Failed/incomplete runs retain diagnostics but cannot expose a stale successful ratio table.
def summarize_benchmark(report):
    status=report['status']
    if status not in ('running','failed','checks-passed'):
        raise ValueError('Unknown storage benchmark status')
    lines=['## Storage speed comparison','','**Status: '+status+'**','']
    if status=='checks-passed':
        cases=aggregate(report['passes'])
        if report['cases']!=cases:
            raise ValueError('Storage statistics do not match raw validated samples')
        lines+=['Microseconds per fixed batch: median [min–max], 20 measured samples; three warmups per pass.',
            'Two passes reverse backend order. Fixture preparation and result validation are excluded.','',
            '| Entries | Key topology | Value bytes | Batch writes | Operation | Memory | Journal | Managed | Journal / memory | Managed / memory |',
            '| ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |']
        for case in cases:
            cells=[]
            for engine in ENGINES:
                item=case['engines'][engine]
                cells.append('—' if item is None else
                    f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]'+(' †' if item['noisy'] else ''))
            memory=case['engines']['memory']
            ratios=['—' if memory is None or case['engines'][e] is None else
                f'{case["engines"][e]["median_ns"]/memory["median_ns"]:.2f}×' for e in ENGINES[1:]]
            lines.append('| '+str(case['items'])+' | '+case['topology']+' | '+str(case['value_bytes'])+' | '+str(case['batch_width'])+' | '+LABELS[PHASES.index(case['phase'])]+' | '+
                         ' | '.join(cells+ratios)+' |')
        lines+=['','† Noisy: pass medians differ by >25% or central sample spread exceeds 2×; ratios are provisional.']
        lines+=['','Selected physical storage (not total directory usage or memory retained by readers):','',
            '| Entries | Key topology | Value bytes | Batch writes | Backend | Stored / current records | Selected bytes before / after |',
            '| ---: | --- | ---: | ---: | --- | ---: | ---: |']
        for case in cases:
            if case['phase']=='publication':
                for engine in ENGINES:
                    metrics=case['engines'][engine]['metrics']
                    before='—' if engine=='memory' else str(metrics['snapshot_bytes']+metrics['journal_bytes'])
                    after=str(metrics['compacted_snapshot_bytes']+metrics['compacted_journal_bytes']) if engine=='managed' else '—'
                    lines.append(f'| {case["items"]} | {case["topology"]} | {case["value_bytes"]} | {case["batch_width"]} | {engine} | '+
                        f'{metrics["stored_nodes"]} / {metrics["selected_nodes"]} | {before} / {after} |')
    else:
        lines+=['No complete validated comparison is available.']
    if report.get('error'):
        safe=' '.join(str(report['error']).split())[:500].replace('<','&lt;').replace('>','&gt;')
        lines+=['','Failure: '+safe]
    lines+=['','Disk publication includes real synchronization; memory publication is not durable.',
        'Reads use warm resident repository views for every backend, not cold/random disk reads. '
        'Reopen includes strict selected snapshot/journal admission; memory has no durable reopen.',
        'Leading/trailing key pairs distinguish short/deep prefixes. Checked native ARC/Clang release LTO, 16/256-byte values, sixteen batches of one/four sparse writes. '
        'Nine-root reclamation precedes current-only reclamation; both clone selected memory records or durably compacts managed storage; journal has no equivalent. Setup and fixture cleanup are outside timing.',
        'Observations on one recorded host; no affinity/frequency isolation or fixed speed threshold.',
        'Download `summary.md`, `results.json`, `samples.csv` and logs for raw measurements and provenance.']
    return '\n'.join(lines)+'\n'
