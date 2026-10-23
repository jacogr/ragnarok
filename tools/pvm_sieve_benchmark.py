#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the frozen real-sieve guest with strict differential state and measurement controls.

Make owns provisioning. No guest compiler is installed and no compiled backend is started.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tomllib
from native_checks import NativeChecks,ROOT
from native_dependencies import require_submodule
from native_fixture_contracts import load_fixture_contracts
from pvm_benchmark import cpu_model
from pvm_sieve_report import ENGINES,LIMITS,parse_output,summarize
from setup_nimony import installed

BUILD=ROOT/'build/tests/pvm-sieve'
CRATE=ROOT/'tests/performance/polkavm'
TARGET=ROOT/'build/pvm-benchmark-rust-target'
FIXTURE=ROOT/'tests/fixtures/pvm-sieve'


def digest(path):
    """Identify immutable source, binary and wire bytes independently of their names."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_fixture(folder=ROOT/'tests/fixtures',upstream=None):
    """Check every declared member, guest provenance and already-pinned host dependencies."""
    _,target,files=load_fixture_contracts(folder)['pvm_sieve']
    for path,expected in files:
        # A directory fixture must pass every member, including its licenses and provenance.
        if digest(path)!=expected:raise ValueError('Changed sieve fixture: '+str(path))
    provenance=json.loads((target/'provenance.json').read_text())
    pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text())
    if provenance['schema']!=1 or provenance['polkavm_commit']!=pins['commit']:
        raise ValueError('Sieve provenance pin mismatch')
    for name,key in (('sieve.polkavm','artifact_sha256'),('checked_entry.rs.inc','checked_entry_sha256'),
                     ('guest-Cargo.lock','guest_lock_sha256')):
        if digest(target/name)!=provenance[key]:raise ValueError('Sieve provenance digest mismatch')
    if upstream is not None:
        # Public reference source and every registry package stay at their pristine existing pins.
        for name,expected in {**pins['source_sha256'],**provenance['upstream_sources']}.items():
            if digest(upstream/name)!=expected:raise ValueError('Changed upstream source: '+name)
        fields=('name','version','source','checksum')
        known={tuple(p.get(k) for k in fields) for p in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
        for package in tomllib.loads((CRATE/'Cargo.lock').read_text())['package']:
            if package['name']!='ragnarok-pvm-benchmark' and tuple(package.get(k) for k in fields) not in known:
                raise ValueError('Unpinned benchmark dependency: '+package['name'])
    return provenance


def run():
    """Build checked engines, reject bad controls, then retain two reversed complete passes."""
    BUILD.mkdir(parents=True,exist_ok=True)
    for name in ('samples.csv','summary.md'):
        # Failed reruns cannot expose a downloadable earlier success.
        (BUILD/name).unlink(missing_ok=True)
    report=dict(status='running',checks=[],passes=[])
    checks=NativeChecks(BUILD)

    def save():
        """Persist partial evidence as it becomes available, including failed runs."""
        (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')

    def command(arguments,name,environment=None,failure=None):
        """Retain strict process status and diagnostics; negative controls require real failures."""
        row=checks.command(arguments,name,environment=environment,timeout=900)
        output=row.pop('output');report['checks'].append(row);save()
        if failure is None:
            if row['exit_code']!=0:raise RuntimeError(name+' failed: '+row['log'])
        elif row['exit_code']==0 or (failure and failure not in output):
            raise RuntimeError(name+' failed to reject its negative control')
        return output

    save()
    try:
        pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        provenance=verify_fixture(upstream=require_submodule(pins))
        compiler,_=installed();rust=json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        sources=[*sorted((ROOT/'src/pvm').glob('*.nim')),*sorted(CRATE.glob('src/*.rs')),
                 CRATE/'Cargo.toml',CRATE/'Cargo.lock',ROOT/'spec/toolchain.json',ROOT/'Makefile',
                 ROOT/'tools/pvm_sieve_benchmark.py',ROOT/'tools/pvm_sieve_report.py',
                 ROOT/'tests/performance/pvm_sieve.nim',ROOT/'tests/performance/pvm_sieve_clock.h']
        report.update(provenance=provenance,sources={str(p.relative_to(ROOT)):digest(p) for p in sources},
            head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
            hardware=dict(platform=__import__('platform').platform(),cpu=cpu_model(),logical_cpus=os.cpu_count(),
                          load_average_start=os.getloadavg()),
            toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            rustc=subprocess.check_output(['rustup','run',rust,'rustc','--version','--verbose'],text=True).strip(),
            nimony=subprocess.check_output([str(compiler),'--version'],text=True).strip(),
            clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0],
            build_environment={key:os.environ[key] for key in ('RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','CFLAGS','LDFLAGS') if key in os.environ},
            warmups_per_pass=3,measured_samples_per_pass=10,pass_count=2,
            profile='checked release ARC/Clang ThinLTO; PolkaVM Interpreter JamV1 Sync/Full/L2Hit')
        build,binary=checks.build(compiler,ROOT/'tests/performance/pvm_sieve.nim','native',
                                  cflags=('-I'+str(ROOT/'tests/performance'),))
        output=build.pop('output');report['checks'].append(build);save()
        if build['exit_code']!=0 or 'Error:' in output or 'FAILURE' in output:
            raise RuntimeError('Native sieve build failed: '+build['log'])
        command(['rustup','run',rust,'cargo','build','--release','--locked','--offline',
                 '--manifest-path',CRATE/'Cargo.toml','--target-dir',TARGET],'rust-build')
        reference=TARGET/'release/ragnarok-pvm-benchmark'
        report['binaries']={str(p.relative_to(ROOT)):digest(p) for p in (binary,reference)}
        for limit in LIMITS:
            # Reference preparation is untimed and freezes the same initial/final state for both engines.
            folder=BUILD/str(limit);folder.mkdir(exist_ok=True)
            prepared=command([reference,'--sieve-prepare',FIXTURE/'sieve.polkavm',folder,limit,1],f'prepare-{limit}')
            if not prepared.startswith('SIEVE_PREPARED,'+str(limit)+','):
                raise ValueError('Invalid reference preparation output')
            data=folder/f'input-{limit}.bin';expected=folder/f'expected-{limit}.bin'
            immutable={path:digest(path) for path in (data,expected)}
            environment=dict(os.environ,RAGNAROK_PVM_SIEVE_INPUT=str(data),
                             RAGNAROK_PVM_SIEVE_EXPECTED=str(expected),RAGNAROK_PVM_SIEVE_SAMPLES='13')
            arguments={'ragnarok':[binary],'polkavm_interpreter':
                       [reference,'--sieve',FIXTURE/'sieve.polkavm',folder,limit,13]}
            for engine in ENGINES:
                # Release assertions must remain live in both executables.
                probe=dict(environment,RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1')
                sentinel='pvm sieve '+('native' if engine=='ragnarok' else 'reference')+' assertion control'
                command(arguments[engine],f'assert-{limit}-{engine}',probe,sentinel)
            for name,path,changed in (('truncated',data,data.read_bytes()[:-1]),
                                      ('tampered',expected,expected.read_bytes()[:16]+bytes([expected.read_bytes()[16]^1])+expected.read_bytes()[17:])):
                original=path.read_bytes()
                try:
                    path.write_bytes(changed)
                    for engine in ENGINES:
                        # Both measured runners must reject bad data rather than regenerate expected bytes.
                        command(arguments[engine],f'{name}-{limit}-{engine}',environment,'')
                finally:
                    path.write_bytes(original)
            for pass_index,order in enumerate((ENGINES,tuple(reversed(ENGINES)))):
                for engine in order:
                    for path,identity in immutable.items():
                        if digest(path)!=identity:raise ValueError('Changed prepared sieve input')
                    samples=parse_output(command(arguments[engine],f'pass{pass_index}-{limit}-{engine}',environment),engine,limit)
                    for path,identity in immutable.items():
                        if digest(path)!=identity:raise ValueError('Sieve runner changed frozen data')
                    report['passes'].append(dict(limit=limit,engine=engine,pass_index=pass_index,
                        inputs={str(p.relative_to(ROOT)):sha for p,sha in immutable.items()},samples=samples));save()
        report['status']='checks-passed';report['hardware']['load_average_end']=os.getloadavg()
        text=summarize(report)
        with (BUILD/'samples.csv').open('w',newline='') as output:
            writer=csv.writer(output);writer.writerow(('limit','engine','pass','sample','warmup','wall_ns','cpu_ns'))
            for item in report['passes']:
                for row in item['samples']:
                    writer.writerow((item['limit'],item['engine'],item['pass_index'],row['sample'],row['sample']<3,row['wall_ns'],row['cpu_ns']))
        print(text)
    except Exception as error:
        # Partial successful timings never constitute a successful comparison.
        report.update(status='failed',error=str(error));(BUILD/'samples.csv').unlink(missing_ok=True);raise
    finally:
        save();(BUILD/'summary.md').write_text(summarize(report))


if __name__=='__main__':
    # Import remains safe for unit tests and tooling discovery.
    run()
