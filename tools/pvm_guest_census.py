#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Count checked real-guest instructions in calibrated private snapshots; publish no timings."""
import hashlib
import json
import os

from native_checks import NativeChecks, ROOT
from pvm_guest_inputs import CASES, prepare_inputs
from pvm_opcode_census import build, calibrate, parse_reports, snapshot_sources
from pvm_sieve_report import parse_process_output
from setup_nimony import installed


CAPACITY = 4096


def digest(path):
    """Bind a source, generated state, or binary to the actual bytes read by this run."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def observation(output, mode, guest, limit):
    """Require exactly one completed, full-state-checked invocation and its strict driver protocol."""
    reports, regular = parse_reports(output, CAPACITY)
    engine = {'dynamic': 'ragnarok', 'planned': 'ragnarok_planned', 'memo': 'ragnarok_memo'}[mode]
    parse_process_output(regular, engine, limit, guest, samples=1)
    if len(reports) != 1:
        raise ValueError('real-guest census requires exactly one invocation')
    return reports[0]


def run():
    """Freeze independent inputs, calibrate instrumentation, and compare two fresh runs of every policy."""
    folder = ROOT/'build/tests/pvm-guest-census'
    folder.mkdir(parents=True, exist_ok=True)
    report = folder/'results.json'
    report.unlink(missing_ok=True)
    checks = NativeChecks(folder, reuse_builds=True)
    compiler, _ = installed()
    sources = [ROOT/'tools'/name for name in ('pvm_guest_census.py', 'pvm_guest_inputs.py', 'pvm_opcode_census.py',
        'pvm_sieve_benchmark.py', 'pvm_sieve_report.py', 'pvm_benchmark.py', 'pvm_benchmark_report.py',
        'native_checks.py', 'native_fixture_contracts.py', 'native_dependencies.py')]
    identities = {path: digest(path) for path in sources}
    prepared = prepare_inputs(checks, folder)
    identities.update(prepared['identities'])
    provenance = prepared['provenance']
    original, generated = snapshot_sources(folder/'snapshot',
        (ROOT/'tests/performance/pvm_sieve.nim', ROOT/'tests/performance/pvm_sieve_clock.h'), CAPACITY)
    identities.update({ROOT/path: value for path, value in original.items()})
    builds, controls, runs = list(prepared['builds']), [], list(prepared['preparations'])
    calibrate(checks, compiler, folder/'snapshot', builds, controls)
    row, binary = build(checks, compiler, folder/'snapshot/tests/performance/pvm_sieve.nim', 'guest',
        defines=('pvmOpcodeCensus',), cflags=('-I'+str(folder/'snapshot/tests/performance'),))
    builds.append(row)
    refused = checks.command([binary], 'guest-assertion-control',
        environment=dict(os.environ, RAGNAROK_PVM_GUEST='sieve', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='1'))
    passed = (refused['exit_code'] != 0 and '[Assertion Failure]' in refused['output']
        and 'pvm sieve native assertion control' in refused['output'] and 'census,begin,' not in refused['output'])
    refused.pop('output')
    controls.append(dict(mode='guest-assertions', passed=passed, run=refused))
    if not passed:
        raise RuntimeError('real-guest census assertion control failed')
    reference = prepared['reference']
    binaries = {path: digest(path) for path in (binary, reference)}
    programs = {}
    for guest, limit, data, expected in prepared['inputs']:
        # Prepared states and all pinned provenance are shared with the paired-revision benchmark.
        environment = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
            RAGNAROK_PVM_SIEVE_INPUT=str(data), RAGNAROK_PVM_SIEVE_EXPECTED=str(expected),
            RAGNAROK_PVM_SIEVE_SAMPLES='1')
        key = guest+'/'+str(limit)
        for repeat in range(2):
            for mode in ('dynamic', 'planned', 'memo'):
                # Fresh processes prove reset and policy invariance; timings/preparation observations are discarded.
                result = checks.command([binary], f'{guest}-{limit}-{mode}-{repeat}',
                    environment=dict(environment, RAGNAROK_PVM_PRICING=mode), timeout=300)
                if result['exit_code']:
                    raise RuntimeError('real-guest census execution failed: '+result['log'])
                counted = observation(result['output'], mode, guest, limit)
                if key in programs and programs[key] != counted:
                    raise ValueError('real-guest census differs across fresh runs or pricing policies: '+key)
                programs[key] = counted
                result.pop('output')
                runs.append(dict(guest=guest, limit=limit, mode=mode, repeat=repeat, run=result))
    snapshot = {folder/'snapshot'/path: value for path, value in generated.items()}
    for path, expected in {**identities, **binaries, **snapshot}.items():
        # A concurrent source/fixture/binary mutation invalidates all aggregate evidence, including successful earlier cases.
        if digest(path) != expected:
            raise ValueError('real-guest census input changed during run: '+str(path))
    report.write_text(json.dumps(dict(diagnostic_only=True, instrumented_sample_timings_discarded=True,
        pair_capacity=CAPACITY, validated_invocations=len(CASES)*6, provenance=provenance,
        source_sha256={str(p.relative_to(ROOT)): h for p, h in identities.items()},
        snapshot_sha256=generated, binary_sha256={str(p.relative_to(ROOT)): h for p, h in binaries.items()},
        builds=builds, controls=controls, runs=runs, programs=programs), indent=2)+'\n')
    print('PASS real-guest opcode census: 7 inputs, 42 validated invocations; timings discarded')
    for name, counted in programs.items():
        print(name, counted['steps'], 'PVM instructions;', len(counted['pairs']), 'distinct pairs')


# Importing the validator is pure; Make owns setup and explicit execution.
if __name__ == '__main__':
    run()
