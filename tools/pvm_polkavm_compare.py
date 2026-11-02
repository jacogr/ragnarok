#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Opt-in Linux x86-64 PolkaVM compiler/interpreter calibration on all PVM samples."""
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tomllib

from native_checks import NativeChecks, ROOT
from native_dependencies import require_submodule
from native_fixture_contracts import load_fixture_contracts
from pvm_benchmark import cpu_model
from pvm_benchmark_report import NAMES
from pvm_sieve_benchmark import verify_fixture
from pvm_sieve_report import limits_for_guest
from pvm_polkavm_report import parse, summarize, parse_clock_control

BUILD=ROOT/'build/tests/pvm-polkavm-ratios'
RUST=json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']


def digest(path):
    """Bind all prepared inputs, programs, runtime sources and measured images to actual bytes."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run():
    """Prepare once with interpretation; compare both explicit engines on identical checked state."""
    BUILD.mkdir(parents=True,exist_ok=True)
    for name in ('summary.md','samples.csv'): (BUILD/name).unlink(missing_ok=True)
    result=BUILD/'results.json'
    # Clear the machine-readable verdict before platform or argument validation can fail.
    result.write_text(json.dumps(dict(status='running'))+'\n')
    try:
        if platform.system()!='Linux' or platform.machine() not in ('x86_64','AMD64'):
            raise RuntimeError('PolkaVM native calibration requires native Linux x86-64')
        pairs=int(os.environ.get('PVM_POLKAVM_PAIRS','6'))
        if pairs not in (2,6):raise ValueError('calibration uses two pilot or six qualification pairs')
    except Exception as error:
        result.write_text(json.dumps(dict(status='failed',error=str(error)))+'\n')
        raise
    checks=NativeChecks(BUILD)
    report=dict(status='running',cpu_counter='Linux perf task-clock; one thread per process, including kernel time',pairs=pairs,runs=[],controls=[],checks=[],identities={},
        hardware=dict(platform=platform.platform(),cpu=cpu_model(),logical_cpus=os.cpu_count(),
                      affinity=sorted(os.sched_getaffinity(0)),load_start=os.getloadavg(),
                      linux_sysctls={name:(Path('/proc/sys')/name.replace('.','/')).read_text().strip()
                          if (Path('/proc/sys')/name.replace('.','/')).is_file() else None
                          for name in ('kernel.perf_event_paranoid','kernel.apparmor_restrict_unprivileged_userns',
                                       'vm.unprivileged_userfaultfd')}),
        scope='Warm execution includes parent and active sandbox process CPU, in-memory hosts; setup, restoration, verification and teardown excluded.',
        preparation_scope='Module compilation/setup parent CPU retained separately; synthetic setup also includes Engine construction. Instance creation excluded.',
        profile='Pinned PolkaVM JamV1, Sync gas, Full/L2Hit, 4096-byte pages, Rust release LTO/codegen-units1; default Linux compiler sandbox.',
        portable_estimate='ARM comparison / x86 PolkaVM native-per-interpreted; assumes per-workload backend ratio transfers across architectures. Not an ARM native measurement.')
    result=BUILD/'results.json'
    def save():result.write_text(json.dumps(report,indent=2)+'\n')
    def command(args,name,env=None,fail=False,timeout=900):
        evidence=checks.command(args,name,environment=env,timeout=timeout)
        output=evidence.pop('output');report['checks'].append(evidence);save()
        if (evidence['exit_code']==0)==fail:raise RuntimeError(name+' unexpected exit; see '+evidence['log'])
        return output,evidence
    def environment(backend=None,**values):
        env=dict(os.environ)
        for key in ('RAGNAROK_PVM_REFERENCE_BACKEND','RAGNAROK_PVM_CLOCK_CONTROL',
                    'RAGNAROK_PVM_SIEVE_ASSERT_PROBE','RAGNAROK_PVM_DOOM_ASSERT',
                    'RAGNAROK_PVM_DOOM_LIFECYCLE'):
            env.pop(key,None)
        if backend:env['RAGNAROK_PVM_REFERENCE_BACKEND']=backend
        env.update(values)
        return env
    save()
    try:
        pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text());upstream=require_submodule(pins)
        for name,expected in pins['source_sha256'].items():
            if digest(upstream/name)!=expected:raise ValueError('changed PolkaVM pin source')
        report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                      polkavm=pins['commit'],rust=RUST,
                      rustc=subprocess.check_output(['rustup','run',RUST,'rustc','--version','--verbose'],text=True),
                      flags={k:os.environ[k] for k in ('RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS') if k in os.environ})
        contracts=load_fixture_contracts(ROOT/'tests/fixtures')
        for guest in ('sieve','minimal','memset','pinky'):verify_fixture(upstream=upstream,guest=guest)
        binaries={}
        known={tuple(p.get(k) for k in ('name','version','source','checksum'))
               for p in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
        for crate,binary in (('polkavm','ragnarok-pvm-benchmark'),('polkavm_doom','ragnarok-pvm-doom')):
            path=ROOT/'tests/performance'/crate
            for package in tomllib.loads((path/'Cargo.lock').read_text())['package']:
                if package['name']!=binary and tuple(package.get(k) for k in ('name','version','source','checksum')) not in known:
                    raise ValueError('unpinned reference dependency')
            target=BUILD/(crate+'-target')
            command(['rustup','run',RUST,'cargo','build','--release','--locked','--offline',
                     '--manifest-path',path/'Cargo.toml','--target-dir',target],crate+'-build')
            binaries[crate]=target/'release'/binary
        identities=[ROOT/'tests/performance/polkavm_backend.rs',ROOT/'spec/polkavm-pins.json',
                    ROOT/'spec/bandersnatch-pins.json',ROOT/'Makefile',ROOT/'.github/workflows/ci.yml',
                    ROOT/'tools/pvm_polkavm_compare.py',ROOT/'tools/pvm_polkavm_report.py',*binaries.values()]
        for crate in binaries:
            path=ROOT/'tests/performance'/crate
            identities += [*path.glob('src/*.rs'),path/'Cargo.toml',path/'Cargo.lock']
        for key in ('pvm_guests','pvm_pinky','pvm_sieve'):
            identities += [path for path,_ in contracts[key][2]]
        fixture=ROOT/'tests/fixtures/pvm-benchmark.bin'
        sys_path=__import__('sys').path;sys_path.insert(0,str(ROOT/'tests'))
        from pvm_benchmark_reference import fixtures
        expected,count=fixtures()
        if fixture.read_bytes()!=expected or count!=len(NAMES):raise ValueError('changed synthetic fixtures')
        identities.append(fixture)
        # A real busy child must dominate the measured CPU while its parent waits.
        control,_=command([binaries['polkavm']],'worker-clock-control',
                          environment(RAGNAROK_PVM_CLOCK_CONTROL='parent'),timeout=30)
        report['controls'].append(dict(kind='worker_cpu',**parse_clock_control(control)))
        rejected,_=command([binaries['polkavm']],'threaded-clock-refused',
            environment(RAGNAROK_PVM_CLOCK_CONTROL='threaded'),fail=True,timeout=30)
        if 'task-clock measurement requires one runtime thread' not in rejected or 'REFERENCE_CPU,' in rejected:
            raise ValueError('multi-thread CPU omission was not refused')
        report['controls'].append(dict(kind='single_thread_required',rejected=True))
        # Exercise every required compiler profile before the application timing cohort.
        available,_=command([binaries['polkavm'],fixture,'compiler'],'synthetic-profiles-available',
            environment('compiler'))
        profiles=parse(available,'compiler','synthetic')
        report['controls'].append(dict(kind='synthetic_profiles_available',backend='compiler',cases=profiles))
        workloads=[dict(family='synthetic',limit=0,args=[binaries['polkavm'],fixture],env={})]
        for guest in ('sieve','minimal','memset','pinky'):
            family={'sieve':'pvm_sieve','pinky':'pvm_pinky'}.get(guest,'pvm_guests')
            artifact=contracts[family][1]/(guest+'.polkavm')
            for limit in limits_for_guest(guest):
                folder=BUILD/'inputs'/guest/str(limit)
                command([binaries['polkavm'],'--sieve-prepare',artifact,folder,limit,1],
                        f'prepare-{guest}-{limit}',environment(RAGNAROK_PVM_GUEST=guest))
                identities += [folder/f'input-{limit}.bin',folder/f'expected-{limit}.bin']
                workloads.append(dict(family=guest,limit=limit,
                    args=[binaries['polkavm'],'--sieve',artifact,folder,limit,13],env={'RAGNAROK_PVM_GUEST':guest}))
        # Both measured engines consume one interpreted DOOM preparation and one exact ROM.
        assets=json.loads((ROOT/'spec/pvm-doom-assets.json').read_text())
        if assets['polkavm_commit']!=pins['commit']:raise ValueError('DOOM source pin mismatch')
        for name,expected in assets['files'].items():
            if digest(upstream/name)!=expected:raise ValueError('changed DOOM source asset')
            identities.append(upstream/name)
        elf=BUILD/'doom.elf';blob=BUILD/'doom.polkavm';rom=upstream/'examples/doom/roms/doom1.wad'
        command(['zstd','-d','-f',upstream/'test-data/doom_64.elf.zst','-o',elf],'doom-decompress')
        command([binaries['polkavm_doom'],'link',elf,blob],'doom-link')
        folder=BUILD/'inputs/doom'
        command([binaries['polkavm_doom'],'prepare',blob,rom,folder,0],'doom-prepare',environment())
        identities += [blob,rom]
        for phase in ('init','tick'):
            identities += [folder/(phase+'.'+suffix) for suffix in ('input','expected','events')]
            workloads.append(dict(family=phase,limit=0,args=[binaries['polkavm_doom'],'run',blob,rom,folder,phase],
                env={'RAGNAROK_PVM_DOOM_TIMING':'1'},event_bytes=(folder/(phase+'.events')).stat().st_size))
        report['identities']={str(p.relative_to(ROOT)):digest(p) for p in identities};save()
        # A changed expected state must stop each backend before publishing execution samples.
        original=BUILD/'inputs/minimal/1000';bad=BUILD/'bad-input'
        bad.mkdir(exist_ok=True)
        shutil.copyfile(original/'input-1000.bin',bad/'input-1000.bin')
        data=bytearray((original/'expected-1000.bin').read_bytes());data[-1]^=1
        (bad/'expected-1000.bin').write_bytes(data)
        artifact=contracts['pvm_guests'][1]/'minimal.polkavm'
        for backend in ('interpreter','compiler'):
            # Successful execution proves sandbox availability and clock coverage before a refusal test.
            output,evidence=command([binaries['polkavm'],'--sieve',artifact,original,1000,1],
                'backend-available-'+backend,environment(backend,RAGNAROK_PVM_GUEST='minimal'))
            available=parse(output,backend,'minimal',1000,count=1)
            report['controls'].append(dict(kind='backend_available',backend=backend,cases=available))
            output,evidence=command([binaries['polkavm'],'--sieve',artifact,bad,1000,1],
                'tampered-state-'+backend,environment(backend,RAGNAROK_PVM_GUEST='minimal'),fail=True)
            if 'terminal state mismatch' not in output or 'REFERENCE_CPU,' in output:
                raise ValueError('reference corruption control did not reach terminal-state validation: '+evidence['log'])
            report['controls'].append(dict(kind='tampered_expected',backend=backend,rejected=True))
        # Application results remain available if a later optional synthetic profile is unavailable.
        workloads.sort(key=lambda row: (0 if row['family'] in ('init','tick') else 2 if row['family']=='synthetic' else 1))
        # All process pairs reverse backend order, with three warmups and ten retained samples.
        for workload in workloads:
            family,limit=workload['family'],workload['limit']
            for pair in range(pairs):
                order=('interpreter','compiler') if pair%2==0 else ('compiler','interpreter')
                for backend in order:
                    args=[*workload['args'],backend] if family=='synthetic' else workload['args']
                    output,evidence=command(args,f'{family}-{limit}-pair{pair}-{backend}',
                        environment(backend,**workload['env']))
                    cases=parse(output,backend,family,limit,workload.get('event_bytes',0))
                    report['runs'].append(dict(backend=backend,pair=pair,family=family,limit=limit,
                        cases=cases,log=evidence['log'],log_sha256=digest(evidence['log'])))
                    save()
            report['cases']=summarize(report['runs']);save()
            for name,expected in report['identities'].items():
                if digest(ROOT/name)!=expected:raise ValueError('measurement input changed during collection')
        report['cases']=summarize(report['runs']);report['status']='checks-passed'
        report['hardware']['load_end']=os.getloadavg();save()
        lines=['# PolkaVM native/interpreted calibration','',
               'Warm CPU includes both parent and active Linux sandbox worker; 3 warmups, 10 samples per process, paired orders.',
               'Native means the pinned Compiler backend. Cold module preparation is retained in JSON.','',
               '| Workload | Native / interpreted CPU | Interpreted / native speedup | Native / interpreted wall |',
               '| --- | ---: | ---: | ---: |']
        for name,case in report['cases'].items():
            lines.append(f"| {name} | {case['native_per_interpreted']:.6f} | {case['interpreted_per_native']:.2f}× | {case['native_per_interpreted_wall']:.6f} |")
        lines += ['', 'Cross-architecture estimate: `(our ARM / PolkaVM interpreted ARM) / (PolkaVM native x86 / interpreted x86)`. This assumes the per-workload reference ratio transfers; it does not measure ARM native execution.']
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
        with (BUILD/'samples.csv').open('w',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(('workload','backend','pair','sample','warmup','parent_cpu_ns','worker_cpu_ns','total_cpu_ns','wall_ns'))
            for row in report['runs']:
                for name,case in row['cases'].items():
                    for sample,values in enumerate(case['samples']):
                        writer.writerow((name,row['backend'],row['pair'],sample,sample<3,
                            values['parent_cpu_ns'],values['worker_cpu_ns'],values['cpu_ns'],values['wall_ns']))
        print((BUILD/'summary.md').read_text())
    except Exception as error:
        report['status']='failed';report['error']=str(error);save();raise


if __name__=='__main__':run()
