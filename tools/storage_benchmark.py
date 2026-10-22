#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build and execute bounded, validated memory versus durable storage benchmarks."""
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
from native_checks import NativeChecks
from storage_growth import run_growth, SOURCES as GROWTH_SOURCES
from build_crypto import dependencies as crypto_sources, build_native as build_crypto
from pvm_reference import command
from setup_nimony import installed
from storage_benchmark_report import ENGINES,COUNTS,TOPOLOGIES,VALUE_BYTES,BATCH_WIDTHS,CASES,PHASES,METRICS,REPORT_VERSION,PROFILE,parse_output,aggregate,summarize_benchmark

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/tests/storage-benchmark'


# Replace a complete artifact only after its private temporary file closes successfully.
def atomic_text(path,value):
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,
                prefix='.'+path.name+'-',suffix='.tmp',delete=False) as output:
            temporary=Path(output.name)
            output.write(value)
        os.replace(temporary,path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


# A failed CSV write cannot publish a partial final artifact or a successful verification status.
def write_samples(report):
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(mode='w',newline='',dir=BUILD,
            prefix='.samples-',suffix='.tmp',delete=False) as output:
            temporary=Path(output.name)
            writer=csv.writer(output);writer.writerow(('pass','backend','items','key_topology','value_bytes','batch_width','sample','warmup',*[phase+'_ns' for phase in PHASES],*METRICS))
            for p,observations in enumerate(report['passes']):
                for engine in ENGINES:
                    for count,topology,value_bytes,batch_width in CASES:
                        for row in observations[f'{engine}-{count}-{topology}-{value_bytes}-{batch_width}']:
                            writer.writerow((p,engine,count,topology,value_bytes,batch_width,row['sample'],row['sample']<3,*[row[k] for k in (*PHASES,*METRICS)]))
        os.replace(temporary,BUILD/'samples.csv')
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


# Record the CPU model without hostnames, network state or unrelated environment variables.
def cpu_model():
    if platform.system()=='Darwin':
        return subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    info=Path('/proc/cpuinfo')
    if info.is_file():
        for line in info.read_text().splitlines():
            if line.startswith('model name'):
                return line.split(':',1)[1].strip()
    return platform.machine()


# Persist progress and failures before rendering any comparison; older success cannot survive a failed rerun.
def run():
    BUILD.mkdir(parents=True,exist_ok=True)
    for name in ('summary.md','samples.csv','results.json','growth/results.json','growth/samples.csv','growth/publications.csv'):
        (BUILD/name).unlink(missing_ok=True)
    report=dict(status='running',checks=[],passes=[],cases=[])
    def save():
        # Full raw samples and source/toolchain identities stay downloadable independently of Markdown.
        atomic_text(BUILD/'results.json',json.dumps(report,indent=2)+'\n')
    save()
    try:
        compiler,_=installed()
        source=ROOT/'tests/performance/storage_workload.nim'
        sources=[*[ROOT/name for name in GROWTH_SOURCES],*sorted((ROOT/'src').rglob('*.nim')),source,
            ROOT/'tests/support/managed_storage_samples.nim',ROOT/'tests/support/storage_samples.nim',
            ROOT/'tools/storage_benchmark.py',ROOT/'tools/storage_benchmark_report.py',
            ROOT/'tools/native_checks.py',ROOT/'tools/pvm_reference.py',ROOT/'spec/toolchain.json',
            ROOT/'Makefile',ROOT/'.github/workflows/ci.yml',ROOT/'tools/build_crypto.py',
            ROOT/'tools/native_source_identity.py',ROOT/'spec/crypto-pins.json']
        # Build the pinned ABI before hashing/linking it; setup provisions sources, not compiled libraries.
        library=build_crypto(crypto_sources(False))
        report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
            hardware=dict(platform=platform.platform(),machine=platform.machine(),cpu=cpu_model(),logical_cpus=os.cpu_count(),
                          load_average_start=os.getloadavg()),
            toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0],
            profile=PROFILE,
            sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
            crypto_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
            compiler_sha256=hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
            schema_version=REPORT_VERSION,backends=list(ENGINES),item_counts=list(COUNTS),
            phase_names=list(PHASES),physical_metrics=list(METRICS),batch_widths=list(BATCH_WIDTHS),value_sizes=list(VALUE_BYTES),key_topologies=list(TOPOLOGIES),warmups_per_pass=3,measured_samples_per_pass=10,pass_count=2,
            pass_orders=[list(ENGINES),list(reversed(ENGINES))])
        save()
        build,binary=NativeChecks(BUILD).build(compiler,source,'storage-native',crypto_library=library)
        build.pop('output',None);report['checks'].append(build);save()
        if build['exit_code']!=0:
            raise RuntimeError('Storage benchmark build failed: '+build['log'])
        report['native_binary_sha256']=hashlib.sha256(Path(binary).read_bytes()).hexdigest()
        for order in (ENGINES,tuple(reversed(ENGINES))):
            observations={}
            for engine in order:
                for count,topology,value_bytes,batch_width in CASES:
                    with tempfile.TemporaryDirectory(prefix=engine+'-'+topology+'-',dir=BUILD) as folder:
                        evidence=command([binary,engine,count,folder,topology,value_bytes,batch_width],f'pass{len(report["passes"])}-{engine}-{count}-{topology}-{value_bytes}-{batch_width}',BUILD,timeout=300)
                    report['checks'].append(evidence);save()
                    if evidence['exit_code']!=0:
                        raise RuntimeError('Storage workload failed: '+evidence['log'])
                    observations[f'{engine}-{count}-{topology}-{value_bytes}-{batch_width}']=parse_output(Path(evidence['log']).read_text(),engine,count,topology,value_bytes,batch_width)
            report['passes'].append(observations);save()
        report['growth']=run_growth(compiler,library,BUILD/'growth',atomic_text)
        report['cases']=aggregate(report['passes']);report['status']='checks-passed'
        report['hardware']['load_average_end']=os.getloadavg()
        write_samples(report)
        summary=summarize_benchmark(report)
        atomic_text(BUILD/'summary.md',summary)
        print(summary)
    except Exception as error:
        # Native assertions, IO refusal, malformed observations and setup errors are real job failures.
        report.update(status='failed',error=str(error));raise
    finally:
        if report['status']!='checks-passed':
            (BUILD/'samples.csv').unlink(missing_ok=True)
            atomic_text(BUILD/'summary.md',summarize_benchmark(report))
        save() # Final success follows complete CSV and validated Markdown.


# Imports expose inert orchestration for tests; Make alone owns provisioning and execution sequencing.
if __name__=='__main__':
    run()
