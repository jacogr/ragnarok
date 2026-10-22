# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Execute the sustained panel as part of Perf Storage, preserving failure and raw evidence."""
import csv
import hashlib
import io
import json
from pathlib import Path
import tempfile
from native_checks import NativeChecks
from pvm_reference import command
from storage_growth_report import ENGINES,CASES,PHASES,METRICS,parse_growth,aggregate_growth,validate_growth

ROOT=Path(__file__).resolve().parents[1]
SOURCES=('tests/performance/storage_growth_workload.nim','tests/support/storage_growth_samples.nim',
         'tools/storage_growth.py','tools/storage_growth_report.py')


def growth_csv(report):
    """Serialize only complete validated observations; warmups remain visible but excluded from statistics."""
    validate_growth(report)
    output=io.StringIO(newline='');writer=csv.writer(output)
    writer.writerow(('pass','backend','items','publications','pattern','sample','warmup',*[p+'_ns' for p in PHASES],*METRICS))
    for index,observations in enumerate(report['passes']):
        for name,rows in observations.items():
            engine=name.split('-')[0]
            for row in rows:
                writer.writerow((index,engine,row['items'],row['publications'],row['pattern'],row['sample'],row['sample']<3,
                    *[row[k] for k in (*PHASES,*METRICS)]))
    return output.getvalue()


def publication_csv(report):
    """Retain every ordered call duration with its case/sample/warmup identity for independent analysis."""
    validate_growth(report)
    output=io.StringIO(newline='');writer=csv.writer(output)
    writer.writerow(('pass','backend','items','publications','pattern','sample','warmup','revision','latency_ns'))
    for index,observations in enumerate(report['passes']):
        for name,rows in observations.items():
            for row in rows:
                for revision,duration in enumerate(row['publication_samples'],1):
                    writer.writerow((index,name.split('-')[0],row['items'],row['publications'],row['pattern'],
                        row['sample'],row['sample']<3,revision,duration))
    return output.getvalue()


def run_growth(compiler,library,folder,publish):
    """Build once, run matching reversed-order cases, and publish success after complete raw artifacts."""
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    for name in ('results.json','samples.csv','publications.csv'):
        (folder/name).unlink(missing_ok=True)
    report=dict(status='running',schema_version=7,checks=[],passes=[],cases=[])
    def save():
        # Parent source/profile/toolchain provenance covers this panel and all SOURCES explicitly.
        publish(folder/'results.json',json.dumps(report,indent=2)+'\n')
    save()
    try:
        build,binary=NativeChecks(folder).build(compiler,ROOT/SOURCES[0],'growth-native',crypto_library=library)
        build.pop('output',None);report['checks'].append(build);save()
        if build['exit_code']!=0:
            raise RuntimeError('Sustained storage build failed: '+build['log'])
        report['native_binary_sha256']=hashlib.sha256(Path(binary).read_bytes()).hexdigest()
        for order in (ENGINES,tuple(reversed(ENGINES))):
            observations={}
            for engine in order:
                for count,steps,pattern in CASES:
                    with tempfile.TemporaryDirectory(prefix=engine+'-',dir=folder) as owned:
                        evidence=command([binary,engine,count,steps,owned,13,pattern],
                            f'pass{len(report["passes"])}-{engine}-{count}-{steps}-{pattern}',folder,timeout=300)
                    report['checks'].append(evidence);save()
                    if evidence['exit_code']!=0:
                        raise RuntimeError('Sustained storage workload failed: '+evidence['log'])
                    observations[f'{engine}-{count}-{steps}-{pattern}']=parse_growth(Path(evidence['log']).read_text(),engine,count,steps,pattern)
            report['passes'].append(observations);save()
        report['cases']=aggregate_growth(report['passes']);report['status']='checks-passed'
        publish(folder/'samples.csv',growth_csv(report))
        publish(folder/'publications.csv',publication_csv(report))
        save() # A successful child report follows a complete raw CSV; the parent still owns overall success.
        return report
    except Exception as error:
        report.update(status='failed',error=str(error))
        for name in ('samples.csv','publications.csv'):
            (folder/name).unlink(missing_ok=True)
        save()
        raise
