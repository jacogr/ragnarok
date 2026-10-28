#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify pinned PVM execution on the declared native CI host; timings remain in separate maintained suites."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from native_checks import NativeChecks, ROOT
from pvm_arm64_jit import qualify
from pvm_benchmark import cpu_model
from setup_nimony import host_pins, installed

BUILD = ROOT/'build/tests/pvm-native'


def architecture(machine):
    """Normalize only supported native host spellings; unknown CPUs never select a fallback silently."""
    names = {'arm64':'arm64', 'aarch64':'arm64', 'ARM64':'arm64',
             'x86_64':'x86_64', 'AMD64':'x86_64', 'X64':'x86_64'}
    if machine not in names:
        raise ValueError('Unsupported PVM host architecture: '+str(machine))
    return names[machine]


def host_identity():
    """Bind actual uname, Python and Actions runner identities before any compiler or executable runs."""
    system, machine = platform.system(), platform.machine()
    uname = subprocess.check_output(['uname', '-sm'], text=True).strip().split()
    if len(uname) != 2 or uname[0] != system or architecture(uname[1]) != architecture(machine):
        raise ValueError('PVM host uname disagreement')
    expected_system = os.environ.get('PVM_CI_SYSTEM', system)
    expected_arch = os.environ.get('PVM_CI_ARCH', architecture(machine))
    if system not in ('Linux', 'Darwin') or system != expected_system or architecture(machine) != expected_arch:
        raise ValueError('PVM runner does not match declared native host')
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        # Hosted runner declarations and actual process identity must agree; a container is not a native perf runner.
        if not os.environ.get('PVM_CI_SYSTEM') or not os.environ.get('PVM_CI_ARCH'):
            raise ValueError('Missing declared PVM CI host')
        if architecture(os.environ.get('RUNNER_ARCH')) != expected_arch:
            raise ValueError('Actions runner architecture disagreement')
        if Path('/.dockerenv').exists() or Path('/run/.containerenv').exists():
            raise ValueError('Container execution cannot qualify native CI performance')
    # ARM /proc metadata often has no "model name"; retain implementer/part/revision, not just "aarch64".
    cpu_details = {}
    cpuinfo = Path('/proc/cpuinfo')
    if system == 'Linux' and cpuinfo.is_file():
        for line in cpuinfo.read_text().splitlines():
            if ':' in line:
                key, value = (part.strip() for part in line.split(':', 1))
                if key in ('model name', 'vendor_id', 'cpu family', 'model', 'stepping',
                           'CPU implementer', 'CPU architecture', 'CPU variant', 'CPU part',
                           'CPU revision', 'Hardware'):
                    cpu_details.setdefault(key, value)
    pins = json.loads((ROOT/'spec/toolchain.json').read_text())
    selected = host_pins(pins, system, machine)
    return dict(system=system, machine=machine, architecture=architecture(machine), uname=uname,
                cpu=cpu_model(), cpu_details=cpu_details, processor=platform.processor(), platform=platform.platform(),
                runner={key:os.environ.get(key) for key in ('RUNNER_NAME','RUNNER_ARCH','ImageOS','ImageVersion')},
                toolchain_platform=selected['platform'], archive=selected['download'])


def qualify_policy(checks):
    """Run maintained owner-policy suites, including forced storage refusal, before starting comparison clocks."""
    rows = []
    for suite in ('pvm_runtime_policy', 'pvm_runtime_policy_refused'):
        checked = checks.command([sys.executable, ROOT/'tools/native_tests.py', '--suite', suite],
                                 suite, timeout=900)
        rows.append(dict(suite=suite, run=checked))
        if checked['exit_code']:
            raise RuntimeError('PVM owner policy qualification failed: '+checked['log'])
    return rows


def run():
    """Retain incomplete evidence on every failure and require all maintained correctness gates before success."""
    BUILD.mkdir(parents=True, exist_ok=True)
    destination = BUILD/'results.json'
    report = dict(status='incomplete')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        report['host'] = host_identity()
        compiler, _ = installed()
        report['compiler_sha256'] = hashlib.sha256(compiler.read_bytes()).hexdigest()
        report['compiler_identity'] = (compiler.parent.parent/'NIGHTLY.txt').read_text()
        report['revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
        paths = [*sorted((ROOT/'src').rglob('*.nim')), *sorted((ROOT/'native/pvm_jit').glob('*')),
                 ROOT/'tools/pvm_arm64_jit.py', ROOT/'tools/pvm_native_ci.py', ROOT/'spec/toolchain.json',
                 *sorted((ROOT/'tests/performance').glob('pvm_arm64_jit*')),
                 ROOT/'tests/unit/codec/test_pvm_stream_all_opcodes.nim',
                 ROOT/'tests/unit/codec/test_pvm_stream_regions_and_host.nim',
                 *sorted((ROOT/'tests/unit/state').glob('test_pvm_runtime_policy*')),
                 *sorted((ROOT/'tools').glob('native_*.py')),
                 *sorted((ROOT/'tools/native_requirements/state').glob('pvm_runtime_policy*.json'))]
        report['sources'] = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in paths if path.is_file()}
        destination.write_text(json.dumps(report, indent=2)+'\n')
        native = report['host']['architecture'] == 'arm64'
        report['coverage'] = 'ARM64 native and forced refusal' if native else 'interpreter and unavailable ARM64 fallback'
        report['qualification'] = qualify(NativeChecks(BUILD), compiler, native=native)
        report['policy_qualification'] = qualify_policy(NativeChecks(BUILD))
        report['policies'] = dict(reference='polkavm-interpreted', independent=['interpreted','jit'],
            native_jit_available=native, jit_unavailable_actual='interpreted')
        report['status'] = 'passed'
    except BaseException as error:
        # Exceptions and interruptions must leave a current failed receipt, never a previous green report.
        report['error'] = str(error)
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    print('PVM native-host correctness passed: '+report['coverage'], flush=True)


if __name__ == '__main__':
    run()
