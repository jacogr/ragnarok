#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only Linux x86-64 native/refusal, complete-state, ABI/storage and exclusive-owner qualification."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

from native_checks import NativeChecks, ROOT
from pvm_guest_compare import unchanged
from pvm_jit_platform import RESIDENT_PROOF
from pvm_x86_resident_audit import audit_link
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-x86-jit'


def qualify_checked_read_resident(checks, compiler, defines):
    """Require the exact linked sentinel, leaf bytes and transaction before DOOM."""
    if defines != ['pvmX86Jit', RESIDENT_PROOF]:
        raise ValueError('Wrong checked-read resident oracle profile')
    name = 'checked-read-resident-oracle'
    source = ROOT/'tests/performance/pvm_checked_read_resident_witness.nim'
    build, binary = checks.build(compiler, source, name, defines=defines,
                                 cflags=['-I'+str(ROOT/'native/pvm_jit')])
    if build['exit_code'] or 'Error:' in build['output'] or 'FAILURE' in build['output']:
        raise RuntimeError('Resident witness build failed: '+build['log'])
    command = build['command']
    if ([arg for arg in command if arg.startswith('-d:')] !=
            ['-d:release', *('-d:'+flag for flag in defines)]
            or not {'--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin'} <= set(command)):
        raise ValueError('Resident witness build command differs from its checked profile')
    binary_sha256 = hashlib.sha256(binary.read_bytes()).hexdigest()
    abi = audit_link(checks, binary, name)

    env = dict(os.environ)
    variable = 'RAGNAROK_PVM_CHECKED_READ_RESIDENT_DUMP'
    env.pop(variable, None)
    receipts, images = {}, {}
    for mode in ('stack', 'resident', 'six', 'seven', 'seven-stack'):
        dump = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, timeout=30,
                              env={**env, variable:mode})
        digest = hashlib.sha256(dump.stdout).hexdigest()
        receipt = dict(mode=mode, bytes=len(dump.stdout), sha256=digest,
                       binary_sha256=binary_sha256, hex=dump.stdout.hex(),
                       exit_code=dump.returncode, stderr=dump.stderr.decode(errors='replace'))
        (checks.folder/(name+'-'+mode+'.json')).write_text(json.dumps(receipt, indent=2)+'\n')
        if dump.returncode or dump.stderr or not 0 < len(dump.stdout) <= 4096:
            raise ValueError('Resident witness dump failed: '+mode)
        receipts[mode], images[mode] = receipt, dump.stdout

    if (len(images['stack']) != 509 or receipts['stack']['sha256'] !=
            '6f3ac88b10342f2d11cda040aec4f7555d3c8e15f67442303f19aff078f396d2'):
        raise ValueError('Resident witness original stack golden mismatch')
    if (len(images['resident']) != 474 or receipts['resident']['sha256'] !=
            '2f16ca51b7ff9998cd74bffded51edd7c92458d0e0fd95e811e299413a1534b0'):
        raise ValueError('Resident witness modeled leaf mismatch')
    if not images['six'].startswith(bytes.fromhex('53 48 8b 5f 08 55 41 54 4c 8b 67 18 '
                                                  '41 55 41 56 41 57 49 89 f2')):
        raise ValueError('Resident witness six-lane entry mismatch')
    if images['seven'] != images['seven-stack']:
        raise ValueError('Resident witness seven-dirty fallback mismatch')
    if hashlib.sha256(binary.read_bytes()).hexdigest() != binary_sha256:
        raise ValueError('Resident witness binary changed before entry')
    run = checks.command([binary], name+'-run', environment=env, timeout=30)
    if (run['exit_code'] or run['output'] != 'PVM_CHECKED_READ_RESIDENT_OK\n'
            or hashlib.sha256(binary.read_bytes()).hexdigest() != binary_sha256):
        raise ValueError('Resident witness transaction failed: '+run['log'])
    return dict(name=name, status='passed', defines=defines, binary_sha256=binary_sha256,
                abi=abi, dumps=receipts, build=build, run=run)


def qualify(checks, compiler, rows=None):
    """Require native execution and its exact refused twin; successful checked fallback alone cannot pass."""
    rows = [] if rows is None else rows
    compiled = checks.command(['clang', '-O2', '-Wall', '-Wextra', '-Werror',
        '-I'+str(ROOT/'native/pvm_jit'), ROOT/'tests/performance/pvm_x86_jit_memory.c',
        '-o', checks.folder/'memory'], 'memory-build')
    if compiled['exit_code']: raise RuntimeError(compiled['output'][-3000:])
    tested = checks.command([checks.folder/'memory'], 'memory-run')
    if tested['exit_code'] or tested['output'] != 'X86_EXECUTABLE_MEMORY_OK,1000\n':
        raise ValueError('x86 executable-memory control failed')
    rows.append(dict(name='memory', build=compiled, run=tested))
    for name, source, refused in (
        ('x86-native', 'tests/performance/pvm_x86_jit_witness.nim', False),
        ('x86-refused', 'tests/performance/pvm_x86_jit_witness.nim', True),
        ('fragment-cap-native', 'tests/performance/pvm_x86_jit_fragment_cap_witness.nim', False),
        ('fragment-cap-refused', 'tests/performance/pvm_x86_jit_fragment_cap_witness.nim', True),
        ('region-refusal-native', 'tests/unit/state/test_pvm_x86_region_refusal.nim', False),
        ('region-refusal-forced', 'tests/unit/state/test_pvm_x86_region_refusal.nim', True),
        ('boundaries', 'tests/performance/pvm_arm64_jit_witness.nim', False),
        ('boundaries-refused', 'tests/performance/pvm_arm64_jit_witness.nim', True),
        ('all-opcodes', 'tests/unit/codec/test_pvm_stream_all_opcodes.nim', False),
        ('checked-store-native', 'tests/unit/codec/test_pvm_stream_checked_store_loop.nim', False),
        ('checked-store-refused', 'tests/unit/codec/test_pvm_stream_checked_store_loop.nim', True),
        ('checked-read-tiny', 'tests/unit/codec/test_pvm_checked_read_tiny.nim', False),
        ('checked-read-arbitration', 'tests/unit/codec/test_pvm_checked_read_arbitration.nim', False),
        ('regions-host', 'tests/unit/codec/test_pvm_stream_regions_and_host.nim', False),
        ('policy', 'tests/unit/state/test_pvm_runtime_policy.nim', False),
        ('policy-refused', 'tests/unit/state/test_pvm_runtime_policy.nim', True)):
        flags = ['pvmX86Jit', *(['pvmX86JitRefuse'] if refused else []),
                 *(['pvmX86RegionRefusalNativeRequired'] if name == 'region-refusal-native' else []),
                 *(['pvmX86RegionRefusalForcedRequired'] if name == 'region-refusal-forced' else []),
                 *(['pvmX86CheckedStoreReceipt'] if name.startswith('checked-store-') else []),
                 *(['pvmSharedAsyncWitness'] if name == 'checked-read-arbitration' else [])]
        build, binary = checks.build(compiler, ROOT/source, name, defines=flags,
                                     cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if build['exit_code']: raise RuntimeError(build['output'][-3000:])
        run = checks.command([binary], name+'-run', timeout=900)
        if run['exit_code']: raise RuntimeError(run['output'][-3000:])
        if name.startswith('fragment-cap-'):
            # A Linux native run must cross the shared quota; refusal proves allocation failure separately.
            expected = 'X86_FRAGMENT_CAP_FORCED_REFUSAL_OK\n' if refused else 'X86_FRAGMENT_CAP_NATIVE_OK\n'
            if run['output'] != expected:
                raise ValueError('incomplete x86 fragment-cap boundary witness')
        if name.startswith('region-refusal-'):
            for mode in ('native', 'forced'):
                expected = 'X86_REGION_REFUSAL_'+mode.upper()+'_REQUIRED,1\n'
                if (expected in run['output']) != (name == 'region-refusal-'+mode):
                    raise ValueError('wrong x86 region-refusal '+mode+' coverage')
            for marker in ('PASS candidate-local shape and size',
                           'PASS exact eight-visit negative budget',
                           'PASS same-owner rejected then eligible',
                           'PASS genuine publication and physical capacity',
                           'PASS both checked guest orders'):
                records = [line for line in run['output'].splitlines() if line.startswith(marker)]
                if len(records) != 1:
                    raise ValueError('incomplete x86 region-refusal witness: '+marker)
        if name.startswith('checked-store-') and 'X86_CHECKED_STORE_ACTIVE\n' not in run['output']:
            raise ValueError('native-plan checked store loop did not activate')
        if name.startswith('checked-read-') and run['output'] != (ROOT/source).with_suffix('.output').read_text():
            raise ValueError('incomplete x86 checked-read witness: '+name)
        if name.startswith('x86-'):
            # Source cohorts stay checked; raw backend cohorts retain real native/refusal execution.
            expected = (
                ('X86_REGISTER_CASES', 2120), ('X86_PREFIX_CASES', 2984),
                ('X86_HIGH_LITERAL_CASES', 2070), ('X86_BRANCH_LITERAL_CASES', 1296),
                ('X86_BRANCH_PREFIX_CASES', 540), ('X86_REGION_PREFIX_CASES', 1440),
                ('X86_CHECKED_THREE_SOURCE_CASES', 3546), ('X86_EXISTING_ROOT_SOURCE_CASES', 6),
                ('X86_RESIDENT_CONTEXT_CASES', 0 if refused else 1440),
                ('X86_COMPACT_IMMEDIATE_CASES', 0 if refused else 3168),
                ('X86_REGION_ARITHMETIC_CASES', 0 if refused else 2120))
            lines = run['output'].splitlines()
            for marker, count in expected:
                records = [line for line in lines if line.partition(',')[0] == marker]
                if records != [marker+','+str(count)]:
                    raise ValueError('Missing or malformed x86 source/backend cohort: '+marker)
            if lines.count('X86_CHECKED_STREAM_REUSE_OK') != 1:
                raise ValueError('Missing exact checked x86 stream reuse witness')
        rows.append(dict(name=name, build=build, run=run))
    for moving in (True, False):
        # The private owner must disarm actual published authority, and still reject duplication.
        name = 'arena-move' if moving else 'arena-copy'
        build, binary = checks.build(compiler, ROOT/'tests/performance/pvm_x86_jit_arena_owner.nim',
            name, defines=[] if moving else ['pvmX86ArenaCopy'],
            cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if moving:
            if build['exit_code']: raise RuntimeError(build['output'][-3000:])
            run = checks.command([binary], name+'-run')
            if run['exit_code'] or run['output'] != 'X86_ARENA_MOVE_OK,1000\n':
                raise ValueError('published x86 arena move failed')
            rows.append(dict(name=name, build=build, run=run))
        else:
            if build['exit_code'] == 0 or "'=dup' is not available for type <X86Arena>" not in build['output']:
                raise ValueError('missing intended x86 arena-copy lowering refusal')
            rows.append(dict(name=name, build=build))
    for frame in (False, True):
        for moving in (False, True):
            # The same maintained source forces real lowering; unrelated compile failures cannot satisfy ownership.
            name = ('frame' if frame else 'stream')+('-move' if moving else '-copy')
            flags = ['pvmX86Jit', *(['pvmArm64JitFrameOwner'] if frame else []),
                     *(['pvmArm64JitMoveOwner'] if moving else [])]
            build, binary = checks.build(compiler, ROOT/'tests/performance/pvm_arm64_jit_ownership.nim',
                name, defines=flags, cflags=['-I'+str(ROOT/'native/pvm_jit')])
            if moving:
                if build['exit_code']: raise RuntimeError(build['output'][-3000:])
                run = checks.command([binary], name+'-run')
                if run['exit_code'] or run['output'] != '0\n0\n': raise ValueError('x86 owner move failed')
            elif build['exit_code'] == 0 or "'=dup' is not available for type <Flat" not in build['output']:
                raise ValueError('missing intended x86 owner-copy lowering refusal')
            rows.append(dict(name=name, build=build))
    return rows


def run():
    """Keep heavy work on actual CI, with exact compiler/source identities and a durable incomplete verdict."""
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('x86 native qualification is CI-only')
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(status='incomplete', qualification=[])
    def save():
        """An interrupted attempt cannot inherit a previous successful receipt."""
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        from pvm_native_ci import host_identity
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise ValueError('x86 qualification requires actual native Linux x86-64')
        compiler, _ = installed()
        paths = [*sorted((ROOT/'src').rglob('*.nim')), *sorted((ROOT/'native/pvm_jit').glob('*')),
                 *sorted((ROOT/'tests/performance').glob('pvm_*jit*')),
                 *sorted((ROOT/'tests/unit/codec').glob('test_pvm_checked_read_*')),
                 ROOT/'tests/unit/state/test_pvm_x86_region_refusal.nim',
                 ROOT/'tools/pvm_x86_jit.py', ROOT/'tools/native_checks.py', ROOT/'spec/toolchain.json', compiler]
        identities = {p:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()}
        report.update(host=host, revision=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
            compiler_sha256=identities[compiler], toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            identities={str(p.relative_to(ROOT)):value for p,value in identities.items()})
        save()
        qualify(NativeChecks(BUILD), compiler, report['qualification'])
        unchanged(identities)
        report['status'] = 'passed'
    except BaseException as error:
        report['error'] = str(error)
        raise
    finally:
        save()
        lines = ['Linux x86-64 JIT qualification: '+report['status'], '',
            'Checked release/ARC/Clang ThinLTO; same interpreter gas, memory and source-attempt checks.',
            'Native x86-64 controls cover registers, control flow, memory and checked-read bodies.',
            'No performance claim; every native gate has an independent state/refusal witness.', '']
        lines += ['- '+row['name'] for row in report['qualification']]
        if report.get('error'): lines += ['', 'Failure: '+report['error']]
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')


if __name__ == '__main__':
    run()
