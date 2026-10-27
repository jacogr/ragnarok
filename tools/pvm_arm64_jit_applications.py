#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Local ARM64 application qualification: public lifetimes, long loops and genuine DOOM hosts.

Fresh paired images and complete-state/refusal controls precede timing. All constructors and cold
calls remain visible. Retained-frame core is reported separately from public invocation ownership.
"""
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile
from native_checks import NativeChecks, ROOT
from pvm_arm64_jit import parse as parse_core
from pvm_guest_inputs import prepare_inputs, digest
from pvm_guest_compare import unchanged
from pvm_interpreter_compare import parse_public, parse_candidate
from pvm_sieve_report import parse_process_output
from pvm_doom_attribution import run as prepare_doom, BUILD as DOOM, timing_samples, reference_lifecycle_samples
from pvm_benchmark import cpu_model
from setup_nimony import installed, cache_directory

BUILD = ROOT/'build/tests/pvm-arm64-applications'
BASELINE = '01f9c6742e18cb87b97545417c85a734dddf3350'
ROLES = ('interpreter', 'baseline', 'jit', 'core', 'reference')
COUNTERS = ('fragments', 'calls', 'operations', 'code_bytes', 'compilation_ns', 'branches', 'headers')


def owner_receipt(output, case):
    """Only one exact final bounded receipt can certify native code survived the measured owner lifetime."""
    lines = output.splitlines()
    fields = lines.pop().split(',') if lines else []
    if len(fields)!=9 or fields[:2]!=['ARM_OWNER',case]:
        raise ValueError('Missing native owner receipt')
    if any(not v.isascii() or not v.isdecimal() or int(v)>=2**63 for v in fields[2:]):
        raise ValueError('Invalid native owner counters')
    counters = dict(zip(COUNTERS,map(int,fields[2:])))
    if counters['headers']>counters['branches'] or counters['branches']>counters['calls']:
        raise ValueError('Impossible native owner counters')
    if counters['fragments']>1024 or counters['code_bytes']>1024*1024:
        raise ValueError('Native owner capacity exceeded')
    return '\n'.join(lines)+'\n', counters


def parse_run(output, role, case, limit, event_bytes=0):
    """Use identical native-owner framing for both compared public JIT roles and strict lifecycle parsers."""
    counters = None
    doom = case in ('init','tick')
    if role in ('baseline','jit') or (role=='core' and doom):
        output,counters = owner_receipt(output,case)
    if role=='reference':
        parsed = reference_lifecycle_samples(output,case,event_bytes) if doom else parse_process_output(output,'polkavm_interpreter',limit,guest=case)
    elif role=='core':
        if doom:
            parsed = parse_candidate(output,case,True,event_bytes)
        else:
            native = parse_core(output,case,True,True)
            parsed = native['execution']; counters = dict(**native['native'],**native['control'])
    else:
        parsed = parse_public(output,case,limit,prepared=True,doom=doom,event_bytes=event_bytes)
    return dict(execution=parsed,native=counters)


def run():
    """Qualify one explicit source cohort before accepting any timing or native/public claim."""
    if platform.system() not in ('Darwin','Linux') or platform.machine() not in ('arm64','aarch64'):
        raise SystemExit('Application experiment requires macOS or Linux ARM64')
    BUILD.mkdir(parents=True,exist_ok=True)
    report = dict(status='incomplete',baseline=BASELINE,platform=platform.platform(),cpu=cpu_model(),
                  builds=[],sources={},controls=[],runs=[],comparison_protocol='matched-owner-v1')
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    (BUILD/'summary.md').write_text('Application comparison incomplete.\n')
    checks = NativeChecks(BUILD)
    compiler,_ = installed()
    fixtures = prepare_inputs(checks,BUILD/'inputs')
    # Reuse maintained pinned-source/asset/ROM/link/host controls before fresh application timings.
    prepare_doom(check_only=True)
    doom_report = json.loads((DOOM/'results.json').read_text())
    assert doom_report['status']=='checks-passed'
    report['doom_admission'] = doom_report
    ids = dict(fixtures['identities'])
    reference = fixtures['reference']
    reference_doom = ROOT/'build/pvm-doom-rust-target/release/ragnarok-pvm-doom'
    ids.update({reference_doom:digest(reference_doom),compiler:digest(compiler)})
    # The long-sieve fixture is freshly produced by the same pinned interpreted reference, with a known prime count.
    destination = BUILD/'inputs/sieve/10000000'; destination.mkdir(parents=True,exist_ok=True)
    artifact = ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm'
    prepared = checks.command([reference,'--sieve-prepare',artifact,destination,10000000,1],
        'prepare-long-sieve',environment=dict(os.environ,RAGNAROK_PVM_GUEST='sieve'),timeout=300)
    if prepared['exit_code']: raise RuntimeError(prepared['output'][-2000:])
    report['long_preparation'] = prepared
    cases = [(g,n,d,e) for g,n,d,e in fixtures['inputs'] if n==100000 or g=='pinky']
    cases.append(('sieve',10000000,destination/'input-10000000.bin',destination/'expected-10000000.bin'))
    cases += [('init',0,None,None),('tick',0,None,None)]
    for path in [*sorted((ROOT/'src').rglob('*.nim')),*sorted((ROOT/'native/pvm_jit').glob('*')),
                 *sorted((ROOT/'tools').glob('*.py')),*sorted((ROOT/'tests/performance').glob('pvm*')),
                 ROOT/'spec/toolchain.json']:
        if path.is_file(): ids[path]=digest(path)
    for path in [DOOM/'doom.polkavm',ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad',*sorted((DOOM/'prepared').glob('*')),
                 cases[4][2],cases[4][3]]:
        ids[path]=digest(path)
    images = {}
    for role in ROLES[:-1]:
        canonical = BUILD/'snapshot'
        if canonical.exists(): shutil.rmtree(canonical)
        canonical.mkdir()
        if role=='baseline':
            raw=subprocess.check_output(['git','archive',BASELINE,'src','native/pvm_jit'],cwd=ROOT)
            with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
                for member in archive.getmembers():
                    if not member.isfile(): continue
                    target=canonical/member.name
                    if not target.resolve().is_relative_to(canonical.resolve()): raise ValueError('Foreign archive path')
                    target.parent.mkdir(parents=True,exist_ok=True)
                    target.write_bytes(archive.extractfile(member).read())
        else:
            shutil.copytree(ROOT/'src',canonical/'src')
            shutil.copytree(ROOT/'native/pvm_jit',canonical/'native/pvm_jit')
        drivers = ('pvm_stream_lifecycle','pvm_stream_doom') if role=='core' else ('pvm_sieve','pvm_doom')
        (canonical/'benchmarks').mkdir()
        for family,name in zip(('kernel','doom'),drivers):
            driver=canonical/'benchmarks'/(family+'.nim')
            driver.write_text((ROOT/('tests/performance/'+name+'.nim')).read_text().replace('../../src/','../src/'))
            defines=[] if role=='interpreter' else ['pvmArm64Jit']
            # Both public JIT roles need identical code-generation settings, including out-of-clock coverage receipts.
            if role in ('baseline','jit') or (role=='core' and family=='doom'): defines+=['pvmArm64JitOwnerReceipt']
            if role=='core' and family=='kernel': defines+=['pvmArm64JitControlReceipt']
            pair=[]
            for repeat in range(2):
                cache=cache_directory(compiler,BUILD,'engine')
                if cache.exists(): shutil.rmtree(cache)
                built,binary=checks.build(compiler,driver,'engine',defines=defines,
                    cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(canonical/'native/pvm_jit')])
                if built['exit_code']: raise RuntimeError(built['output'][-3000:])
                saved=BUILD/f'{role}-{family}-{repeat}'; shutil.copy2(binary,saved);pair.append(saved)
                ids[saved]=digest(saved)
                report['builds'].append(dict(role=role,family=family,repeat=repeat,run=built))
            if pair[0].read_bytes()!=pair[1].read_bytes(): raise ValueError('Fresh equal-image control failed')
            images[role,family]=pair[0]
        report['sources'][role]={str(path.relative_to(canonical)):digest(path) for path in sorted(canonical.rglob('*')) if path.is_file()}
    # An unchanged source cohort is an A/A control: role naming must never change either public executable image.
    report['equal_source_control'] = report['sources']['baseline'] == report['sources']['jit']
    if report['equal_source_control']:
        for family in ('kernel','doom'):
            if images['baseline',family].read_bytes()!=images['jit',family].read_bytes():
                raise ValueError('Equal public JIT sources produced different role images')
    report['identities']={str(p.relative_to(ROOT)):h for p,h in ids.items()}
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    for order in range(2):
        for case,limit,data,expected in cases:
            doom=case in ('init','tick'); family='doom' if doom else 'kernel'
            events=(DOOM/'prepared'/(case+'.events')).stat().st_size if doom else 0
            env=dict(os.environ,RAGNAROK_PVM_GUEST=case,RAGNAROK_PVM_PRICING='prepared',
                     RAGNAROK_PVM_SIEVE_SAMPLES='13',RAGNAROK_PVM_SIEVE_CLOCK='1',RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
                     RAGNAROK_PVM_DOOM_PRICING='prepared',RAGNAROK_PVM_DOOM_PREPARATION='1',
                     RAGNAROK_PVM_DOOM_TIMING='1',RAGNAROK_PVM_DOOM_ASSERT='0',RAGNAROK_PVM_LOCAL_ONECALL='0',
                     RAGNAROK_PVM_DOOM_INPUT=str(DOOM/'prepared'),RAGNAROK_PVM_DOOM_PHASE=case,
                     RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'))
            if not doom: env.update(RAGNAROK_PVM_SIEVE_INPUT=str(data),RAGNAROK_PVM_SIEVE_EXPECTED=str(expected))
            for role in (ROLES if order==0 else ROLES[::-1]):
                env['RAGNAROK_PVM_DOOM_LIFECYCLE']='1' if role=='reference' and doom else '0'
                args=[images[role,family]] if role!='reference' else ([reference_doom,'run',DOOM/'doom.polkavm',env['RAGNAROK_PVM_DOOM_ROM'],DOOM/'prepared',case] if doom else [reference,'--sieve',artifact if case=='sieve' else ROOT/f'tests/fixtures/{"pvm-pinky" if case=="pinky" else "pvm-guests"}/{case}.polkavm',data.parent,limit,13])
                if order==0:
                    positive=checks.command(args,f'{case}-{limit}-{role}-positive',environment=env,timeout=900)
                    if positive['exit_code']: raise RuntimeError(positive['output'][-2000:])
                    parse_run(positive['output'],role,case,limit,events)
                    report['controls'].append(dict(case=case,limit=limit,role=role,kind='positive',run=positive))
                    for kind in (('assertions','state','events') if doom else ('assertions','state')):
                        controlled = DOOM/'prepared'/(case+('.events' if kind=='events' else '.expected')) if doom else expected
                        original=controlled.read_bytes()
                        probe=dict(env)
                        if kind=='assertions': probe['RAGNAROK_PVM_DOOM_ASSERT' if doom else 'RAGNAROK_PVM_SIEVE_ASSERT_PROBE']='1'
                        else:
                            changed=bytearray(original);changed[8]^=1;controlled.write_bytes(changed)
                        try:
                            refused=checks.command(args,f'{case}-{limit}-{role}-{kind}',environment=probe,timeout=900)
                            if refused['exit_code']==0 or not any(word in refused['output'] for word in ('Assertion Failure','panicked')):
                                raise ValueError('Missing intended application refusal')
                        finally:
                            if kind!='assertions': controlled.write_bytes(original)
                        report['controls'].append(dict(case=case,limit=limit,role=role,kind=kind,run=refused))
                unchanged(ids)
                row=checks.command(args,f'{case}-{limit}-{order}-{role}',environment=env,timeout=900)
                if row['exit_code']: raise RuntimeError(row['output'][-3000:])
                parsed=parse_run(row['output'],role,case,limit,events)
                report['runs'].append(dict(case=case,limit=limit,order=order,role=role,run=row,parsed=parsed))
                unchanged(ids)
                (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    if len(report['runs'])!=70 or len(report['controls'])!=115: raise ValueError('Incomplete application cohort')
    if not any(r['parsed']['native']['operations']>0 for r in report['runs'] if r['role']=='jit'):
        raise ValueError('No native public execution')
    report['identities']={str(p.relative_to(ROOT)):h for p,h in ids.items()}
    report['status']='passed'
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.','',
           '| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |',
           '|---|---:|---:|---:|---:|---:|---:|---:|']
    for case,limit,_,_ in cases:
        columns=[[] for _ in range(7)]
        for order in range(2):
            medians={role:statistics.median(next(r for r in report['runs'] if (r['case'],r['limit'],r['order'],r['role'])==(case,limit,order,role))['parsed']['execution']['samples'][i]['cpu_ns'] for i in range(3,13)) for role in ROLES}
            values=[*[f'{medians[role]/1e6:.3f}' for role in ROLES],f'{medians["jit"]/medians["interpreter"]:.3f}',f'{medians["jit"]/medians["reference"]:.3f}']
            for col,value in zip(columns,values): col.append(value)
        lines.append('| '+case+' '+str(limit)+' | '+' | '.join(' / '.join(c) for c in columns)+' |')
    (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))


if __name__=='__main__':
    run()
