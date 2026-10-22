# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete storage samples and render truthful memory/journal/managed speed tables."""
import json
import math
from pathlib import PurePosixPath
import re
import statistics
from storage_growth_report import summarize_growth
from storage_growth import SOURCES as GROWTH_SOURCES
from storage_growth_io import SOURCE_FIELDS as IO_SOURCE_FIELDS

REPORT_VERSION=23
PROFILE='checked native ARC/Clang release opt:speed boundchecks:on LTO'
NATIVE_SOURCES=('native/crypto/primitive_bridge.c','native/crypto/primitive_bridge.h',
    'native/crypto/rust_primitives.h','native/bandersnatch/Cargo.lock','tools/build_bandersnatch.py',
    'spec/bandersnatch-pins.json')
REQUIRED_SOURCES=('tests/performance/storage_workload.nim','tests/support/managed_storage_samples.nim',
    'tests/support/storage_samples.nim','tools/storage_benchmark.py','tools/storage_benchmark_report.py',
    'tools/native_checks.py','tools/native_source_identity.py','tools/pvm_reference.py',
    'tools/build_crypto.py','spec/crypto-pins.json','spec/toolchain.json','Makefile','.github/workflows/ci.yml',*GROWTH_SOURCES,*NATIVE_SOURCES)

ENGINES=('memory','journal','managed')
COUNTS=(1024,8192)
TOPOLOGIES=('leading','trailing')
VALUE_BYTES=(16,256)
BATCH_WIDTHS=(1,4)
CASES=tuple((count,topology,value_bytes,batch_width) for count in COUNTS for topology in TOPOLOGIES for value_bytes in VALUE_BYTES for batch_width in BATCH_WIDTHS)
PHASES=('publication','reads','extraction','reopen','maintenance','retention','snapshots','misses')
METRICS=('stored_nodes','selected_nodes','snapshot_bytes','journal_bytes','compacted_snapshot_bytes','compacted_journal_bytes')
LABELS=('16 publications','4,096 warm-view reads','Complete-map extraction','Strict disk reopen','Current-root reclamation','Nine-root reclamation','4,096 retained snapshots','4,096 missing-address lookups')


# Reject malformed provenance before rendering a successful comparison; partial failures stay diagnosable.
def validate_provenance(report):
    def require(condition,field):
        # Every structural refusal names the field without dumping potentially large or untrusted content.
        if not condition:
            raise ValueError('Invalid storage benchmark provenance: '+field)
    def digest(value,length):
        # Hash syntax records an identity; it does not grant checkpoint or execution authority.
        return isinstance(value,str) and re.fullmatch('[0-9a-f]{'+str(length)+'}',value) is not None
    require(type(report.get('schema_version')) is int and report['schema_version']==REPORT_VERSION,'schema')
    require(report.get('profile')==PROFILE,'checked profile')
    panel=report.get('panel','combined')
    require(panel in ('comparison','growth','combined'),'panel scope')
    require(digest(report.get('head'),40) and type(report.get('worktree_dirty')) is bool,'source revision')
    for field in ('crypto_sha256','compiler_sha256','native_binary_sha256'):
        require((field=='native_binary_sha256' and panel=='growth') or digest(report.get(field),64),field)
    components=report.get('native_components')
    require(type(components) is dict and set(components)=={'bridge','provider_loader','provider_build'},'native closure')
    require(all(digest(v,64) for v in components.values()) and components['bridge']==report['crypto_sha256'] and
        components['provider_loader']==components['provider_build'],'native closure identity')
    for field,expected in (('warmups_per_pass',3),('measured_samples_per_pass',10),('pass_count',2)):
        require(type(report.get(field)) is int and report[field]==expected,field)
    for field,expected in (('backends',ENGINES),('item_counts',COUNTS),('key_topologies',TOPOLOGIES),
            ('value_sizes',VALUE_BYTES),('batch_widths',BATCH_WIDTHS),('phase_names',PHASES),('physical_metrics',METRICS)):
        value=report.get(field)
        require(type(value) is list and value==list(expected) and
                all(type(item) is type(expected[0]) for item in value),field)
    if panel == 'growth':
        # Growth-only reports must not carry a partial or stale short comparison.
        require(report.get('passes')==[] and report.get('cases')==[] and 'native_binary_sha256' not in report,'growth-only coverage')
    else:
        # The short comparison retains its complete workload and opposite backend orders.
        orders=[list(ENGINES),list(reversed(ENGINES))]
        require(report.get('pass_orders')==orders,'opposite backend orders')
        passes=report.get('passes')
        require(type(passes) is list and len(passes)==2,'complete passes')
        for order,observations in zip(orders,passes):
            expected=[f'{e}-{n}-{t}-{v}-{w}' for e in order for n,t,v,w in CASES]
            require(type(observations) is dict and list(observations)==expected,'observed backend order')
    sources=report.get('sources')
    require(type(sources) is dict and len(REQUIRED_SOURCES)<=len(sources)<=16384,'source manifest')
    require(set(REQUIRED_SOURCES)<=set(sources),'required sources')
    for name,value in sources.items():
        require(type(name) is str and 0<len(name)<=1024 and '\x00' not in name and '\\' not in name,'source name')
        path=PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts and str(path)==name and digest(value,64),'source identity')
    toolchain=report.get('toolchain')
    require(type(toolchain) is dict and type(toolchain.get('schema')) is int and toolchain['schema']==1,'toolchain')
    require(digest(toolchain.get('commit'),40) and isinstance(toolchain.get('version'),str) and
            re.fullmatch(r'\d+\.\d+\.\d+',toolchain['version']) is not None,'toolchain identity')
    require(isinstance(report.get('clang'),str) and 0<len(report['clang'])<=1024,'Clang version')
    hardware=report.get('hardware')
    require(type(hardware) is dict,'hardware')
    for field in ('platform','machine','cpu'):
        require(isinstance(hardware.get(field),str) and 0<len(hardware[field])<=4096,'hardware '+field)
    cpus=hardware.get('logical_cpus')
    require(cpus is None or (type(cpus) is int and 0<cpus<=1048576),'logical CPUs')
    for field in ('load_average_start','load_average_end'):
        values=hardware.get(field)
        require(type(values) in (list,tuple) and len(values)==3 and
                all(type(v) in (int,float) and math.isfinite(v) and v>=0 for v in values),field)
    growth_summary=''
    if panel == 'comparison':
        # A short-only report cannot silently embed stale growth evidence from a previous run.
        require('growth' not in report,'comparison-only coverage')
    else:
        # Reparse the same full sustained/SDK contract in both standalone and historical combined reports.
        growth_summary=summarize_growth(report.get('growth'))
        for field,name in IO_SOURCE_FIELDS.items():
            require(report['growth']['io'][field]==sources[name],'SDK '+field)
    checks=report.get('checks')
    require(type(checks) is list and len(checks)==(0 if panel=='growth' else 1+2*len(ENGINES)*len(CASES)),'native checks')
    logs=[]
    for check in checks:
        require(type(check) is dict and type(check.get('exit_code')) is int and check['exit_code']==0,'native exit')
        require(isinstance(check.get('log'),str) and 0<len(check['log'])<=4096,'native log')
        elapsed=check.get('elapsed_seconds')
        require(type(elapsed) in (int,float) and math.isfinite(elapsed) and elapsed>=0,'native elapsed')
        logs.append(check['log'])
    require(len(set(logs))==len(logs) and not report.get('error'),'successful evidence')
    return growth_summary # Parent rendering reuses this already validated child text in the same call.


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
                        max_ns=max(values),pass_medians_ns=medians,metrics={k:rows[0][0][k] for k in METRICS},noisy=max(medians)/min(medians)>1.25 or values[18]/values[1]>2)
            ratios={}
            for engine in ENGINES[1:]:
                memory=engines['memory'];other=engines[engine]
                if memory is None or other is None:
                    ratios[engine]=None
                else:
                    # Opposite-order pass medians expose ratios hidden by pooling across host drift.
                    paired=[other['pass_medians_ns'][i]/memory['pass_medians_ns'][i] for i in range(2)]
                    ratios[engine]=dict(pooled=other['median_ns']/memory['median_ns'],
                        pass_ratios=paired,unstable=max(paired)/min(paired)>1.25)
            cases.append(dict(items=count,topology=topology,value_bytes=value_bytes,batch_width=batch_width,phase=phase,engines=engines,ratios=ratios))
    return cases


# Failed/incomplete runs retain diagnostics but cannot expose a stale successful ratio table.
def summarize_benchmark(report):
    status=report['status']
    if status not in ('running','failed','checks-passed'):
        raise ValueError('Unknown storage benchmark status')
    title='Storage sustained growth' if report.get('panel')=='growth' else 'Storage speed comparison'
    lines=['## '+title,'','**Status: '+status+'**','']
    if status=='checks-passed':
        growth_summary=validate_provenance(report)
        if report.get('panel')=='growth':
            # Validation above includes the full child matrix, SDK witnesses and parent provenance.
            return "\n".join(lines)+growth_summary
        cases=aggregate(report['passes'])
        if json.dumps(report['cases'],sort_keys=True,allow_nan=False)!=json.dumps(cases,sort_keys=True,allow_nan=False):
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
            ratios=[]
            for engine in ENGINES[1:]:
                ratio=case['ratios'][engine]
                ratios.append('—' if ratio is None else f'{ratio["pooled"]:.2f}×'+(' ‡' if ratio['unstable'] else ''))
            lines.append('| '+str(case['items'])+' | '+case['topology']+' | '+str(case['value_bytes'])+' | '+str(case['batch_width'])+' | '+LABELS[PHASES.index(case['phase'])]+' | '+
                         ' | '.join(cells+ratios)+' |')
        lines+=['','† Noisy: pass medians differ by >25% or central sample spread exceeds 2×; ratios are provisional.','‡ Unstable ratio: opposite-order pass-median ratios differ by >25%; pooling can hide order or host effects.']
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
        lines+=['',growth_summary.rstrip()]
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
