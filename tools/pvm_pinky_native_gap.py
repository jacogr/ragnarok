#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Measure Pinky against the pinned reference and attribute current native handoffs."""

from itertools import permutations
import json
from pathlib import Path
import platform
from statistics import median
import subprocess

from native_checks import NativeChecks
from pvm_benchmark import CRATE, TARGET
from pvm_ci_performance import ROOT, PerformanceRunner, digest, execution_environment
from pvm_instruction_profile import calibrate_scope, collect, exclusive_costs, profile_counts
from pvm_jit_platform import native_defines
from pvm_native_samples import match_measured_native_invocations, validate_native_sample_totals
from pvm_polkavm_report import parse as parse_polkavm, parse_clock_control
from pvm_sieve_benchmark import verify_fixture
from pvm_x86_jit_profile import selected_symbol
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-performance'
MASTER = 'e0704df6eb893e4e0c4eb06a0e5ac9c874e210c0'
CASE = 'pinky-1'
PACKAGE = 'ragnarok-pvm-benchmark'
SCOPE_HEADER = 'PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu'
HANDOFF = ('nativeFusionExit', 'checkNativeFusionExit', 'flatFusionEntry',
           'runFlatFusionSegment', 'enterNativeFusion')


def prepare(runner, report):
    """Keep the application image and guest inputs identical to the ordinary checked build."""
    changed = subprocess.check_output([
        'git', 'diff', '--name-only', MASTER, '--', 'src', 'native/pvm_jit', 'spec',
        'tests/performance/pvm_sieve.nim', 'tests/performance/pvm_sieve_clock.h',
        'tests/performance/pvm_invocation_scope.nim', 'tests/fixtures'],
        cwd=ROOT, text=True)
    if changed.strip():
        raise RuntimeError('Application runtime, fixture or driver differs from master')
    runner.rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    reference_root = runner.reference_build(CRATE, TARGET, PACKAGE)
    verify_fixture(upstream=reference_root, guest='pinky')
    fixture = ROOT/'tests/fixtures/pvm-pinky/pinky.polkavm'
    destination = BUILD/'inputs/pinky/1'
    reference = TARGET/'release'/PACKAGE
    runner.references['micro'] = reference
    runner.command([reference, '--sieve-prepare', fixture, destination, '1', '1'],
                   'pinky-prepare', execution_environment(RAGNAROK_PVM_GUEST='pinky'))
    inputs = (destination/'input-1.bin', destination/'expected-1.bin')
    runner.inputs[CASE] = inputs
    runner.seal([reference, fixture, *inputs])
    runner.compiler = installed()[0]
    runner.defines = native_defines()
    runner.build_images()
    report['inputs'] = {path.name: digest(path) for path in (fixture, *inputs)}
    report['image_sha256'] = {name: digest(path) for name, path in
                              [('ragnarok', runner.images['guest']), ('polkavm', reference)]}
    report['builds'] = runner.report['builds']
    report['polkavm_revision'] = runner.report['identity']['reference_revision']


def compiler_mode(environment):
    """Explicitly request the pinned sandboxed compiler for this reference call only."""
    return dict(environment, RAGNAROK_PVM_REFERENCE_BACKEND='compiler')


def compiler_samples(output):
    """Admit results only after actual compiled code and separately measured worker CPU."""
    lines = output.splitlines()
    if lines.count(SCOPE_HEADER) != 1:
        raise ValueError('Missing full native reference invocation boundary')
    # Full-call lifecycle lines are separate from the existing module and task-clock receipts.
    ancillary = ('PVM_MEASURE_SCOPE,', 'PVM_RUNTIME_OWNER,', 'PVM_RUNTIME_CLOSE,',
                 'PVM_OWNER_WINDOW,')
    core = '\n'.join(line for line in lines if not line.startswith(ancillary))
    return parse_polkavm(core, 'compiler', 'pinky', 1)[CASE]


def native_receipts(parsed):
    """Require this run's real per-invocation published native work."""
    receipt = validate_native_sample_totals(parsed['diagnostics']['scope_observations'],
                                            parsed['native'], 'jit', 'guest-process')
    if receipt is None or receipt['samples'][-1]['operations'] <= 0:
        raise ValueError('Missing real native Pinky work')
    return receipt


def controls(runner, case, compiled, report):
    """Use the established backend/clock and tampered-state refusal controls."""
    for role in ('jit', 'reference'):
        runner.controls(case, role)
    report['controls'].extend(runner.report['controls'])
    if not compiled:
        return
    reference = runner.references['micro']
    env = execution_environment(RAGNAROK_PVM_CLOCK_CONTROL='parent')
    clock = runner.command([reference, 'worker-clock-control'], 'pinky-worker-clock', env)
    report['worker_clock'] = parse_clock_control(clock['output'])
    args, env, expected = runner.invocation(case, 'reference')
    invalid = BUILD/'compiler-bad-input'
    invalid.mkdir()
    original, _ = runner.inputs[CASE]
    (invalid/original.name).write_bytes(original.read_bytes())
    broken = bytearray(expected.read_bytes())
    broken[-1] ^= 1
    (invalid/expected.name).write_bytes(broken)
    bad_args = list(args)
    bad_args[3] = invalid
    refused = runner.command(bad_args, 'pinky-compiler-refusal', compiler_mode(env),
                             expected_failure=True)
    if ('sieve terminal state mismatch' not in refused['output']
            or 'REFERENCE_CPU,' in refused['output']):
        raise RuntimeError('Compiled Pinky did not enforce its complete state oracle')
    report['compiler_tampered_state_refused'] = True


def benchmark(runner, case, compiled, report):
    """Use every process order equally and preserve each accepted uninstrumented call."""
    roles = ('jit', 'reference', 'compiler') if compiled else ('jit', 'reference')
    orders = tuple(permutations(roles))
    if not compiled:
        orders *= 3
    for pair, order in enumerate(orders):
        for role in order:
            args, env, _ = runner.invocation(case, 'reference' if role == 'compiler' else role)
            if role == 'compiler':
                env = compiler_mode(env)
            label = f'pinky-{pair}-{role}'
            result = runner.command(args, label, env)
            if role == 'compiler':
                parsed = compiler_samples(result['output'])
            else:
                parsed = runner.parse(result['output'], case, role)[CASE]
                if role == 'jit':
                    if parsed['policy']['actual'] != 'jit':
                        raise RuntimeError('Pinky benchmark used interpreted fallback')
                    native_receipts(parsed)
            wire = parsed['samples'] if role == 'compiler' else parsed['invocation']['samples']
            if len(wire) != 13 or any(row['cpu_ns'] <= 0 or row['wall_ns'] <= 0 for row in wire):
                raise RuntimeError('Incomplete Pinky process timing')
            report['runs'].append(dict(pair=pair, order=order, role=role, samples=wire,
                                       result=parsed, log=result['log']))
        print(f'Completed Pinky timing order {pair+1}/{len(orders)}', flush=True)


def profile(runner, case, report):
    """Attribute the same checked executable after timing, with matched native work receipts."""
    symbols = runner.command(['nm', '--defined-only', runner.images['guest']], 'pinky-symbols')
    scope = selected_symbol(symbols['output'], 'runPreparedKernel')
    args, env, _ = runner.invocation(case, 'jit')
    version = runner.command(['valgrind', '--version'], 'version')
    report['valgrind'] = version['output'].strip()
    checks = NativeChecks(BUILD)
    command = checks.command

    def fair_command(arguments, name, **options):
        """Keep the asynchronous compiler runnable while collecting exact guest scopes."""
        runner.verify()
        if arguments[:2] == ['valgrind', '--tool=callgrind']:
            arguments = [arguments[0], '--fair-sched=yes', '--scheduling-quantum=1000',
                         *arguments[1:]]
        result = command(arguments, name, **options)
        runner.verify()
        return result

    checks.command = fair_command
    calibrate_scope(checks, report)
    raw, final = collect(checks, args[0], 'pinky-jit', scope, env, 900,
                         dump_symbols=(scope,), executions=13)
    if raw['exit_code']:
        raise RuntimeError('Callgrind guest failed: '+raw['log'])
    parsed = runner.parse(raw['output'], case, 'jit')[CASE]
    observed = native_receipts(parsed)
    comparisons = []
    for row in report['runs']:
        if row['role'] != 'jit':
            continue
        measured = native_receipts(row['result'])
        try:
            work = match_measured_native_invocations(measured, observed, 'jit')
        except ValueError as exc:
            comparisons.append(str(exc))
            continue
        report['profile_match'] = dict(pair=row['pair'], work=work)
        break
    else:
        raise RuntimeError('Profile and timing native work differ: '+str(comparisons))
    report['profile'] = {}
    for name, raw_profile in [('cold', BUILD/'pinky-jit.callgrind.1'), ('reuse', final)]:
        content = raw_profile.read_text()
        costs = exclusive_costs(content)
        counts = profile_counts(content)
        groups = {symbol: sum(x['Ir'] for k, x in costs.items()
                              if k.split('_', 1)[0] == symbol) for symbol in HANDOFF}
        report['profile'][name] = dict(
            counts=counts, exclusive_instructions=groups,
            top=sorted(((k, v['Ir']) for k, v in costs.items()), key=lambda k: -k[1])[:30],
            raw_sha256=digest(raw_profile),
            share=sum(groups.values())/counts['Ir'])


def summarize(report):
    """Report the matched warm CPU and wall boundaries independently."""
    analyses = {}
    rows = ['# Same-runner Pinky warm public calls', '',
            '| Backend | Warm CPU (ms) | Warm wall (ms) | CPU vs interpreter |',
            '| --- | ---: | ---: | ---: |']
    indexed = {(r['pair'], r['role']): r['samples'] for r in report['runs']}
    pairs = sorted({r['pair'] for r in report['runs']})
    roles = list(dict.fromkeys(r['role'] for r in report['runs']))
    warm = lambda rows, clock: median(r[clock] for r in rows[3:])
    for role in roles:
        phase = {}
        for clock in ('cpu_ns', 'wall_ns'):
            cells = [warm(indexed[pair, role], clock) for pair in pairs]
            factors = [value/warm(indexed[pair, 'reference'], clock)
                       for pair, value in zip(pairs, cells)]
            phase[clock] = dict(median_ns=median(cells), paired_median_factor=median(factors),
                                per_pair_ns=cells, per_pair_factor=factors)
        analyses[role] = phase
        cpu, wall = (phase[k]['median_ns']/1e6 for k in ('cpu_ns', 'wall_ns'))
        rows.append(f"| {role} | {cpu:.3f} | {wall:.3f} | {phase['cpu_ns']['paired_median_factor']:.4f} |")
    if 'compiler' in roles:
        direct = {clock: median(warm(indexed[pair, 'jit'], clock)/
                               warm(indexed[pair, 'compiler'], clock) for pair in pairs)
                  for clock in ('cpu_ns', 'wall_ns')}
        report['jit_over_compiler'] = direct
        rows += ['', f"JIT / pinned compiler: {direct['cpu_ns']:.3f}× CPU, "
                    f"{direct['wall_ns']:.3f}× wall."]
    if 'profile' in report:
        warm_profile = report['profile']['reuse']
        rows += ['', f"Warm handoff group: {warm_profile['share']:.2%} of sampled "
                    'Callgrind instructions (exclusive costs).']
    report['warm'] = analyses
    (BUILD/'summary.md').write_text('\n'.join(rows)+'\n')


def main():
    """Keep timings independently readable even if the subsequent attribution fails."""
    BUILD.mkdir(parents=True, exist_ok=True)
    result = BUILD/'pinky-native-gap.json'
    report = dict(status='incomplete', architecture=platform.machine(), runtime=MASTER,
                  controls=[], runs=[], cpu_model=next((line.split(':', 1)[1].strip()
                      for line in Path('/proc/cpuinfo').read_text().splitlines()
                      if line.startswith('model name')), 'unavailable'))
    try:
        runner = PerformanceRunner(BUILD, 'micro')
        runner.cases = [row for row in runner.cases if row['case_id'] == CASE]
        case, = runner.cases
        compiled = platform.machine() == 'x86_64'
        prepare(runner, report)
        controls(runner, case, compiled, report)
        benchmark(runner, case, compiled, report)
        summarize(report)
        report['status'] = 'timing-passed'
        result.write_text(json.dumps(report, indent=2)+'\n')
        profile(runner, case, report)
        runner.verify()
        summarize(report)
        report['status'] = 'passed'
    except BaseException as exc:
        report.update(error=str(exc))
        raise
    finally:
        result.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
