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
from build_crypto import dependencies as crypto_sources, build_native as build_crypto
from pvm_reference import command
from setup_nimony import installed
from storage_benchmark_report import ENGINES,COUNTS,TOPOLOGIES,VALUE_BYTES,CASES,PHASES,METRICS,parse_output,aggregate,summarize_benchmark

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/tests/storage-benchmark'


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
    for name in ('summary.md','samples.csv'):
        (BUILD/name).unlink(missing_ok=True)
    report=dict(status='running',checks=[],passes=[],cases=[])
    def save():
        # Full raw samples and source/toolchain identities stay downloadable independently of Markdown.
        (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        compiler,_=installed()
        source=ROOT/'tests/performance/storage_workload.nim'
        sources=[*sorted((ROOT/'src').rglob('*.nim')),source,
            ROOT/'tests/support/managed_storage_samples.nim',ROOT/'tests/support/storage_samples.nim',
            ROOT/'tools/storage_benchmark.py',ROOT/'tools/storage_benchmark_report.py',
            ROOT/'tools/native_checks.py',ROOT/'tools/pvm_reference.py',ROOT/'spec/toolchain.json',
            ROOT/'Makefile',ROOT/'.github/workflows/ci.yml']
        # Build the pinned ABI before hashing/linking it; setup provisions sources, not compiled libraries.
        library=build_crypto(crypto_sources(False))
        report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
            hardware=dict(platform=platform.platform(),machine=platform.machine(),cpu=cpu_model(),logical_cpus=os.cpu_count(),
                          load_average_start=os.getloadavg()),
            toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0],
            profile='checked native ARC/Clang release opt:speed boundchecks:on LTO',
            sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
            crypto_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
            schema_version=8,value_sizes=list(VALUE_BYTES),key_topologies=list(TOPOLOGIES),warmups_per_pass=3,measured_samples_per_pass=10,pass_count=2,
            pass_orders=[list(ENGINES),list(reversed(ENGINES))])
        save()
        build,binary=NativeChecks(BUILD).build(compiler,source,'storage-native',crypto_library=library)
        build.pop('output',None);report['checks'].append(build);save()
        if build['exit_code']!=0:
            raise RuntimeError('Storage benchmark build failed: '+build['log'])
        for order in (ENGINES,tuple(reversed(ENGINES))):
            observations={}
            for engine in order:
                for count,topology,value_bytes in CASES:
                    with tempfile.TemporaryDirectory(prefix=engine+'-'+topology+'-',dir=BUILD) as folder:
                        evidence=command([binary,engine,count,folder,topology,value_bytes],f'pass{len(report["passes"])}-{engine}-{count}-{topology}-{value_bytes}',BUILD,timeout=300)
                    report['checks'].append(evidence);save()
                    if evidence['exit_code']!=0:
                        raise RuntimeError('Storage workload failed: '+evidence['log'])
                    observations[f'{engine}-{count}-{topology}-{value_bytes}']=parse_output(Path(evidence['log']).read_text(),engine,count,topology,value_bytes)
            report['passes'].append(observations);save()
        report['cases']=aggregate(report['passes']);report['status']='checks-passed'
        report['hardware']['load_average_end']=os.getloadavg();save()
        with (BUILD/'samples.csv').open('w',newline='') as output:
            writer=csv.writer(output);writer.writerow(('pass','backend','items','key_topology','value_bytes','sample','warmup',*[phase+'_ns' for phase in PHASES],*METRICS))
            for p,observations in enumerate(report['passes']):
                for engine in ENGINES:
                    for count,topology,value_bytes in CASES:
                        for row in observations[f'{engine}-{count}-{topology}-{value_bytes}']:
                            writer.writerow((p,engine,count,topology,value_bytes,row['sample'],row['sample']<3,*[row[k] for k in (*PHASES,*METRICS)]))
        print(summarize_benchmark(report))
    except Exception as error:
        # Native assertions, IO refusal, malformed observations and setup errors are real job failures.
        report.update(status='failed',error=str(error));raise
    finally:
        save()
        (BUILD/'summary.md').write_text(summarize_benchmark(report))


# Imports expose inert orchestration for tests; Make alone owns provisioning and execution sequencing.
if __name__=='__main__':
    run()
