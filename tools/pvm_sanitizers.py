#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Calibrate AddressSanitizer before replaying selected frozen PVM corpora with unchanged checks/allocator."""
import hashlib
import json
import os
import platform
import subprocess

from native_checks import NativeChecks, ROOT
from native_tests import NATIVE_REQUIREMENTS, unit_environment, unit_source, unit_static_fixtures, UNIT_SUITES, ARC_SUITES, unit_evidence
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


def validate_profiles():
    """Refuse incompatible selected suites during inventory preflight, before any compilation."""
    if len(SUITES) != len(set(SUITES)):
        raise ValueError('Duplicate sanitizer suite')
    for name in SUITES:
        # New generated, linked or defined requirements need explicit sanitizer support.
        requirements = NATIVE_REQUIREMENTS[name]
        if requirements['prepared'] or any(requirements[key] for key in ('defines', 'includes', 'libraries', 'observers')):
            raise ValueError('unsupported sanitizer corpus profile: '+name)


def passed(report, names):
    """Require exact selected coverage and all calibration controls from this worker/profile."""
    rows = report.get('suites', [])
    controls = report.get('controls', [])
    return (report.get('status') == 'checks-passed'
            and report.get('selected') == list(names)
            and len(rows) == len(names) and {row.get('name') for row in rows} == set(names)
            and all(row.get('passed') is True for row in rows)
            and [row.get('mode') for row in controls] == [mode for mode, _ in CONTROLS]
            and all(row.get('passed') is True for row in controls)
            and report.get('cflags') == list(CFLAGS) and report.get('link_flags') == list(LFLAGS))


class SanitizerChecks(NativeChecks):
    """Retain partial compiler/process output when the original timeout terminates a task."""

    def command(self, arguments, name, **options):
        """Timeouts remain failures, with durable output rather than discarded capture buffers."""
        try:
            return super().command(arguments, name, **options)
        except subprocess.TimeoutExpired as error:
            # subprocess may provide bytes even for text mode; preserve both captured streams.
            output = ''.join(value.decode(errors='replace') if isinstance(value, bytes) else value or ''
                             for value in (error.stdout, error.stderr))
            (self.folder/(name+'.log')).write_text(output+'\nTIMEOUT: '+str(error)+'\n')
            raise


def run_selected(compiler, names, folder):
    """Calibrate this worker, then replay only its exact scheduled instrumented suite selection."""
    folder.mkdir(parents=True, exist_ok=True)
    report_path = folder/'results.json'
    report_path.unlink(missing_ok=True)
    if platform.system() not in ('Darwin', 'Linux'):
        raise RuntimeError('PVM AddressSanitizer qualification requires the maintained macOS/Linux Clang profile')
    validate_profiles()
    if not names or len(names) != len(set(names)) or not set(names) <= set(SUITES):
        raise ValueError('Invalid sanitizer selection')
    checks = SanitizerChecks(folder, reuse_builds=True)
    environment = dict(os.environ, ASAN_OPTIONS='halt_on_error=1:abort_on_error=0')
    evidence = folder/'evidence'
    evidence.mkdir(exist_ok=True)
    for path in evidence.glob('*.json'):
        # Each invocation retires previous ARC observations before calibration or execution.
        path.unlink()
    report = dict(builds=[], controls=[], suites=[], selected=list(names), status='failed',
                  source_sha256={}, cflags=list(CFLAGS), link_flags=list(LFLAGS),
                  platform=platform.platform(),
                  allocator='unchanged pinned native allocator; ASan does not track logical pool suballocations')
    control_source = ROOT/'tests/support/pvm_sanitizer_control.nim'
    try:
        # Capture exact source/output identities before execution, including failed/partial runs.
        sources = [*sorted((ROOT/'src/pvm').rglob('*.nim')), control_source,
                   control_source.with_suffix('.h'), ROOT/'src/codec/natural.nim',
                   ROOT/'tools/native_checks.py', ROOT/'tools/pvm_sanitizers.py']
        for name in names:
            sources.extend((unit_source(name), unit_source(name).with_suffix('.output')))
        report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                   for path in sources}
        version = checks.command(['clang', '--version'], 'clang-version', environment=environment)
        report['clang'] = version
        if version['exit_code']:
            raise RuntimeError('cannot identify sanitizer C compiler')
        row, binary = build(checks, compiler, control_source, 'control', ('-I'+str(control_source.parent),))
        report['builds'].append(row)
        for mode, expected in CONTROLS:
            # Positive calibration precedes exact heap/stack classified one-byte read failures.
            result = checks.command([binary], 'control-'+mode, environment={
                **environment, 'RAGNAROK_PVM_SANITIZER_CONTROL': mode}, timeout=30)
            valid = calibration_passed(mode, result)
            result.pop('output')
            report['controls'].append(dict(mode=mode, expected=expected, passed=valid, run=result))
            if not valid:
                raise RuntimeError('sanitizer calibration failed: '+mode)
        for name in names:
            # Keep original fixture, expected-output, allocator, assertion and 180-second contracts.
            source = unit_source(name)
            env = unit_environment(compiler, name=name, base=environment)
            env['RAGNAROK_TEST_EVIDENCE'] = str(evidence)
            row, binary = build(checks, compiler, source, name)
            report['builds'].append(row)
            result = checks.command([binary], name+'-run', environment=env, timeout=180)
            valid = suite_passed(result, source.with_suffix('.output').read_text())
            result.pop('output')
            fixtures = {str(path.relative_to(ROOT)): expected for _, _, files in unit_static_fixtures(name)
                        for path, expected in files}
            observed = dict(name=name, passed=valid, run=result, fixture_sha256=fixtures)
            report['suites'].append(observed)
            if valid and name in ARC_SUITES:
                # Instrumented evidence must be fresh, numeric and at baseline in its own folder.
                observed['arc'] = unit_evidence(compiler, name, evidence)
            if not valid:
                raise RuntimeError('sanitized corpus failed: '+name)
            print('PASS AddressSanitizer corpus:', name, flush=True)
        report['status'] = 'checks-passed'
    except Exception as error:
        # Partial controls/suites and all prior logs survive failed builds, runs, fixtures and timeouts.
        report['error'] = str(error)
        print('FAIL AddressSanitizer:', error, flush=True)
    finally:
        # A failed invocation always replaces earlier success with current partial evidence.
        report_path.write_text(json.dumps(report, indent=2)+'\n')
    return report


def main():
    """Keep the standalone local entry point on exactly the same calibrated task executor."""
    folder = ROOT/'build/tests/pvm-asan'
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'results.json').unlink(missing_ok=True)
    if platform.system() not in ('Darwin', 'Linux'):
        raise RuntimeError('PVM AddressSanitizer qualification requires the maintained macOS/Linux Clang profile')
    compiler, _ = installed()
    report = run_selected(compiler, SUITES, folder)
    raise SystemExit(0 if passed(report, SUITES) else 1)


# Importing verdict predicates never provisions tools, builds code or executes intentional failures.
if __name__ == '__main__':
    main()
