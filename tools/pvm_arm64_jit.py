#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Local ARM64 register-fragment experiment; complete checked fixtures, fresh builds and both orders.

This compares retained frames only. Public invocation ownership and DOOM host integration are
separate future increments. Compilation/publication, including rejected-fragment scans and cache construction, remains inside the cold execution clock.
"""
import argparse
import io
import tarfile
import subprocess
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
from native_checks import NativeChecks, ROOT
from setup_nimony import installed, cache_directory
from pvm_guest_inputs import prepare_inputs, digest
from pvm_guest_compare import unchanged, revision, snapshot_imports
from pvm_interpreter_compare import parse_candidate

BUILD = ROOT/'build/tests/pvm-arm64-jit'
DRIVER = ROOT/'tests/performance/pvm_stream_lifecycle.nim'


def baseline_revision(value=None):
    """Freeze current HEAD by default, or require an explicit immutable forty-digit commit ID."""
    if value is not None and (type(value) is not str or len(value)!=40
            or any(c not in '0123456789abcdef' for c in value)):
        raise ValueError('Baseline must be an exact lowercase commit SHA')
    resolved = revision('HEAD' if value is None else value)
    if len(resolved)!=40 or any(c not in '0123456789abcdef' for c in resolved):
        raise ValueError('Invalid resolved baseline commit')
    if value is not None and resolved!=value:
        raise ValueError('Resolved baseline differs from the exact commit SHA')
    return resolved


def parse(output, guest, native, control=False):
    """Separate the one declared native receipt from the existing strict thirteen-call protocol."""
    lines = output.splitlines()
    receipt = None
    control_receipt = None
    if control:
        fields = lines.pop().split(',') if lines else []
        if len(fields)!=4 or fields[:2]!=['ARM_CONTROL',guest]: raise ValueError('Missing native control receipt')
        if any(not x.isascii() or not x.isdecimal() or int(x)>=2**63 for x in fields[2:]):
            raise ValueError('Malformed native control receipt')
        control_receipt=dict(zip(('branches','headers'),map(int,fields[2:])))
        if control_receipt['headers']>control_receipt['branches']: raise ValueError('More native headers than branches')
    if native:
        fields = lines.pop().split(',') if lines else []
        if len(fields) != 7 or fields[:2] != ['ARM_JIT', guest]:
            raise ValueError('Missing native coverage receipt')
        if any(not x.isascii() or not x.isdecimal() or int(x) >= 2**63 for x in fields[2:]):
            raise ValueError('Malformed native coverage receipt')
        receipt = dict(zip(('fragments','calls','operations','code_bytes','compilation_ns'),map(int,fields[2:])))
    return dict(execution=parse_candidate('\n'.join(lines)+'\n',guest), native=receipt, control=control_receipt)


def dirty_loop_witness(output, mode):
    """Require full checked boundaries and an activated owner before crediting native loop coverage."""
    if mode not in ('native', 'refused', 'interpreted'):
        raise ValueError('Unknown dirty-loop witness mode')
    lines = output.splitlines()
    if lines.count('ARM_DIRTY_LOOP_CONTROL_CASES,840') != 1 or \
            lines.count('ARM_DIRTY_LOOP_ALIAS_REFUSAL,1') != 1:
        raise ValueError('Missing guarded dirty-loop boundary or alias controls')
    owner_count = lines.count('ARM_DIRTY_LOOP_OWNER,1')
    if owner_count != (0 if mode == 'interpreted' else 1):
        raise ValueError('Missing active dirty-loop owner lifetime witness')
    word_controls = lines.count('ARM_WORD_CONTROL_CASES,698')
    if word_controls != (0 if mode == 'interpreted' else 1):
        raise ValueError('Missing native word-loop boundary witness')
    word_aliases = lines.count('ARM_WORD_ALIAS_CASES,110')
    if word_aliases != (0 if mode == 'interpreted' else 1):
        raise ValueError('Missing native word-loop alias witness')
    word_owner = lines.count('ARM_WORD_OWNER,1')
    if word_owner != (0 if mode == 'interpreted' else 1):
        raise ValueError('Missing native word-loop owner lifetime witness')
    word_groups = [line.split(',') for line in lines if line.startswith('ARM_WORD_GROUPS,')]
    if mode == 'interpreted':
        if word_groups: raise ValueError('Interpreted witness claimed native word groups')
    else:
        if (len(word_groups) != 1 or len(word_groups[0]) != 2 or
                not word_groups[0][1].isascii() or not word_groups[0][1].isdecimal() or
                int(word_groups[0][1]) >= 2**63):
            raise ValueError('Missing or malformed native word-group receipt')
        groups = int(word_groups[0][1])
        if (mode == 'native' and groups == 0) or (mode == 'refused' and groups != 0):
            raise ValueError('Native word-group activity disagrees with execution mode')
    loops = [line.split(',') for line in lines if line.startswith('ARM_DIRTY_LOOP,')]
    if mode != 'native':
        if loops: raise ValueError('Checked or refused execution entered dirty-loop code')
        return None
    if len(loops) != 1 or len(loops[0]) != 4 or any(not value.isascii() or
            not value.isdecimal() or int(value) >= 2**63 for value in loops[0][1:]):
        raise ValueError('Missing active dirty-loop call/block/decline receipt')
    calls, blocks, declines = map(int, loops[0][1:])
    if calls == 0 or blocks <= calls or declines == 0 or declines > calls:
        raise ValueError('Guarded dirty-loop did not retain resident execution')
    return dict(calls=calls, blocks=blocks, declines=declines)


def qualify(checks, compiler, *, native=True):
    """Share native/refusal and checked-fallback gates without enabling ARM64 execution on other hosts."""
    rows = []
    memory = checks.command(['clang','-O2','-Wall','-Wextra','-Werror','-I'+str(ROOT/'native/pvm_jit'),
        ROOT/'tests/performance/pvm_arm64_jit_memory.c','-o',checks.folder/'memory-check'],'memory-build')
    if memory['exit_code']: raise RuntimeError(memory['output'])
    memory = checks.command([checks.folder/'memory-check'],'memory-run')
    expected = ('ARM_MEMORY_OK,1000,capacity,publication,retirement,integer64\n' if native
                else 'ARM_MEMORY_UNAVAILABLE,checked-fallback\n')
    if memory['exit_code'] or memory['output'] != expected:
        raise ValueError('Executable storage controls failed')
    rows.append(memory)
    for name,source,defines in (
        ('witness','tests/performance/pvm_arm64_jit_witness.nim',
            ['pvmArm64Jit','pvmArmDirtyLoopOwnerReceipt'] if native else []),
        ('witness-refused','tests/performance/pvm_arm64_jit_witness.nim',
            ['pvmArm64Jit','pvmArm64JitRefuse','pvmArmDirtyLoopOwnerReceipt']),
        ('region-refusal','tests/unit/state/test_pvm_arm_region_refusal.nim',['pvmArm64Jit','pvmArm64JitRefusalReceipt']),
        ('region-refusal-forced','tests/unit/state/test_pvm_arm_region_refusal.nim',['pvmArm64Jit','pvmArm64JitRefuse','pvmArm64JitRefusalReceipt']),
        ('all-opcodes','tests/unit/codec/test_pvm_stream_all_opcodes.nim',['pvmArm64Jit'] if native else []),
        ('regions-host','tests/unit/codec/test_pvm_stream_regions_and_host.nim',['pvmArm64Jit'] if native else [])):
        # Qualify native execution, explicit OS refusal and the established whole-state boundary suites before timing.
        built,binary=checks.build(compiler,ROOT/source,name,defines=defines,cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if built['exit_code']: raise RuntimeError(built['output'][-3000:])
        checked=checks.command([binary],name+'-run')
        if checked['exit_code']: raise RuntimeError(checked['output'][-3000:])
        if name.startswith('region-refusal'):
            # Require actual native coverage for all three ownership orders, not a silent checked-only pass.
            records=[line.split(',')[1:] for line in checked['output'].splitlines()
                     if line.startswith('ARM_REGION_REFUSAL_NATIVE,')]
            if len(records)!=3 or any(len(row)!=6 or any(not value.isascii() or not value.isdecimal()
                    for value in row) for row in records):
                raise ValueError('Missing ARM candidate-local ownership receipts')
            records=[list(map(int,row)) for row in records]
            if [row[:2] for row in records]!=[[0,0],[0,1],[1,1]]:
                raise ValueError('Changed ARM candidate-local ownership orders')
            positive=native and name=='region-refusal'
            if any(not (row[3]>row[2] and row[4]>row[3] and row[5]>0) if positive else any(row[2:])
                   for row in records):
                raise ValueError('Missing ARM candidate-local publication/execution')
        if name.startswith('witness'):
            for marker,count in [('ARM_SHIFT_PAIR_LITERAL_CASES',64896),('ARM_SHIFT_PAIR_DECLINE_CASES',507)]:
                expected = count if native and name == 'witness' else 0
                if marker+','+str(expected)+'\n' not in checked['output']:
                    raise ValueError('Missing paired-shift controls: '+marker)
            width_expected = 24843 if native and name == 'witness' else 0
            if (native or name == 'witness-refused') and 'ARM_LOAD_WIDTH_LITERAL_CASES,'+str(width_expected)+'\n' not in checked['output']:
                raise ValueError('Missing signed/unsigned guarded-load width literals')
            # Rejected native stores leave meaningful checked-store/native-arithmetic and complete snapshot fallback coverage.
            if 'ARM_STORE_FALLBACK_CONTROL_CASES,43904\n' not in checked['output']:
                raise ValueError('Missing complete checked-store source/gas/host controls')
            if 'ARM_CHECKED_STORE_SECOND_EXIT_CASES,360\n' not in checked['output']:
                raise ValueError('Missing complete native-arithmetic/later checked-store exit controls')
            region_receipts = [line for line in checked['output'].splitlines()
                               if line.startswith('ARM_SELF_REGION_CASES,')]
            if region_receipts != ['ARM_SELF_REGION_CASES,1920']:
                raise ValueError('Missing complete one-block region boundary witness')
            # The CLI result carries only genuine native coverage, not inferred source-shape visits.
            mode = 'refused' if name == 'witness-refused' else 'native' if native else 'interpreted'
            checked['dirty_loop'] = dirty_loop_witness(checked['output'], mode)
        if native and name == 'witness':
            # Genuine two/three-block caches and every inactive charge record must retain exact scalar mismatch refusal.
            matches = [line for line in checked['output'].splitlines()
                       if line.startswith('ARM_REGION_SCALAR_MATCH_CASES,')]
            if matches != ['ARM_REGION_SCALAR_MATCH_CASES,111']:
                raise ValueError('Missing complete scalar region-charge witness')
        checked['build'] = {key:value for key,value in built.items() if key != 'output'}
        if name == 'witness-refused' or (native and name == 'witness'):
            # The existing independent witness must prove real publication/calls or an exact zero-count refusal.
            receipts = [line for line in checked['output'].splitlines() if line.startswith('TRANSFER_STATS,')]
            expected_counts = [1, 2] if name == 'witness' else [0, 0]
            if receipts != ['TRANSFER_STATS,'+','.join(map(str, expected_counts))]:
                raise ValueError('Missing native publication/execution witness: '+name)
            checked['native_publications'], checked['native_calls'] = expected_counts
        rows.append(checked)
    for owner, extra in (('stream', []), ('frame', ['pvmArm64JitFrameOwner'])):
        for moving in (True, False):
            # Lowering must reject the intended duplicate, while an explicit move has an executable positive control.
            name = 'ownership-'+owner+('-move' if moving else '-copy')
            built, binary = checks.build(compiler, ROOT/'tests/performance/pvm_arm64_jit_ownership.nim', name,
                defines=['pvmArm64Jit', *extra, *(['pvmArm64JitRefuse'] if not native else []),
                         *(['pvmArm64JitMoveOwner'] if moving else [])],
                cflags=['-I'+str(ROOT/'native/pvm_jit')])
            if moving:
                if built['exit_code']: raise RuntimeError(built['output'][-2000:])
                checked = checks.command([binary], name+'-run')
                if checked['exit_code'] or checked['output'] != '0\n0\n': raise ValueError('Owner move control failed')
            elif built['exit_code']==0 or "'=dup' is not available for type <Flat" not in built['output']:
                raise ValueError('Missing intended exclusive-owner lowering refusal')
            rows.append(dict(owner=owner, moving=moving, build=built))
    return rows


def main():
    """Build serially before all timing, keep complete receipts and refuse incomplete cohorts."""
    if platform.system() not in ('Darwin','Linux') or platform.machine() not in ('arm64','aarch64'):
        raise SystemExit('This local experiment requires macOS or Linux ARM64')
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--baseline', default=os.environ.get('PVM_JIT_BASELINE'),
        help='Exact previous JIT commit; defaults to the current HEAD as an A/A control')
    baseline = baseline_revision(args.parse_args().baseline)
    BUILD.mkdir(parents=True,exist_ok=True)
    checks = NativeChecks(BUILD)
    compiler, _ = installed()
    report = dict(status='incomplete',platform=platform.platform(),toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),builds=[],controls=[],runs=[])
    report['baseline'] = baseline
    report['comparison_protocol'] = 'matched-control-v1'
    report['sources'] = {}
    result_path = BUILD/'results.json'
    # A failed new invocation must never leave a prior successful report masquerading as this run.
    result_path.write_text(json.dumps(report,indent=2)+'\n')
    summary_path = BUILD/'summary.md'
    summary_path.write_text('Comparison incomplete; no current timing verdict.\n')
    report['qualification'] = qualify(checks, compiler)
    fixtures = prepare_inputs(checks,BUILD/'inputs')
    identities = dict(fixtures['identities'])
    identities[compiler] = digest(compiler)
    # Bind maintained source/helper/header bytes, not just a mutable branch name.
    for parent in ('src','native/pvm_jit'):
        for path in sorted((ROOT/parent).rglob('*')):
            if path.is_file(): identities[path] = digest(path)
    for path in [*sorted((ROOT/'tools').rglob('*.py')),DRIVER,ROOT/'tests/performance/pvm_sieve_clock.h',ROOT/'tests/performance/pvm_arm64_jit_witness.nim',ROOT/'tests/performance/pvm_arm64_jit_memory.c',ROOT/'tests/performance/pvm_arm64_jit_ownership.nim']:
        identities[path] = digest(path)
    images = {}
    for mode in ('interpreter','baseline','jit'):
        canonical = BUILD/'snapshot'
        if canonical.exists(): shutil.rmtree(canonical)
        canonical.mkdir()
        if mode=='baseline':
            # Read only the exact accepted runtime/header tree; never execute helpers from a revision being compared.
            raw=subprocess.check_output(['git','archive',baseline,'src','native/pvm_jit'],cwd=ROOT)
            with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
                for member in archive.getmembers():
                    if not member.isfile(): continue
                    target=canonical/member.name
                    if not target.resolve().is_relative_to(canonical.resolve()): raise ValueError('Foreign archive path')
                    target.parent.mkdir(parents=True,exist_ok=True)
                    target.write_bytes(archive.extractfile(member).read())
        else:
            # Current uncommitted trial bytes are sealed below and later matched to their preserving commit.
            shutil.copytree(ROOT/'src',canonical/'src')
            shutil.copytree(ROOT/'native/pvm_jit',canonical/'native/pvm_jit')
        driver=canonical/'benchmarks/kernel.nim'
        driver.parent.mkdir()
        driver.write_text(snapshot_imports(DRIVER.read_text().replace('../../src/','../src/'),
                                           canonical/'src/pvm'))
        report['sources'][mode]={str(path.relative_to(canonical)):digest(path)
            for path in sorted(canonical.rglob('*')) if path.is_file()}
        pair = []
        for repeat in range(2):
            # The same source/output coordinates and wholly private fresh cache control path-dependent images.
            cache = cache_directory(compiler,BUILD,'engine')
            if cache.exists(): shutil.rmtree(cache)
            row,binary = checks.build(compiler,driver,'engine',defines=(['pvmArm64Jit','pvmArm64JitControlReceipt'] if mode!='interpreter' else []),
                cflags=['-I'+str(ROOT/'tests/performance'),'-I'+str(canonical/'native/pvm_jit')])
            report['builds'].append(dict(mode=mode,repeat=repeat,build={k:v for k,v in row.items() if k!='output'}))
            if row['exit_code']: raise RuntimeError(row['output'][-3000:])
            saved = BUILD/f'{mode}-{repeat}'
            shutil.copy2(binary,saved)
            pair.append(saved)
            identities[saved] = digest(saved)
        if any(digest(canonical/path)!=h for path,h in report['sources'][mode].items()): raise ValueError('Canonical sources changed')
        if pair[0].read_bytes()!=pair[1].read_bytes(): raise ValueError('Fresh equal-image control failed')
        images[mode] = pair[0]
    report['equal_source_control'] = report['sources']['baseline'] == report['sources']['jit']
    if report['equal_source_control']:
        # The diagnostic receipt is identical in both native roles; equal sources must also yield the same executable bytes.
        if images['baseline'].read_bytes()!=images['jit'].read_bytes():
            raise ValueError('Equal native kernel sources produced different role images')

    for order in range(2):
        for guest,limit,data,expected in fixtures['inputs']:
            for mode in (('interpreter','baseline','jit') if order==0 else ('jit','baseline','interpreter')):
                env = dict(os.environ,RAGNAROK_PVM_GUEST=guest,RAGNAROK_PVM_SIEVE_INPUT=str(data),
                    RAGNAROK_PVM_SIEVE_EXPECTED=str(expected),RAGNAROK_PVM_SIEVE_SAMPLES='13',RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0')
                if order==0:
                    # Both unchanged positive execution and active assertion/state refusal controls precede timing.
                    positive = checks.command([images[mode]],f'{guest}-{limit}-{mode}-positive',environment=env)
                    if positive['exit_code']: raise RuntimeError(positive['output'][-2000:])
                    parse(positive['output'],guest,mode!='interpreter',mode!='interpreter')
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
                report['runs'].append(dict(case=guest,limit=limit,order=order,mode=mode,run=run,parsed=parse(run['output'],guest,mode!='interpreter',mode!='interpreter')))
                unchanged(identities)
    if len(report['runs'])!=42 or len(report['controls'])!=63: raise ValueError('Incomplete cohort')
    if sum(r['parsed']['native']['operations'] for r in report['runs'] if r['mode']=='jit')==0:
        raise ValueError('No compiled execution observed')
    report['identities']={str(p.relative_to(ROOT)):h for p,h in identities.items()}
    report['status']='passed'
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['CPU ms, forward / reverse. Retained frames; cold includes compilation and publication.','',
        '| Case | Interpreter reused | Previous JIT | Current JIT | Current / previous | Current / interpreter | JIT cold | Compilation | Native operations / 13 calls |',
        '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for guest,limit,_,_ in fixtures['inputs']:
        columns=[[] for _ in range(8)]
        for order in range(2):
            selected=[r for r in report['runs'] if (r['case'],r['limit'],r['order'])==(guest,limit,order)]
            old=next(r['parsed'] for r in selected if r['mode']=='interpreter')
            prior=next(r['parsed'] for r in selected if r['mode']=='baseline')
            new=next(r['parsed'] for r in selected if r['mode']=='jit')
            old_ns=statistics.median(s['cpu_ns'] for s in old['execution']['samples'][3:])
            new_ns=statistics.median(s['cpu_ns'] for s in new['execution']['samples'][3:])
            prior_ns=statistics.median(s['cpu_ns'] for s in prior['execution']['samples'][3:])
            values=[f'{old_ns/1e6:.3f}',f'{prior_ns/1e6:.3f}',f'{new_ns/1e6:.3f}',f'{new_ns/prior_ns:.3f}',f'{new_ns/old_ns:.3f}',
                f"{new['execution']['samples'][0]['cpu_ns']/1e6:.3f}",f"{new['native']['compilation_ns']/1e6:.3f}",str(new['native']['operations'])]
            for column,value in zip(columns,values): column.append(value)
        lines.append('| '+guest+' '+str(limit)+' | '+' | '.join(' / '.join(c) for c in columns)+' |')
    lines += ['', '| Case | Order | Native conditional branches | Checked direct-header entries |', '|---|---:|---:|---:|']
    for row in report['runs']:
        if row['mode']=='jit':
            counters=row['parsed']['control']
            lines.append(f"| {row['case']} {row['limit']} | {row['order']} | {counters['branches']} | {counters['headers']} |")
    (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))


if __name__=='__main__':
    main()
