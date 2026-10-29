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
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-x86-jit'


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
        ('boundaries', 'tests/performance/pvm_arm64_jit_witness.nim', False),
        ('boundaries-refused', 'tests/performance/pvm_arm64_jit_witness.nim', True),
        ('all-opcodes', 'tests/unit/codec/test_pvm_stream_all_opcodes.nim', False),
        ('regions-host', 'tests/unit/codec/test_pvm_stream_regions_and_host.nim', False),
        ('policy', 'tests/unit/state/test_pvm_runtime_policy.nim', False),
        ('policy-refused', 'tests/unit/state/test_pvm_runtime_policy.nim', True)):
        flags = ['pvmX86Jit', *(['pvmX86JitRefuse'] if refused else [])]
        build, binary = checks.build(compiler, ROOT/source, name, defines=flags,
                                     cflags=['-I'+str(ROOT/'native/pvm_jit')])
        if build['exit_code']: raise RuntimeError(build['output'][-3000:])
        run = checks.command([binary], name+'-run', timeout=900)
        if run['exit_code']: raise RuntimeError(run['output'][-3000:])
        if name.startswith('x86-') and ('X86_REGISTER_CASES,2120\n' not in run['output'] or
                'X86_PREFIX_CASES,2984\n' not in run['output'] or
                'X86_HIGH_LITERAL_CASES,2070\n' not in run['output'] or
                'X86_BRANCH_LITERAL_CASES,1296\n' not in run['output'] or
                'X86_BRANCH_PREFIX_CASES,540\n' not in run['output'] or
                'X86_REGION_PREFIX_CASES,1440\n' not in run['output'] or 'X86_CACHE_REUSE_OK\n' not in run['output']):
            raise ValueError('incomplete native x86 scalar/cache witness')
        if name.startswith('x86-'):
            for marker,count in [('X86_COMPACT_REGION_TAG_CASES',52),('X86_COMPACT_SPAN_BOUNDARY_CASES',5)]:
                expected = 0 if refused else count
                if marker+','+str(expected)+'\n' not in run['output']:
                    raise ValueError('Missing compact source-proof controls: '+marker)
            # The new context oracle must execute on native storage; refused builds retain the existing full fallback matrix.
            expected = 0 if refused else 1440
            if 'X86_RESIDENT_CONTEXT_CASES,'+str(expected)+'\n' not in run['output']:
                raise ValueError('incomplete resident x86 context witness')
        if name.startswith('x86-'):
            # Native literals prove both compact width boundaries and arbitrary64 fallback; refusal must execute no native cases.
            expected = 0 if refused else 3168
            if 'X86_COMPACT_IMMEDIATE_CASES,'+str(expected)+'\n' not in run['output']:
                raise ValueError('incomplete compact immediate witness')
        if name.startswith('x86-'):
            # Independent whole-region arithmetic covers the restored emitter together with exact source/gas context.
            expected = 0 if refused else 2120
            if 'X86_REGION_ARITHMETIC_CASES,'+str(expected)+'\n' not in run['output']:
                raise ValueError('incomplete whole-region arithmetic witness')
        if name.startswith('x86-'):
            # Three-block source controls include refused builds; raw native contexts/publication require executable ownership.
            for marker,count in [('X86_THREE_CONTEXT_CASES',720),('X86_RESERVED_REGION_CASES',1),('X86_REGION_PROMOTION_CONTEXTS',2),('X86_FULL_PROMOTION_REFUSAL_CASES',1)]:
                expected = 0 if refused else count
                if marker+','+str(expected)+'\n' not in run['output']:
                    raise ValueError('incomplete three-block native controls: '+marker)
            if 'X86_REGION_PROMOTION_SOURCE_CASES,6\n' not in run['output']:
                raise ValueError('Missing cold-to-hot region promotion source controls')
            if 'X86_THREE_SOURCE_CASES,3546\n' not in run['output']:
                raise ValueError('incomplete independent three-block source/gas/pricing controls')
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
            'Arithmetic-only opt-in prototype; production x86 default and ARM64 engine remain unchanged.',
            'No performance claim; every native gate has an independent state/refusal witness.', '']
        lines += ['- '+row['name'] for row in report['qualification']]
        if report.get('error'): lines += ['', 'Failure: '+report['error']]
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')


if __name__ == '__main__':
    run()
