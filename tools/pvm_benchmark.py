#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run opt-in correctness-validated PVM speed baselines with explicit backend availability."""
import csv
from pvm_benchmark_report import native_pricing_mode
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tomllib
from native_checks import NativeChecks
from native_dependencies import ROOT,require_submodule
from pvm_reference import command
from pvm_benchmark_report import ACTIVE_ENGINES,DEFERRED_COMPILER,NAMES,parse_output,aggregate,summarize_benchmark
from setup_nimony import installed

BUILD=ROOT/'build/tests/pvm-benchmark'
CRATE=ROOT/'tests/performance/polkavm'
TARGET=ROOT/'build/pvm-benchmark-rust-target'


# Retain exact source/input identities even for an uncommitted local measurement tree.
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Record CPU model without collecting hostname, network state or unrelated environment variables.
def cpu_model():
    if platform.system()=='Darwin':
        return subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    if Path('/proc/cpuinfo').is_file():
        for line in Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name'):return line.split(':',1)[1].strip()
    return platform.machine()


# Setup owns builds; every observed duration is emitted only after that execution validates fully.
def run():
    BUILD.mkdir(parents=True,exist_ok=True)
    # A new failed run must not expose an earlier downloadable success or old sample file.
    (BUILD/'summary.md').unlink(missing_ok=True)
    (BUILD/'samples.csv').unlink(missing_ok=True)
    report=dict(status='running',checks=[],passes=[],cases=[])
    result=BUILD/'results.json'

    # Persist partial progress so a failed backend cannot leave an earlier green comparison table.
    def save():
        result.write_text(json.dumps(report,indent=2)+'\n')

    # Preserve strict command status and complete logs, including timeout process-group cleanup.
    def checked(arguments,name,timeout=900,environment=None):
        if environment is None:
            evidence=command(arguments,name,BUILD,timeout)
        else:
            # Measured interpreter processes spawn no children; retain their explicit native policy selection.
            evidence=NativeChecks(BUILD).command(arguments,name,environment=environment,timeout=timeout)
            evidence.pop('output',None)
            evidence['benchmark_environment']={key:environment[key] for key in ('RAGNAROK_PVM_BENCHMARK','RAGNAROK_PVM_PRICING') if key in environment}
        report['checks'].append(evidence);save()
        if evidence['exit_code']!=0:raise RuntimeError(name+' failed; see '+evidence['log'])
        return Path(evidence['log']).read_text()

    save()
    try:
        pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text());upstream=require_submodule(pins)
        gray=json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
        require_submodule(dict(gray,repository=gray['repository'].removeprefix('https://github.com/')))
        for name,expected in pins['source_sha256'].items():
            if digest(upstream/name)!=expected:raise ValueError('Changed pinned reference source: '+name)
        fields=('name','version','source','checksum')
        known={tuple(p.get(k) for k in fields) for p in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
        for package in tomllib.loads((CRATE/'Cargo.lock').read_text())['package']:
            if package['name']!='ragnarok-pvm-benchmark' and tuple(package.get(k) for k in fields) not in known:
                raise ValueError('Unpinned benchmark dependency: '+package['name'])
        sys.path.insert(0,str(ROOT/'tests'))
        from pvm_benchmark_reference import fixtures
        fixture=ROOT/'tests/fixtures/pvm-benchmark.bin';expected,count=fixtures()
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_benchmark.fixture.json').read_text())
        if (fixture.read_bytes()!=expected or count!=len(NAMES)
                or digest(fixture)!=descriptor['files'][fixture.name]):
            raise ValueError('Benchmark inputs differ from independent expectations')
        compiler,_=installed();rust=json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        sources=[*sorted((ROOT/'src').rglob('*.nim')),ROOT/'tests/performance/pvm_workload.nim',
                 *sorted((CRATE/'src').rglob('*.rs')),CRATE/'Cargo.toml',CRATE/'Cargo.lock',
                 ROOT/'tools/pvm_benchmark.py',ROOT/'tools/pvm_benchmark_report.py',ROOT/'tests/pvm_benchmark_reference.py',
                 ROOT/'tests/pvm_gas_reference.py',ROOT/'spec/toolchain.json',ROOT/'Makefile',ROOT/'.github/workflows/ci.yml']
        report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
            hardware=dict(platform=platform.platform(),cpu=cpu_model(),logical_cpus=os.cpu_count(),
                          load_average_start=os.getloadavg()),
            rust=rust,rustc=subprocess.check_output(['rustup','run',rust,'rustc','--version','--verbose'],text=True).strip(),
            nimony_toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            build_environment={key:os.environ[key] for key in ('RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','CFLAGS','LDFLAGS') if key in os.environ},
            nimony=subprocess.check_output([str(compiler),'--version'],text=True).strip(),
            clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0],
            polkavm=pins['commit'],graypaper=gray['commit'],fixture_sha256=digest(fixture),
            sources={str(p.relative_to(ROOT)):digest(p) for p in sources},warmups_per_pass=3,
            measured_samples_per_pass=10,pass_count=2,
            pass_orders=[list(ACTIVE_ENGINES),list(reversed(ACTIVE_ENGINES))],
            compiled_comparison='deferred by maintainer; no compiler process is started',
            profile='checked release ARC/Clang LTO; pinned upstream Rust release LTO/codegen-units1/debug; JamV1 Sync/Full/L2Hit')
        save()
        native_folder=ROOT/'build/pvm-benchmark';native_folder.mkdir(exist_ok=True)
        build,binary=NativeChecks(native_folder).build(compiler,ROOT/'tests/performance/pvm_workload.nim','native')
        build_output=build.pop('output','');report['checks'].append(build);save()
        if build['exit_code']!=0 or 'Error:' in build_output or 'FAILURE' in build_output:
            raise RuntimeError('Native benchmark build failed: '+build['log'])
        memo_build,memo_binary=NativeChecks(native_folder).build(compiler,ROOT/'tests/performance/pvm_workload.nim','native-memo',defines=('pvmBenchmarkMemo',))
        memo_output=memo_build.pop('output','');report['checks'].append(memo_build);save()
        if memo_build['exit_code']!=0 or 'Error:' in memo_output or 'FAILURE' in memo_output:
            raise RuntimeError('Native memo benchmark build failed: '+memo_build['log'])
        checked(['rustup','run',rust,'cargo','build','--release','--locked','--offline',
            '--manifest-path',CRATE/'Cargo.toml','--target-dir',TARGET],'rust-build')
        report['binaries']={str(p.relative_to(ROOT)):digest(p) for p in (binary,memo_binary,TARGET/'release/ragnarok-pvm-benchmark')}
        arguments={'ragnarok':[binary],'ragnarok_planned':[binary],'ragnarok_memo':[memo_binary],
                   'polkavm_interpreter':[TARGET/'release/ragnarok-pvm-benchmark',fixture,'interpreter']}
        for probe_binary,mode,sentinel in ((binary,'memo','legacy'),(memo_binary,'dynamic','memo')):
            # Separate instantiations must reject wrong labels before emitting any measurement.
            probe=NativeChecks(BUILD).command([probe_binary],'mode-control-'+sentinel,
                environment=dict(os.environ,RAGNAROK_PVM_BENCHMARK=str(fixture),RAGNAROK_PVM_PRICING=mode))
            output=probe.pop('output','');report['checks'].append(probe);save()
            if probe['exit_code']==0 or 'pvm benchmark '+sentinel+' mode mismatch' not in output:
                raise RuntimeError('Native benchmark mode control did not fail')
        os.environ['RAGNAROK_PVM_BENCHMARK']=str(fixture)
        for pass_index,order in enumerate((ACTIVE_ENGINES,tuple(reversed(ACTIVE_ENGINES)))):
            # Reversing engine order limits simple first/last bias; it does not claim host isolation.
            # Deferral is policy metadata, never a backend probe or substituted interpreter sample.
            observations={'polkavm_compiler':[dict(samples=[],reason=DEFERRED_COMPILER,deferred=True) for _ in NAMES]}
            for engine in order:
                mode=dict(os.environ,RAGNAROK_PVM_BENCHMARK=str(fixture),RAGNAROK_PVM_PRICING=native_pricing_mode(engine))
                output=checked(arguments[engine],f'pass{pass_index}-{engine}',timeout=300,environment=mode)
                observations[engine]=parse_output(output,engine)
            report['passes'].append(observations);save()
        report['cases']=aggregate(report['passes']);report['status']='checks-passed'
        report['hardware']['load_average_end']=os.getloadavg();save()
        with (BUILD/'samples.csv').open('w',newline='') as output:
            writer=csv.writer(output);writer.writerow(('workload','engine','pass','sample','warmup','execution_ns','prepare_once_ns'))
            for case in report['cases']:
                for engine,item in case['engines'].items():
                    for sample in item.get('samples',[]):
                        writer.writerow((case['name'],engine,sample['pass_index'],sample['sample'],
                            sample['sample']<3,sample['execution_ns'],sample['prepare_once_ns']))
        text=summarize_benchmark(report);(BUILD/'summary.md').write_text(text);print(text)
    except Exception as error:
        # Source, correctness, malformed samples or backend execution errors make the entire run fail.
        report.update(status='failed',error=str(error));raise
    finally:
        save()
        (BUILD/'summary.md').write_text(summarize_benchmark(report))


# Importing the benchmark command never provisions dependencies or starts measurements.
if __name__=='__main__':
    run()
