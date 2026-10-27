#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Local ARM64 register-fragment experiment; complete checked fixtures, fresh builds and both orders.

This compares retained frames only. Public invocation ownership and DOOM host integration are
separate future increments. Compilation/publication, including rejected-fragment scans and cache construction, remains inside the cold execution clock.
"""
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
from native_checks import NativeChecks, ROOT
from setup_nimony import installed, cache_directory
from pvm_guest_inputs import prepare_inputs, digest
from pvm_guest_compare import unchanged
from pvm_interpreter_compare import parse_candidate

BUILD = ROOT/'build/tests/pvm-arm64-jit'
DRIVER = ROOT/'tests/performance/pvm_stream_lifecycle.nim'


def parse(output, guest, native):
    """Separate the one declared native receipt from the existing strict thirteen-call protocol."""
    lines = output.splitlines()
    receipt = None
    if native:
        fields = lines.pop().split(',') if lines else []
        if len(fields) != 7 or fields[:2] != ['ARM_JIT', guest]:
            raise ValueError('Missing native coverage receipt')
        if any(not x.isascii() or not x.isdecimal() or int(x) >= 2**63 for x in fields[2:]):
            raise ValueError('Malformed native coverage receipt')
        receipt = dict(zip(('fragments','calls','operations','code_bytes','compilation_ns'),map(int,fields[2:])))
    return dict(execution=parse_candidate('\n'.join(lines)+'\n',guest), native=receipt)


def main():
    """Build serially before all timing, keep complete receipts and refuse incomplete cohorts."""
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This local experiment requires Darwin ARM64')
    BUILD.mkdir(parents=True,exist_ok=True)
    checks = NativeChecks(BUILD)
    compiler, _ = installed()
    report = dict(status='incomplete',platform=platform.platform(),toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),builds=[],controls=[],runs=[])
    report['qualification'] = []
    memory = checks.command(['clang','-O2','-Wall','-Wextra','-Werror','-I'+str(ROOT/'native/pvm_jit'),
        ROOT/'tests/performance/pvm_arm64_jit_memory.c','-o',BUILD/'memory-check'],'memory-build')
    if memory['exit_code']: raise RuntimeError(memory['output'])
    memory = checks.command([BUILD/'memory-check'],'memory-run')
    if memory['exit_code'] or memory['output'] != 'ARM_MEMORY_OK,1000,capacity,publication,retirement\n':
        raise ValueError('Executable storage controls failed')
    report['qualification'].append(memory)
    for name,source,defines in (
        ('witness','tests/performance/pvm_arm64_jit_witness.nim',['pvmArm64Jit']),
        ('witness-refused','tests/performance/pvm_arm64_jit_witness.nim',['pvmArm64Jit','pvmArm64JitRefuse']),
        ('all-opcodes','tests/unit/codec/test_pvm_stream_all_opcodes.nim',['pvmArm64Jit']),
        ('regions-host','tests/unit/codec/test_pvm_stream_regions_and_host.nim',['pvmArm64Jit'])):
        # Qualify native execution, explicit OS refusal and the established whole-state boundary suites before timing.
        built,binary=checks.build(compiler,ROOT/source,name,defines=defines,cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if built['exit_code']: raise RuntimeError(built['output'][-3000:])
        checked=checks.command([binary],name+'-run')
        if checked['exit_code']: raise RuntimeError(checked['output'][-3000:])
        report['qualification'].append(checked)
    fixtures = prepare_inputs(checks,BUILD/'inputs')
    identities = dict(fixtures['identities'])
    identities[compiler] = digest(compiler)
    # Bind maintained source/helper/header bytes, not just a mutable branch name.
    for parent in ('src','native/pvm_jit'):
        for path in sorted((ROOT/parent).rglob('*')):
            if path.is_file(): identities[path] = digest(path)
    for path in [*sorted((ROOT/'tools').rglob('*.py')),DRIVER,ROOT/'tests/performance/pvm_sieve_clock.h',ROOT/'tests/performance/pvm_arm64_jit_witness.nim',ROOT/'tests/performance/pvm_arm64_jit_memory.c']:
        identities[path] = digest(path)
    images = {}
    for mode in ('interpreter','jit'):
        pair = []
        for repeat in range(2):
            # The same source/output coordinates and wholly private fresh cache control path-dependent images.
            cache = cache_directory(compiler,BUILD,'engine')
            if cache.exists(): shutil.rmtree(cache)
            row,binary = checks.build(compiler,DRIVER,'engine',defines=['pvmArm64Jit'] if mode=='jit' else [],
                cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(ROOT/'native/pvm_jit')])
            report['builds'].append(dict(mode=mode,repeat=repeat,build={k:v for k,v in row.items() if k!='output'}))
            if row['exit_code']: raise RuntimeError(row['output'][-3000:])
            saved = BUILD/f'{mode}-{repeat}'
            shutil.copy2(binary,saved)
            pair.append(saved)
            identities[saved] = digest(saved)
        if pair[0].read_bytes()!=pair[1].read_bytes(): raise ValueError('Fresh equal-image control failed')
        images[mode] = pair[0]
    for order in range(2):
        for guest,limit,data,expected in fixtures['inputs']:
            for mode in (('interpreter','jit') if order==0 else ('jit','interpreter')):
                env = dict(os.environ,RAGNAROK_PVM_GUEST=guest,RAGNAROK_PVM_SIEVE_INPUT=str(data),
                    RAGNAROK_PVM_SIEVE_EXPECTED=str(expected),RAGNAROK_PVM_SIEVE_SAMPLES='13',RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
                if order==0:
                    # Both unchanged positive execution and active assertion/state refusal controls precede timing.
                    positive = checks.command([images[mode]],f'{guest}-{limit}-{mode}-positive',environment=env)
                    if positive['exit_code']: raise RuntimeError(positive['output'][-2000:])
                    parse(positive['output'],guest,mode=='jit')
                    report['controls'].append(dict(case=guest,limit=limit,mode=mode,kind='positive',run=positive))
                    for kind in ('assertions','state'):
                        probe = dict(env)
                        if kind=='assertions': probe['RAGNAROK_PVM_SIEVE_ASSERT_PROBE']='1'
                        else:
                            # A private changed expectation preserves every original fixture identity.
                            wrong = BUILD/'wrong-expected.bin'
                            raw=bytearray(expected.read_bytes());raw[8]^=1;wrong.write_bytes(raw)
                            probe['RAGNAROK_PVM_SIEVE_EXPECTED']=str(wrong)
                        refused=checks.command([images[mode]],f'{guest}-{limit}-{mode}-{kind}',environment=probe)
                        if refused['exit_code']==0 or 'Assertion Failure' not in refused['output']:
                            raise ValueError('Missing intended assertion/state refusal')
                        report['controls'].append(dict(case=guest,limit=limit,mode=mode,kind=kind,run=refused))
                unchanged(identities)
                run=checks.command([images[mode]],f'{guest}-{limit}-{order}-{mode}',environment=env)
                if run['exit_code']: raise RuntimeError(run['output'][-2000:])
                report['runs'].append(dict(case=guest,limit=limit,order=order,mode=mode,run=run,parsed=parse(run['output'],guest,mode=='jit')))
                unchanged(identities)
    if len(report['runs'])!=28 or len(report['controls'])!=42: raise ValueError('Incomplete cohort')
    if sum(r['parsed']['native']['operations'] for r in report['runs'] if r['mode']=='jit')==0:
        raise ValueError('No compiled execution observed')
    report['identities']={str(p.relative_to(ROOT)):h for p,h in identities.items()}
    report['status']='passed'
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['CPU ms, forward / reverse. Retained frames; cold includes compilation and publication.','',
        '| Case | Interpreter reused | JIT reused | JIT / interpreter | JIT cold | Compilation | Native operations / 13 calls |',
        '|---|---:|---:|---:|---:|---:|---:|']
    for guest,limit,_,_ in fixtures['inputs']:
        columns=[[],[],[],[],[],[]]
        for order in range(2):
            selected=[r for r in report['runs'] if (r['case'],r['limit'],r['order'])==(guest,limit,order)]
            old=next(r['parsed'] for r in selected if r['mode']=='interpreter')
            new=next(r['parsed'] for r in selected if r['mode']=='jit')
            old_ns=statistics.median(s['cpu_ns'] for s in old['execution']['samples'][3:])
            new_ns=statistics.median(s['cpu_ns'] for s in new['execution']['samples'][3:])
            values=[f'{old_ns/1e6:.3f}',f'{new_ns/1e6:.3f}',f'{new_ns/old_ns:.3f}',
                f"{new['execution']['samples'][0]['cpu_ns']/1e6:.3f}",f"{new['native']['compilation_ns']/1e6:.3f}",str(new['native']['operations'])]
            for column,value in zip(columns,values): column.append(value)
        lines.append('| '+guest+' '+str(limit)+' | '+' | '.join(' / '.join(c) for c in columns)+' |')
    (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))


if __name__=='__main__':
    main()
