#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Calibrate AddressSanitizer before replaying selected frozen PVM corpora with unchanged checks/allocator."""
import hashlib
import json
import os
import platform

from native_checks import NativeChecks, ROOT
from native_tests import NATIVE_REQUIREMENTS, unit_environment, unit_source, unit_static_fixtures, UNIT_SUITES
from setup_nimony import installed

SUITES = ('pvm_conditional_control_reference', 'pvm_jump_table_reference',
          'pvm_memory_access_reference', 'pvm_register_chain_reference', 'pvm_registers',
          'pvm_execution','pvm_prepared_blocks','pvm_host_execution','pvm_host_response',
          *tuple(name for name in UNIT_SUITES if name.startswith('pvm_stream_')))
CONTROLS = (('positive', None), ('heap', 'heap-use-after-free'), ('stack', 'stack-buffer-overflow'))
CFLAGS = ('-fsanitize=address', '-fno-omit-frame-pointer', '-g')
LFLAGS = ('-fsanitize=address',)


def calibration_passed(mode, result):
    """Require the intended instrumented read; a generic crash or missing sanitizer never passes."""
    expected = dict(CONTROLS)[mode]
    output = result['output']
    if expected is None:
        return result['exit_code'] == 0 and output.strip() == 'PVM sanitizer positive passed'
    return (result['exit_code'] != 0 and 'ERROR: AddressSanitizer: '+expected in output
            and 'pvm_sanitizer_read' in output and 'READ of size 1' in output)


def suite_passed(result, expected):
    """Preserve each source-owned output contract and reject even a zero-exit sanitizer diagnostic."""
    return (result['exit_code'] == 0 and 'AddressSanitizer' not in result['output']
            and result['output'].strip() == expected.strip())


def build(checks, compiler, source, name, includes=()):
    """Share the maintained checked native profile and retain exact failed compiler output."""
    row, binary = checks.build(compiler, source, name, cflags=(*CFLAGS, *includes), link_flags=LFLAGS)
    output = row.pop('output')
    (checks.folder/(name+'-build.log')).write_text(output)
    if row['exit_code'] or 'Error:' in output or 'FAILURE' in output:
        raise RuntimeError('sanitizer build failed: '+name)
    row['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    return row, binary


def main():
    """Keep analyzer execution opt-in, sequential, calibrated and separate from ordinary unit verdicts."""
    folder = ROOT/'build/tests/pvm-asan'
    folder.mkdir(parents=True, exist_ok=True)
    report = folder/'results.json'
    report.unlink(missing_ok=True)
    if platform.system() not in ('Darwin', 'Linux'):
        raise RuntimeError('PVM AddressSanitizer qualification requires the maintained macOS/Linux Clang profile')
    checks = NativeChecks(folder, reuse_builds=True)
    compiler, _ = installed()
    environment = dict(os.environ, ASAN_OPTIONS='halt_on_error=1:abort_on_error=0')
    version = checks.command(['clang', '--version'], 'clang-version', environment=environment)
    if version['exit_code']:
        raise RuntimeError('cannot identify sanitizer C compiler')
    # Promoted public suites retain numeric ARC observations as well as in-process assertions.
    evidence = folder/'evidence'
    evidence.mkdir(exist_ok=True)
    for path in evidence.glob('*.json'):
        path.unlink() # This analyzer run owns these files; a fresh refusal cannot reuse old observations.
    builds, controls, suites, sources = [], [], [], {}
    control_source = ROOT/'tests/support/pvm_sanitizer_control.nim'
    row, binary = build(checks, compiler, control_source, 'control', ('-I'+str(control_source.parent),))
    builds.append(row)
    for mode, expected in CONTROLS:
        # Positive calibration is deliberately first; later failures must identify the intended ASan classification and access site.
        result = checks.command([binary], 'control-'+mode, environment={
            **environment, 'RAGNAROK_PVM_SANITIZER_CONTROL': mode}, timeout=30)
        passed = calibration_passed(mode, result)
        result.pop('output')
        controls.append(dict(mode=mode, expected=expected, passed=passed, run=result))
        if not passed:
            raise RuntimeError('sanitizer calibration failed: '+mode)
    for name in SUITES:
        # Reuse source/fixture/output discovery; refuse future linked/generated/defined profiles instead of silently dropping their requirements.
        requirements = NATIVE_REQUIREMENTS[name]
        if requirements['prepared'] or any(requirements[key] for key in ('defines', 'includes', 'libraries', 'observers')):
            raise RuntimeError('unsupported sanitizer corpus profile: '+name)
        source = unit_source(name)
        env = unit_environment(compiler, name=name, base=environment)
        env['RAGNAROK_TEST_EVIDENCE'] = str(folder/'evidence')
        row, binary = build(checks, compiler, source, name)
        builds.append(row)
        result = checks.command([binary], name+'-run', environment=env, timeout=180)
        passed = suite_passed(result, source.with_suffix('.output').read_text())
        result.pop('output')
        fixtures = {str(path.relative_to(ROOT)): expected for _, _, files in unit_static_fixtures(name)
                    for path, expected in files}
        suites.append(dict(name=name, passed=passed, run=result, fixture_sha256=fixtures))
        sources[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
        expected = source.with_suffix('.output')
        sources[str(expected.relative_to(ROOT))] = hashlib.sha256(expected.read_bytes()).hexdigest()
        if not passed:
            raise RuntimeError('sanitized corpus failed: '+name)
        print('PASS AddressSanitizer corpus:', name, flush=True)
    for path in [*sorted((ROOT/'src/pvm').rglob('*.nim')), control_source,
                 control_source.with_suffix('.h'), ROOT/'src/codec/natural.nim',
                 ROOT/'tools/native_checks.py', ROOT/'tools/pvm_sanitizers.py']:
        # Exact source/binary/fixture identities keep this analyzer run distinct from another profile or later tree.
        sources[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    report.write_text(json.dumps(dict(builds=builds, controls=controls, suites=suites,
        source_sha256=sources, cflags=CFLAGS, link_flags=LFLAGS, clang=version, platform=platform.platform(),
        allocator='unchanged pinned native allocator; ASan does not track logical pool suballocations'), indent=2)+'\n')
    print('PASS calibrated PVM AddressSanitizer corpora:', len(suites))


# Importing verdict predicates never provisions tools, builds code or executes intentional failures.
if __name__ == '__main__':
    main()
