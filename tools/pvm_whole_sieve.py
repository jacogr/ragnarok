#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Private local ARM64 whole-program sieve experiment; gas-free results are diagnostic only.

Builds one native whole image and separately compares current gas-metered JIT and untraced PolkaVM.
No production runtime, quota, default or shared emitter source is modified.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import statistics
import subprocess
import time
import tarfile

from native_checks import NativeChecks, ROOT
from native_dependencies import require_submodule
from pvm_sieve_benchmark import verify_fixture
from setup_nimony import installed

BUILD = ROOT/'build/pvm-whole-sieve'
PRODUCTION = '8bcb461b866f0edb970b6542ad9823f9aaa3050a'
ROLES = ('whole-image-gas-off', 'current-jit-gas-on', 'reference-untraced-gas-on')
REPEATS, DISCARDED = 13, 3


def replace_once(source, old, new):
    """Private consumers fail on source drift instead of guessing a changed measurement boundary."""
    if source.count(old) != 1:
        raise ValueError('private projection anchor differs: '+old[:80])
    return source.replace(old, new, 1)


def reference_projection(source):
    """Retain the fast run and full snapshot check; clock fresh instance restore/drop separately from module reuse."""
    source=replace_once(source,'    profile.set_page_size(4096);',
                        '    profile.set_page_size(4096);\n    profile.set_step_tracing(false);')
    source=replace_once(source,'    assert!(samples == 1 || samples == 13);','    assert!(samples == 1 || samples == 2 || samples == 13);')
    source=replace_once(source,'    let module = module(blob);', '''    let started=cpu_nanoseconds();
    let module = module(blob);
    let prepared=cpu_nanoseconds()-started;
    if !preparing {
        println!("FAST_MODE,interpreter,step_tracing=false");
        println!("FAST_PREPARE,{prepared}");
    }''')
    source=replace_once(source,'    for sample in 0..samples {\n        let mut instance = restored_instance(&module, entry, &registers, &initialized_pages);', '''    drop(initial);
    for sample in 0..samples {
        let restore_start=cpu_nanoseconds();
        let mut instance = restored_instance(&module, entry, &registers, &initialized_pages);
        let restore_elapsed=cpu_nanoseconds()-restore_start;''')
    source=replace_once(source,'        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");', '''        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");
        let retire_start=cpu_nanoseconds();
        drop(instance);
        let retired=cpu_nanoseconds()-retire_start;
        println!("FAST_RESTORE,{sample},{restore_elapsed}");
        println!("FAST_INSTANCE_TEARDOWN,{sample},{retired}");''')
    # Only the final command body is extended; module/helpers and the actual invocation remain maintained.
    assert source.endswith('    }\n}\n')
    source=source[:-2]+'''    let started=cpu_nanoseconds();
    drop(module);
    let retired=cpu_nanoseconds()-started;
    println!("FAST_RETIRE,{retired}");
    println!("FAST_SEQUENCE_OK,sieve,{samples}");
}
'''
    return source


def digest(path):
    """All source, input and image identities bind actual immutable bytes, never a file timestamp."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unsigned(value):
    """Metrics use canonical bounded nonnegative integers, including genuine sub-resolution zero clocks."""
    if not value.isascii() or not value.isdecimal() or len(value)>20 or int(value)>=2**64:
        raise ValueError('invalid numeric experiment receipt')
    return int(value)


def matrix():
    """Prespecify one serial forward/reverse cohort:13fresh processes/role/order with3fixed discards."""
    return [(order, sample, role) for order, roles in enumerate((ROLES, ROLES[::-1]))
            for sample in range(REPEATS) for role in roles]


def parse(output, role):
    """Read only actual CPU/elapsed scopes; absent reference/JIT lifecycle scopes remain absent."""
    rows=[r.split(',') for r in output.splitlines()]
    if role==ROLES[0]:
        if rows[-1]!=['WHOLE_PASS','10000000'] or rows.count(['WHOLE_GAS_DISABLED','1'])!=1:
            raise ValueError('incomplete gas-free whole-image witness')
        calls=[r for r in rows if r[0]=='WHOLE_EXIT']
        if len(calls)!=2 or any(len(r)!=9 or r[1:5]!=[str(i),'1','0','1'] for i,r in enumerate(calls)):
            raise ValueError('whole image did not complete in one real native exit')
        image=[r for r in rows if r[0]=='WHOLE_IMAGE']
        if len(image)!=1 or len(image[0])!=5 or min(map(unsigned,image[0][1:]))<=0:
            raise ValueError('missing complete native compilation')
        helpers=[list(map(unsigned,r[5:7])) for r in calls]
        if helpers!=[[11272390,4203132]]*2:
            raise ValueError('unexpected actual checked-memory helper work')
        scopes={}
        for tag,key in [('WHOLE_INPUT_PREPARE','input_prepare'),('WHOLE_IMAGE_RETIRE','image_retirement')]:
            selected=[r for r in rows if r[0]==tag]
            if len(selected)!=1 or len(selected[0])!=3:raise ValueError('missing native scope: '+tag)
            scopes[key]=dict(cpu_ns=unsigned(selected[0][1]),elapsed_ns=unsigned(selected[0][2]))
        scopes['constructor']=dict(cpu_ns=unsigned(image[0][3]),elapsed_ns=unsigned(image[0][4]))
        for tag,key in [('WHOLE_RESTORE','writer_restore'),('WHOLE_PUBLICATION','immutable_publication')]:
            selected=[r for r in rows if r[0]==tag]
            if len(selected)!=2 or any(len(r)!=4 or r[1]!=str(i) for i,r in enumerate(selected)):
                raise ValueError('missing native per-call scope: '+tag)
            scopes[key]=[dict(cpu_ns=unsigned(r[2]),elapsed_ns=unsigned(r[3])) for r in selected]
        return dict(calls=[dict(cpu_ns=unsigned(r[7]),elapsed_ns=unsigned(r[8])) for r in calls],
                    scopes=scopes,code_bytes=unsigned(image[0][1]),compiled_instructions=unsigned(image[0][2]),
                    native_exits=[1,1],checked_helpers=helpers,gas_metering=False)
    calls=[r for r in rows if r[0]=='SIEVE']
    label='ragnarok_prepared' if role==ROLES[1] else 'polkavm_interpreter'
    if len(calls)!=2 or any(len(r)!=6 or r[1:4]!=[label,'10000000',str(i)] for i,r in enumerate(calls)):
        raise ValueError('incomplete comparison calls')
    scopes={}
    if role==ROLES[1]:
        prepared=[r for r in rows if r[0]=='PREPARED_PROGRAM']
        if len(prepared)!=1:raise ValueError('missing current prepared owner')
        scopes['constructor']=dict(cpu_ns=unsigned(prepared[0][1]),elapsed_ns=unsigned(prepared[0][2]))
        native=[r for r in rows if r[0]=='WHOLE_JIT_NATIVE']
        if len(native)!=2 or any(len(r)!=6 or r[1]!=str(i) or r[2]!='jit' for i,r in enumerate(native)):
            raise ValueError('missing actual current JIT work')
        values=[list(map(unsigned,r[3:])) for r in native]
        if min(values[0])<=0 or any(values[1][i]<=values[0][i] for i in (1,2)):
            raise ValueError('continuing current JIT call made no native progress')
    else:
        if rows.count(['FAST_MODE','interpreter','step_tracing=false'])!=1 or rows[-1]!=['FAST_SEQUENCE_OK','sieve','2']:
            raise ValueError('reference is not explicit untraced interpretation')
        for tag,key in [('FAST_PREPARE','constructor'),('FAST_RETIRE','module_retirement')]:
            selected=[r for r in rows if r[0]==tag]
            if len(selected)!=1 or len(selected[0])!=2:raise ValueError('missing reference scope: '+tag)
            scopes[key]=dict(cpu_ns=unsigned(selected[0][1]),elapsed_ns=None)
        for tag,key in [('FAST_RESTORE','instance_restore'),('FAST_INSTANCE_TEARDOWN','instance_teardown')]:
            selected=[r for r in rows if r[0]==tag]
            if len(selected)!=2 or any(len(r)!=3 or r[1]!=str(i) for i,r in enumerate(selected)):
                raise ValueError('missing reference per-call scope')
            scopes[key]=[dict(cpu_ns=unsigned(r[2]),elapsed_ns=None) for r in selected]
    return dict(calls=[dict(cpu_ns=unsigned(r[5]),elapsed_ns=unsigned(r[4])) for r in calls],
                scopes=scopes,gas_metering=True)


def summarize(runs):
    """Compute per-order raw medians/ranges and call-only diagnostic ratios, without pooling runners or scopes."""
    if [(r['order'],r['sample'],r['role']) for r in runs]!=matrix():
        raise ValueError('incomplete serial comparison cohort')
    results=[]
    for order in (0,1):
        roles={}
        for role in ROLES:
            selected=[r for r in runs if r['order']==order and r['role']==role]
            for row in selected:
                if row['discarded']!=(row['sample']<DISCARDED) or row['measured']!=parse(row['run']['output'],role):
                    raise ValueError('changed parsed sample or discard policy')
            retained=[r['measured'] for r in selected if not r['discarded']]
            if len(retained)!=10:raise ValueError('missing retained process')
            calls=[]
            for call in range(2):
                metrics={}
                for metric in ('cpu_ns','elapsed_ns'):
                    values=[r['calls'][call][metric] for r in retained]
                    if min(values)<=0:raise ValueError('missing actual call clock')
                    metrics[metric]=dict(median=statistics.median(values),minimum=min(values),maximum=max(values),samples=10)
                calls.append(metrics)
            roles[role]=dict(calls=calls,retained_lifecycle_scopes=[r['scopes'] for r in retained])
        ratios={role:[roles[role]['calls'][call]['cpu_ns']['median']/roles[ROLES[2]]['calls'][call]['cpu_ns']['median']
                      for call in range(2)] for role in ROLES[:2]}
        results.append(dict(order=order,roles=roles,cpu_over_untraced_reference=ratios,
                            gas_and_ownership_equivalent=False))
    return results


def run():
    """Build/qualify locally only on ARM64, then execute exactly one fixed serial comparison cohort."""
    if platform.machine().lower() not in ('arm64','aarch64') or platform.system() not in ('Darwin','Linux'):
        raise RuntimeError('standalone experiment requires local ARM64')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    build=ROOT/'build'/('pvm-whole-sieve-'+revision[:8]+'-'+str(time.time_ns()))
    build.mkdir(parents=True,exist_ok=False)
    (ROOT/'build/pvm-whole-sieve-latest.json').write_text(json.dumps(dict(path=str(build),revision=revision),indent=2)+'\n')
    checks=NativeChecks(build)
    report=dict(status='incomplete',protocol='whole-sieve-arm64-gas-free-v1',production=PRODUCTION,
        gas_disabled_only_for_whole_image=True,performance_equivalent_to_production=False,
        host=dict(system=platform.system(),architecture=platform.machine()),builds=[],controls=[],commands=[],runs=[],summary=[],
        repeats=13,discard_first=3,calls_per_owner=2,scope='Native writer restore/publication outside call; JIT immutable publication inside call; reference mutable instances. Gas-off native versus gas-metered controls. No equivalent lifecycle total.')
    def save():
        """A failed setup/control/sample persists incomplete evidence instead of exposing an older success."""
        (build/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    def command(args,name,environment=None,required=True,timeout=900):
        """Retain process CPU including waited descendants separately from internal guest-call clocks."""
        before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic_ns()
        row=checks.command(args,name,environment=environment,timeout=timeout)
        after=resource.getrusage(resource.RUSAGE_CHILDREN)
        row['process_elapsed_ns']=time.monotonic_ns()-start
        row['process_cpu_ns']=round(((after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime))*1e9)
        report['commands'].append(dict(name=name,**row));save()
        if required and row['exit_code']:raise RuntimeError(name+' failed: '+row['output'][-1800:])
        return row
    save()
    try:
        report['revision']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        # The whole-image compiler consumes our unchanged public memory/program primitives; the current JIT uses a complete fresh-master archive.
        for path in ('src/pvm/program.nim','src/pvm/machine.nim','src/codec/natural.nim',
                     'tests/performance/pvm_sieve_clock.h','spec/toolchain.json'):
            if subprocess.check_output(['git','show',PRODUCTION+':'+path],cwd=ROOT)!=(ROOT/path).read_bytes():
                raise ValueError('whole-image primitive differs from current production: '+path)
        production_source=build/'production_source'
        production_source.mkdir(exist_ok=True)
        raw=subprocess.check_output(['git','archive',PRODUCTION,'src','native/pvm_jit'],cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
            for item in archive:
                if item.isdir():continue
                if not item.isfile() or Path(item.name).is_absolute() or '..' in Path(item.name).parts:
                    raise ValueError('foreign production archive member')
                target=production_source/item.name;target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.extractfile(item).read())
        report['cpu_model']=(subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
                             if platform.system()=='Darwin' else Path('/proc/cpuinfo').read_text())
        compiler,_=installed();report['compiler']=dict(path=str(compiler),sha256=digest(compiler),
            identity=(compiler.parent.parent/'NIGHTLY.txt').read_text())
        pins=json.loads((ROOT/'spec/polkavm-pins.json').read_text());upstream=require_submodule(pins,fetch=True)
        report['fixture']=verify_fixture(upstream=upstream,guest='sieve')
        rust=json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        rust_binary=Path(subprocess.check_output(['rustup','which','--toolchain',rust,'rustc'],text=True).strip())
        clang_binary=Path(shutil.which('clang')).resolve()
        compiler_identities={rust_binary:digest(rust_binary),clang_binary:digest(clang_binary)}
        report['external_compilers']={str(path):sha for path,sha in compiler_identities.items()}
        report['rust_version']=command(['rustup','run',rust,'rustc','--version','--verbose'],'rust-identity')
        report['clang_version']=command([clang_binary,'--version'],'clang-identity')
        report['provenance_limits']='Consumed owned/upstream/Nimony-library source bytes retained. Compiler executables identified by hash/version, not retained; system SDK and registry crates remain identified through versions/pinned lock checksums rather than a complete retained sysroot.'

        # Seal the actual source/header/toolchain library inputs before any build can consume them.
        original=ROOT/'tests/performance/polkavm'
        source_paths=[*[p for p in (ROOT/'src').rglob('*') if p.is_file()],
            *[p for p in (ROOT/'native/pvm_jit').rglob('*') if p.is_file()],
            *[p for p in production_source.rglob('*') if p.is_file()],
            *sorted((ROOT/'tools').glob('*.py')),*ROOT.glob('tests/performance/pvm_whole*'),
            ROOT/'tests/performance/pvm_sieve.nim',ROOT/'tests/performance/pvm_sieve_clock.h',
            *[p for p in original.rglob('*') if p.is_file()],
            *[p for p in (ROOT/'tests/fixtures/pvm-sieve').rglob('*') if p.is_file()],
            *[ROOT/'spec'/name for name in ('toolchain.json','polkavm-pins.json','bandersnatch-pins.json')],
            ROOT/'Makefile',ROOT/'.gitmodules',upstream/'Cargo.toml',upstream/'Cargo.lock',
            *[p for p in (upstream/'crates').rglob('*') if p.is_file()],
            *[upstream/name for name in {**pins['source_sha256'],**report['fixture']['upstream_sources']}],
            compiler.parent.parent/'NIGHTLY.txt',
            *[p for p in (compiler.parent.parent/'lib').rglob('*') if p.is_file()]]
        source_identities={p:digest(p) for p in source_paths if p.is_file()}
        report['source_maps']={str(p.relative_to(ROOT)):sha for p,sha in source_identities.items()}
        source_archive=build/'consumed-sources.tar.gz'
        with tarfile.open(source_archive,'w:gz') as archive:
            for path,wanted in sorted(source_identities.items()):
                raw=path.read_bytes()
                if hashlib.sha256(raw).hexdigest()!=wanted:raise ValueError('source changed before archival')
                item=tarfile.TarInfo(str(path.relative_to(ROOT)));item.size=len(raw);item.mode=0o644
                archive.addfile(item,io.BytesIO(raw))
        report['source_archive']=dict(path=str(source_archive.relative_to(ROOT)),sha256=digest(source_archive))

        original=ROOT/'tests/performance/polkavm';crate=build/'reference-source';(crate/'src').mkdir(parents=True,exist_ok=True)
        for path in [original/'Cargo.toml',original/'Cargo.lock',*sorted((original/'src').glob('*.rs'))]:
            text=path.read_text()
            if path.name=='Cargo.toml':text=text.replace('../../../vendor/polkavm/',str(upstream)+'/')
            if path.name=='sieve.rs':text=reference_projection(text)
            (crate/('src/'+path.name if path.suffix=='.rs' else path.name)).write_text(text)
        source_identities.update({p:digest(p) for p in crate.rglob('*') if p.is_file()})
        report['builds'].append(command(['rustup','run',rust,'cargo','fetch','--locked','--manifest-path',crate/'Cargo.toml'],'reference-fetch'))
        report['builds'].append(command(['rustup','run',rust,'cargo','build','--release','--locked','--offline','--manifest-path',crate/'Cargo.toml','--target-dir',build/'reference-target'],'reference-build'))
        reference=build/'reference-target/release/ragnarok-pvm-benchmark'
        driver=subprocess.check_output(['git','show',PRODUCTION+':tests/performance/pvm_sieve.nim'],cwd=ROOT).decode()
        driver=driver.replace('../../src/', './production_source/src/')
        driver=replace_once(driver,'assert requestedSamples in ["1", "4", "13"]','assert requestedSamples == "2"')
        driver=replace_once(driver,'let samples = if requestedSamples == "1": 1 elif requestedSamples == "4": 4 else: 13','let samples = 2')
        driver=replace_once(driver,'  check(done.value.machine, indices, access, expected, limit, guest)', '''  check(done.value.machine, indices, access, expected, limit, guest)
  assert done.value.backend == reference.PvmBackend.Jit
  let native = reference.preparedInfo(prepared).value
  assert native.jitBuilt and native.jitPlatformSupported and native.checkedFallbackEnabled
  echo "WHOLE_JIT_NATIVE,", sample, ",", done.value.backend, ",", native.nativeFragments,
    ",", native.nativeCalls, ",", native.nativeOperations''')
        adapter=build/'jit_adapter.nim';adapter.write_text(driver)
        source_identities[adapter]=digest(adapter)
        if any(digest(p)!=sha for p,sha in source_identities.items()):raise ValueError('consumed source changed during build preparation')
        images={}
        for role,source,defines in [(ROLES[0],ROOT/'tests/performance/pvm_whole_sieve.nim',[]),
                (ROLES[1],adapter,['pvmArm64Jit','pvmArm64JitOwnerReceipt']),
                ('controls',ROOT/'tests/performance/pvm_whole_controls.nim',[])]:
            before=resource.getrusage(resource.RUSAGE_CHILDREN);started=time.monotonic_ns()
            row,binary=checks.build(compiler,source,role,defines=defines,
                cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(production_source/'native/pvm_jit')])
            after=resource.getrusage(resource.RUSAGE_CHILDREN)
            row['process_elapsed_ns']=time.monotonic_ns()-started
            row['process_cpu_ns']=round(((after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime))*1e9)
            report['builds'].append(row)
            if row['exit_code']:raise RuntimeError(row['output'][-1800:])
            images[role]=binary
        images[ROLES[2]]=reference
        report['controls'].append(command([images['controls']],'native-controls'))
        if not report['controls'][-1]['output'].splitlines()[-1].startswith('WHOLE_CONTROLS_PASS,'):
            raise ValueError('missing actual native controls')
        def environment(limit):
            """Every role restores the same immutable reference input and checked expected state."""
            folder=build/'inputs'/str(limit)
            return dict(os.environ,RAGNAROK_PVM_GUEST='sieve',RAGNAROK_PVM_PRICING='prepared',
                RAGNAROK_PVM_BACKEND='jit',RAGNAROK_PVM_SIEVE_INPUT=str(folder/f'input-{limit}.bin'),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(folder/f'expected-{limit}.bin'),RAGNAROK_PVM_SIEVE_SAMPLES='2',
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
        for limit in (1000,10000000):
            folder=build/'inputs'/str(limit);folder.mkdir(parents=True,exist_ok=True)
            report['controls'].append(command([reference,'--sieve-prepare',ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm',folder,limit,1],f'prepare-{limit}',dict(os.environ,RAGNAROK_PVM_GUEST='sieve')))
            if limit==1000:
                # The actual small whole-image fixture must pass before the long diagnostic begins.
                row=command([images[ROLES[0]]],'whole-small-correctness',environment(1000))
                if row['output'].splitlines()[-1]!=['WHOLE_PASS,1000'][0]:
                    raise ValueError('small whole-image witness missing')
                report['controls'].append(row)
        for role in ROLES:
            env=environment(10000000);env['RAGNAROK_PVM_SIEVE_ASSERT_PROBE']='1'
            args=([images[role],'--sieve',ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm',build/'inputs/10000000',10000000,2]
                  if role==ROLES[2] else [images[role]])
            row=command(args,'assert-'+role,env,required=False)
            needle=('whole-image sieve assertion control' if role==ROLES[0] else
                    'pvm sieve native assertion control' if role==ROLES[1] else 'sieve reference assertion control')
            if row['exit_code']==0 or needle not in row['output']:raise ValueError('inactive assertion control: '+role)
            report['controls'].append(row)
        sources=[*ROOT.glob('tests/performance/pvm_whole*'),ROOT/'tools/pvm_whole_sieve.py',adapter,
                 *sorted(crate.rglob('*.rs')),crate/'Cargo.toml',crate/'Cargo.lock',compiler,
                 *[p for p in (build/'inputs').rglob('*') if p.is_file()],*images.values()]
        if any(digest(p)!=sha for p,sha in source_identities.items()):raise ValueError('consumed source changed during builds/controls')
        identities=dict(source_identities)
        identities.update({p:digest(p) for p in sources if p.is_file()})
        identities[source_archive]=report['source_archive']['sha256']
        report['identities']={str(p.relative_to(ROOT)):sha for p,sha in identities.items()}
        save()
        for order,sample,role in matrix():
            # Compile and validate before this serial cohort; no competing work is launched during timings.
            if any(digest(path)!=sha for path,sha in identities.items()):raise ValueError('input/source/image changed')
            args=([images[role],'--sieve',ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm',build/'inputs/10000000',10000000,2]
                  if role==ROLES[2] else [images[role]])
            row=command(args,f'order{order}-sample{sample}-{role}',environment(10000000))
            report['runs'].append(dict(order=order,sample=sample,role=role,discarded=sample<3,
                                      run=row,measured=parse(row['output'],role)))
            save()
        if any(digest(p)!=sha for p,sha in identities.items()):raise ValueError('final source/input/image seal changed')
        if any(digest(p)!=sha for p,sha in compiler_identities.items()):raise ValueError('compiler identity changed')
        report['final_seal']='passed'
        report['summary']=summarize(report['runs']);report['status']='passed'
        print(json.dumps(report['summary'],indent=2),flush=True)
    except BaseException as error:
        report['error']=type(error).__name__+': '+str(error)
        raise
    finally:save()


if __name__=='__main__':run()
