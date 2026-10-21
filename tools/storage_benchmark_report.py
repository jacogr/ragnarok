# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete storage samples and render truthful memory/journal/managed speed tables."""
import statistics

ENGINES=('memory','journal','managed')
COUNTS=(1024,8192)
TOPOLOGIES=('leading','trailing')
VALUE_BYTES=(16,256)
CASES=tuple((count,topology,value_bytes) for count in COUNTS for topology in TOPOLOGIES for value_bytes in VALUE_BYTES)
PHASES=('publication','reads','extraction','reopen','maintenance')
LABELS=('16 publications','4,096 warm-view reads','Complete-map extraction','Strict disk reopen','Current-root reclamation')


# Native success alone cannot substitute for all warmup/sample identities and positive timings.
def parse_output(output, engine, count, topology='leading', value_bytes=256):
    if engine not in ENGINES or count not in COUNTS or topology not in TOPOLOGIES or value_bytes not in VALUE_BYTES:
        raise ValueError('Unknown storage benchmark configuration')
    rows=[]
    for line in output.splitlines():
        fields=line.split('\t')
        if len(fields)!=10 or fields[0]!='sample':
            raise ValueError('Unexpected storage benchmark output')
        size=int(fields[1])
        if fields[2]!=topology:
            raise ValueError('Wrong storage key topology')
        if int(fields[3])!=value_bytes:
            raise ValueError('Wrong storage value representation')
        sample,*times=map(int,fields[4:])
        if size!=count or not 0<=sample<13 or any(not 0<t<(1<<63) for t in times[:3]):
            raise ValueError('Invalid storage benchmark sample')
        for phase,duration in zip(PHASES,times):
            # Unsupported operations have exactly one sentinel; no fabricated duration or ratio is accepted.
            missing=(engine=='memory' and phase=='reopen') or (engine=='journal' and phase=='maintenance')
            if (missing and duration!=-1) or (not missing and not 0<duration<(1<<63)):
                raise ValueError('Invalid storage operation observation')
        rows.append(dict(items=size,topology=topology,value_bytes=value_bytes,sample=sample,**dict(zip(PHASES,times))))
    if sorted(r['sample'] for r in rows)!=list(range(13)):
        raise ValueError('Missing or duplicate storage samples')
    return sorted(rows,key=lambda r:r['sample'])


# Recompute every statistic from complete opposite-order passes; never accept substituted medians.
def aggregate(passes):
    if len(passes)!=2:
        raise ValueError('Two complete storage passes required')
    expected={f'{engine}-{count}-{topology}-{value_bytes}' for engine in ENGINES for count,topology,value_bytes in CASES}
    if any(set(p)!=expected for p in passes):
        raise ValueError('Incomplete storage backend/size coverage')
    cases=[]
    for count,topology,value_bytes in CASES:
        for phase in PHASES:
            engines={}
            for engine in ENGINES:
                rows=[p[f'{engine}-{count}-{topology}-{value_bytes}'] for p in passes]
                for group in rows:
                    # Reparse structured evidence through the same strict native-output contract.
                    encoded=''.join('sample\t'+str(r['items'])+'\t'+r['topology']+'\t'+str(r['value_bytes'])+'\t'+str(r['sample'])+'\t'+
                        '\t'.join(str(r[k]) for k in PHASES)+'\n' for r in group)
                    if parse_output(encoded,engine,count,topology,value_bytes)!=group:
                        raise ValueError('Noncanonical storage samples')
                if (phase=='reopen' and engine=='memory') or (phase=='maintenance' and engine=='journal'):
                    engines[engine]=None
                else:
                    groups=[[r[phase] for r in group if r['sample']>=3] for group in rows]
                    values=sorted(groups[0]+groups[1])
                    medians=[statistics.median(group) for group in groups]
                    engines[engine]=dict(median_ns=statistics.median(values),min_ns=min(values),
                        max_ns=max(values),noisy=max(medians)/min(medians)>1.25 or values[18]/values[1]>2)
            cases.append(dict(items=count,topology=topology,value_bytes=value_bytes,phase=phase,engines=engines))
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
            '| Entries | Key topology | Value bytes | Operation | Memory | Journal | Managed | Journal / memory | Managed / memory |',
            '| ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |']
        for case in cases:
            cells=[]
            for engine in ENGINES:
                item=case['engines'][engine]
                cells.append('—' if item is None else
                    f'{item["median_ns"]/1000:.2f} [{item["min_ns"]/1000:.2f}–{item["max_ns"]/1000:.2f}]'+(' †' if item['noisy'] else ''))
            memory=case['engines']['memory']
            ratios=['—' if memory is None or case['engines'][e] is None else
                f'{case["engines"][e]["median_ns"]/memory["median_ns"]:.2f}×' for e in ENGINES[1:]]
            lines.append('| '+str(case['items'])+' | '+case['topology']+' | '+str(case['value_bytes'])+' | '+LABELS[PHASES.index(case['phase'])]+' | '+
                         ' | '.join(cells+ratios)+' |')
        lines+=['','† Noisy: pass medians differ by >25% or central sample spread exceeds 2×; ratios are provisional.']
    else:
        lines+=['No complete validated comparison is available.']
    if report.get('error'):
        safe=' '.join(str(report['error']).split())[:500].replace('<','&lt;').replace('>','&gt;')
        lines+=['','Failure: '+safe]
    lines+=['','Disk publication includes real synchronization; memory publication is not durable.',
        'Reads use warm resident repository views for every backend, not cold/random disk reads. '
        'Reopen includes strict selected snapshot/journal admission; memory has no durable reopen.',
        'Leading/trailing key pairs distinguish short/deep prefixes. Checked native ARC/Clang release LTO, 16/256-byte values, sixteen sparse updates. '
        'Current-root reclamation clones selected memory records or durably compacts managed storage; journal has no equivalent. Setup and fixture cleanup are outside timing.',
        'Observations on one recorded host; no affinity/frequency isolation or fixed speed threshold.',
        'Download `summary.md`, `results.json`, `samples.csv` and logs for raw measurements and provenance.']
    return '\n'.join(lines)+'\n'
