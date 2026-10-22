# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Collect independent SDK-call evidence; instrumented timings never enter Perf Storage comparisons."""
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import tempfile
from native_checks import NativeChecks
from pvm_reference import command
from storage_io_observer import prepare
from storage_growth_report import ENGINES,CASES,PHASES,unavailable

ROOT=Path(__file__).resolve().parents[1]
OPERATIONS=('read','write','fsync','ftruncate','flock','renameat','unlinkat','close')
IO_ORDER=('publication','snapshots','extraction_before','reads_before','reopen','retention',
          'retained_reopen','maintenance','extraction_after','reads_after','compacted_reopen')
PROFILE='checked native ARC/Clang release boundchecks:on LTO; test SDK observer O2; timings discarded'
SOURCE_FIELDS={'observer_source_sha256':'tests/native/storage_io_observer.c',
               'observer_header_sha256':'native/storage_io/observer.h',
               'redirect_sha256':'native/storage_io/redirect.h'}
SOURCES=('tools/storage_growth_io.py','tools/storage_io_observer.py',*SOURCE_FIELDS.values())


def parse_io(output,engine,count,steps,pattern):
    """Bind each exact operation boundary to one real fixture; no speed sample is accepted here."""
    if engine not in ENGINES or (count,steps,pattern) not in CASES or set(IO_ORDER)!=set(PHASES):
        raise ValueError('Unknown SDK storage workload or phase plan')
    expected=[p for p in IO_ORDER if not unavailable(engine,p)]
    rows=[]
    for line in output.splitlines():
        fields=line.split('\t')
        if (len(fields)!=7+len(OPERATIONS) or fields[:6]!=['io',engine,str(count),str(steps),pattern,'0'] or
                len(rows)>=len(expected) or fields[6]!=expected[len(rows)] or
                any(re.fullmatch(r'0|[1-9][0-9]{0,18}',v) is None for v in fields[7:])):
            raise ValueError('Invalid SDK observation identity/order')
        values=list(map(int,fields[7:]));counts=dict(zip(OPERATIONS,values));phase=fields[6]
        if any(v>=(1<<63) for v in values) or counts['ftruncate']!=0:
            raise ValueError('Invalid SDK counts or unexpected recovery truncation')
        resident=phase in ('snapshots','extraction_before','extraction_after','reads_before','reads_after')
        if engine=='memory' or resident:
            if any(values):
                raise ValueError('Resident operation unexpectedly performed observed SDK IO')
        elif phase=='publication':
            if counts['write']<steps or counts['fsync']<steps or counts['renameat'] or counts['unlinkat']:
                raise ValueError('Disk publication lacks synchronized frame witnesses')
        elif phase in ('reopen','retained_reopen','compacted_reopen'):
            if counts['read']==0 or counts['flock']==0 or counts['fsync']<(2 if engine=='journal' else 4) or any(counts[k] for k in ('write','renameat','unlinkat')):
                raise ValueError('Strict reopen lacks read/lease evidence or mutates storage')
        elif phase in ('retention','maintenance'):
            if counts['write']==0 or counts['fsync']==0 or counts['renameat']!=1 or counts['unlinkat']<2:
                raise ValueError('Managed reclamation lacks replacement/retirement witnesses')
        rows.append(dict(backend=engine,items=count,publications=steps,pattern=pattern,sample=0,phase=phase,**counts))
    if len(rows)!=len(expected):
        raise ValueError('Incomplete SDK observation coverage')
    return rows


def validate_io(report):
    """Reparse complete counts and require independent observed-build identity and successful execution."""
    if type(report) is not dict or report.get('status')!='checks-passed' or type(report.get('schema_version')) is not int or report['schema_version']!=1 or report.get('profile')!=PROFILE:
        raise ValueError('Invalid SDK report status/profile')
    for field in (*SOURCE_FIELDS,'observer_object_sha256','native_binary_sha256'):
        if type(report.get(field)) is not str or re.fullmatch('[0-9a-f]{64}',report[field]) is None:
            raise ValueError('Invalid SDK source/object identity')
    checks=report.get('checks')
    if type(checks) is not list or len(checks)!=2+len(ENGINES)*len(CASES):
        raise ValueError('Incomplete SDK execution evidence')
    logs=[]
    for check in checks:
        if type(check) is not dict or type(check.get('exit_code')) is not int or check['exit_code']!=0:
            raise ValueError('Failed SDK native execution')
        duration=check.get('elapsed_seconds');log=check.get('log')
        if type(duration) not in (int,float) or not 0<=duration<=86400 or not math.isfinite(duration) or type(log) is not str or not 0<len(log)<=4096:
            raise ValueError('Invalid SDK execution evidence')
        logs.append(log)
    if len(set(logs))!=len(logs) or report.get('error'):
        raise ValueError('Duplicate or failed SDK execution evidence')
    observations=report.get('observations');expected=[f'{e}-{n}-{s}-{p}' for e in ENGINES for n,s,p in CASES]
    if type(observations) is not dict or list(observations)!=expected:
        raise ValueError('Incomplete SDK backend coverage')
    for engine in ENGINES:
        for count,steps,pattern in CASES:
            rows=observations[f'{engine}-{count}-{steps}-{pattern}']
            if type(rows) is not list:
                raise ValueError('Invalid structured SDK observations')
            for row in rows:
                if type(row) is not dict or set(row)!=set(('backend','items','publications','pattern','sample','phase',*OPERATIONS)) or any(type(row[k]) is not int for k in ('items','publications','sample',*OPERATIONS)):
                    raise ValueError('Invalid structured SDK row')
            encoded=''.join('io\t'+'\t'.join(str(r[k]) for k in ('backend','items','publications','pattern','sample','phase',*OPERATIONS))+'\n' for r in rows)
            if parse_io(encoded,engine,count,steps,pattern)!=rows:
                raise ValueError('Noncanonical structured SDK rows')
    return observations


def calls_csv(report):
    """Export all phase counts independently of any timing statistics or per-call latency samples."""
    observations=validate_io(report);output=io.StringIO(newline='');writer=csv.writer(output)
    fields=('backend','items','publications','pattern','sample','phase',*OPERATIONS)
    writer.writerow(fields)
    for rows in observations.values():
        for row in rows:
            writer.writerow(row[k] for k in fields)
    return output.getvalue()


def summarize_io(report):
    """Keep the job summary compact while raw CSV retains strict-reopen/reclamation boundaries too."""
    observations=validate_io(report)
    lines=['### Independent SDK-call witnesses','','A separate checked observer build emits counts only; its instrumented timings are discarded.',
        'Publication counts per complete trajectory:','',
        '| Entries | Publications | Updates | Backend | write | fsync | read | flock |',
        '| ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for rows in observations.values():
        row=next(r for r in rows if r['phase']=='publication')
        lines.append(f'| {row["items"]} | {row["publications"]} | {row["pattern"]} | {row["backend"]} | '+
            ' | '.join(str(row[k]) for k in ('write','fsync','read','flock'))+' |')
    lines+=['','Resident reads, extraction and snapshot acquisition have zero observed SDK calls for every backend.',
        'Strict reopen requires read/lease/confirmation-sync witnesses and no data or namespace mutation. Managed compaction requires durable replacement and predecessor retirement.',
        'Counts cover eight named SDK call sites, including attempts; they are not device IO, bytes transferred or power-loss certification.',
        'Download `growth/io/calls.csv`, its JSON and logs for every observed phase and source/object identity.']
    return '\n'.join(lines)+'\n'


def run_io(compiler,library,folder,publish):
    """Build the maintained observer separately and collect one fully validated native control per case."""
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    for name in ('results.json','calls.csv'):
        (folder/name).unlink(missing_ok=True)
    report=dict(status='running',schema_version=1,profile=PROFILE,checks=[],observations={})
    def save():
        # Parent head/source/compiler/profile provenance binds this independent counter control to the run.
        publish(folder/'results.json',json.dumps(report,indent=2)+'\n')
    save()
    try:
        observer,prepared=prepare(folder);report['checks'].append(prepared['build'])
        report.update(observer_source_sha256=prepared['source_sha256'],observer_header_sha256=prepared['header_sha256'],
            redirect_sha256=hashlib.sha256((ROOT/SOURCE_FIELDS['redirect_sha256']).read_bytes()).hexdigest(),
            observer_object_sha256=hashlib.sha256(observer.read_bytes()).hexdigest())
        save()
        flags=['-I'+str(ROOT/'native/storage_io'),'-include'+str(ROOT/'native/storage_io/redirect.h'),
            *['-DRAGNAROK_STORAGE_IO_'+op.upper() for op in OPERATIONS]]
        build,binary=NativeChecks(folder).build(compiler,ROOT/'tests/performance/storage_growth_workload.nim',
            'growth-io-native',crypto_library=library,native_libraries=(observer,),cflags=flags,defines=('storageIoCounts',))
        build.pop('output',None);report['checks'].append(build);save()
        if build['exit_code']!=0:
            raise RuntimeError('SDK storage build failed: '+build['log'])
        report['native_binary_sha256']=hashlib.sha256(Path(binary).read_bytes()).hexdigest()
        for engine in ENGINES:
            for count,steps,pattern in CASES:
                with tempfile.TemporaryDirectory(prefix=engine+'-',dir=folder) as owned:
                    evidence=command([binary,engine,count,steps,owned,1,pattern],f'{engine}-{count}-{steps}-{pattern}',folder,timeout=300)
                report['checks'].append(evidence);save()
                if evidence['exit_code']!=0:
                    raise RuntimeError('SDK storage control failed: '+evidence['log'])
                report['observations'][f'{engine}-{count}-{steps}-{pattern}']=parse_io(Path(evidence['log']).read_text(),engine,count,steps,pattern)
                save()
        report['status']='checks-passed'
        publish(folder/'calls.csv',calls_csv(report));save()
        return report
    except Exception as error:
        report.update(status='failed',error=str(error));(folder/'calls.csv').unlink(missing_ok=True)
        save()
        raise
