#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Attribute host, memory and arithmetic public calls in the original canonical synthetic image.

Each policy executes the unchanged eleven-owner, 143-call process on its measured Linux x86 host.
Return dumps select cold/reused cases afterward; clocks are discarded. No case filter, rebuilt
image, readiness wait or backend substitution can change the shared runtime's admission context.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

from native_checks import NativeChecks, ROOT
from pvm_benchmark_report import NAMES
from pvm_ci_performance import execution_environment
from pvm_guest_compare import unchanged
from pvm_instruction_profile import (calibrate_scope, collect, exclusive_costs, final_return_dump, profile_counts,
                                     validate_return_dump_identity)
from pvm_native_ci import host_identity
from pvm_native_samples import match_measured_native_invocations, validate_native_sample_totals
from pvm_performance_report import validate_current_report
from pvm_performance_synthetic import parse_synthetic
from pvm_x86_jit_profile import canonical_source_identity, canonical_tooling_seals, selected_symbol


def canonical_synthetic_plan(cohort, revision):
    """Bind both complete processes to the passed cohort, exact checked recipe and sealed inputs."""
    validate_current_report(cohort)
    if (re.fullmatch('[0-9a-f]{40}', revision) is None or cohort['revision'] != revision
            or cohort['architecture'] != 'x86_64' or cohort['scope'] != 'all'):
        raise ValueError('Canonical synthetic source, architecture or scope disagreement')
    identity = cohort['identity']
    files = identity['files']
    drivers = [Path(name) for name in files if name.endswith('/tests/performance/pvm_workload.nim')]
    if len(drivers) != 1 or not drivers[0].is_absolute():
        raise ValueError('Missing or ambiguous canonical synthetic source root')
    source = drivers[0].parents[2]
    build, = [row for row in cohort['builds'] if row['family'] == 'synthetic']
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld', '-d:pvmX86Jit',
             '--passC:-I'+str(source/'tests/performance'),
             '--passC:-I'+str(source/'native/pvm_jit')]
    command = build['run']['command']
    if (len(command) != len(flags)+5 or command[1:2] != ['c'] or command[2:-3] != flags
            or not command[-3].startswith('--nimcache:')
            or command[-2:] != ['--out:'+build['binary'], str(drivers[0])]
            or files.get(command[0]) != identity['compiler']['sha256']
            or not isinstance(identity.get('clang'), str) or not identity['clang'].strip()
            or not isinstance(identity.get('build_environment'), dict)):
        raise ValueError('Canonical synthetic checked build recipe disagreement')
    processes = []
    for role in ('interpreted', 'jit'):
        # Every owner belongs to one original process; do not create a new process per selected case.
        rows = []
        for index, name in enumerate(NAMES):
            measured, = [row for row in cohort['runs'] if
                         (row['case_id'], row['role'], row['order']) == (name, role, 0)]
            parsed = measured['parsed']
            native = validate_native_sample_totals(parsed['diagnostics']['scope_observations'],
                parsed['native'], role, 'synthetic-'+str(index))
            if native is None:
                raise ValueError('Canonical synthetic has no per-invocation native evidence')
            rows.append(dict(case=name, native_samples=native, policy=parsed['policy'],
                             run=measured['run']))
        env = rows[0]['run']['benchmark_environment']
        fixture = Path(env.get('RAGNAROK_PVM_BENCHMARK', ''))
        environment = dict(RAGNAROK_PVM_BACKEND=role, RAGNAROK_PVM_PERFORMANCE='1',
            RAGNAROK_PVM_BENCHMARK=str(fixture), RAGNAROK_PVM_PRICING='prepared',
            RAGNAROK_PVM_BENCH_ASSERT_PROBE='0')
        if (not fixture.is_absolute() or str(fixture) not in files or env != environment
                or rows[0]['run']['command'] != [build['binary']]
                or any(row['run'] != rows[0]['run'] for row in rows)):
            raise ValueError('Canonical synthetic invocation recipe disagreement')
        processes.append(dict(role=role, rows=rows, environment=environment,
                              inputs={str(fixture): files[str(fixture)]}))
    return dict(revision=revision, source_root=str(source), build=build, processes=processes,
        compiler=identity['compiler'], clang=identity['clang'], toolchain=identity['toolchain'],
        build_environment=identity['build_environment'])


def synthetic_profile_observations(process, parsed, scope, binary, folder):
    """Qualify every owner in one complete original process, retaining explicit attribution refusals.

    Callers supply the full strict wire parser's output and a canonical plan. Every raw part and
    embedded identity is required before selecting any owner. A compiler-scheduling disagreement
    refuses that owner's attribution; it never removes a call or turns a partial report into a pass.
    This pure reader also permits stricter replay of already collected original evidence.
    """
    role = process['role']
    if [row['case'] for row in process['rows']] != list(NAMES) or set(parsed) != set(NAMES):
        raise ValueError('Incomplete synthetic process owner inventory')
    name = 'synthetic-'+role
    output = folder/(name+'.callgrind')
    final_return_dump(output, 13, owners=len(NAMES))
    validate_return_dump_identity(output, 13*len(NAMES), scope, binary)
    hashes = {part.name: hashlib.sha256(part.read_bytes()).hexdigest()
              for part in sorted(folder.glob(name+'.callgrind*'))}
    profiles, refusals = [], []
    for index, row in enumerate(process['rows']):
        # All raw/wire calls remain present even when one measured native schedule cannot be reproduced.
        value = parsed[row['case']]
        observed = validate_native_sample_totals(value['diagnostics']['scope_observations'],
            value['native'], role, 'synthetic-'+str(index))
        if observed is None:
            raise ValueError('Profiled synthetic has no per-invocation native evidence')
        try:
            if value['policy']['actual'] != row['policy']['actual']:
                raise ValueError('Profiled synthetic changed actual backend')
            comparison = match_measured_native_invocations(row['native_samples'], observed, role)
        except ValueError as error:
            # Fail the overall report after recording every owner; do not lose later memory evidence.
            refusals.append(dict(case=row['case'], role=role, reason=str(error),
                canonical_native_samples=row['native_samples'], profiled_native_samples=observed))
            continue
        parts = [folder/(name+'.callgrind.'+str(index*13+offset)) for offset in (1, 13)]
        texts = [part.read_text() for part in parts]
        costs = [exclusive_costs(text) for text in texts]
        profiles.append(dict(case=row['case'], role=role, checked_calls=143, scope=scope,
            native=value['native'], policy=value['policy'], native_comparison=comparison,
            actual_by_phase={phase: 'jit' if comparison[phase]['operations'] else 'interpreted'
                             for phase in ('cold', 'reused')},
            cold=profile_counts(texts[0]), reused=profile_counts(texts[1]),
            cold_self_costs=costs[0], self_costs=costs[1],
            selected_parts={phase: part.name for phase, part in zip(('cold', 'reused'), parts)},
            profile_hashes=hashes, inputs=process['inputs']))
    return profiles, refusals


def profile_current_synthetic(cohort_path, revision, folder=None):
    """Retain partial evidence on failure; only the original image on its measured CI host may run."""
    folder = Path(folder or ROOT/'build/tests/pvm-synthetic-profile')
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'synthetic-results.json'
    report = dict(schema='pvm-canonical-synthetic-profile-v1', status='incomplete',
        clock_policy='discarded', hardware_counters=False, boundary_protocol='symbol-returns-v1',
        thread_scheduling='fair-required', scheduling_quantum=1000,
        scope='one public execute/executeWithHost: restoration, scalar callbacks/resumes and '
              'owned publication; excludes constructor, startup and independent driver oracles',
        image_authority='original-sealed-image', native_activity_authority='per-invocation-v1',
        controls=[], builds=[], profiles=[], refusals=[])
    try:
        # Foreign hosts and development shells cannot reach calibration or the retained image.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Current synthetic profiles are CI-only')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise ValueError('Current synthetic profiles require native Linux x86_64')
        path = Path(cohort_path)
        seals = {path: hashlib.sha256(path.read_bytes()).hexdigest(), **canonical_tooling_seals()}
        seals[Path(__file__).resolve()] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        cohort = json.loads(path.read_text())
        if host != cohort['identity']['host']:
            raise ValueError('Synthetic profile host differs from the canonical runner instance')
        plan = canonical_synthetic_plan(cohort, revision)
        source = canonical_source_identity(cohort, plan)
        binary = Path(plan['build']['binary'])
        if not binary.is_file():
            raise ValueError('Original sealed synthetic image is absent; implicit rebuilds are forbidden')
        seals[binary] = plan['build']['binary_sha256']
        for process in plan['processes']:
            seals.update({Path(name): value for name, value in process['inputs'].items()})
        if any(member.is_symlink() for member in seals):
            raise ValueError('Redirected canonical synthetic diagnostic input')
        unchanged(seals)
        report.update(host=host, source=source, image=plan['build'], compiler=plan['compiler'],
            clang=plan['clang'], toolchain=plan['toolchain'],
            build_environment=plan['build_environment'], files={str(k): v for k, v in seals.items()})
        checks = NativeChecks(folder)
        original = checks.command

        def command(arguments, name, **options):
            """Guard every tool/process call with original seals and fair async-compiler scheduling."""
            unchanged(seals)
            arguments = list(arguments)
            if arguments[:2] == ['valgrind', '--tool=callgrind']:
                arguments[1:1] = ['--fair-sched=yes', '--scheduling-quantum=1000']
            options.setdefault('environment', execution_environment())
            result = original(arguments, 'synthetic-'+name, **options)
            unchanged(seals)
            if result['exit_code']:
                raise RuntimeError('Current synthetic profile command failed: '+name)
            return result

        checks.command = command
        version = command(['valgrind', '--version'], 'version')['output']
        if re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version.strip()
        calibrate_scope(checks, report)
        scope = selected_symbol(command(['nm', '--defined-only', binary], 'symbols')['output'],
                                'runPreparedSynthetic')
        for process in plan['processes']:
            # The complete eleven-owner process keeps the original cross-case runtime context.
            role = process['role']
            name = 'synthetic-'+role
            executed, final = collect(checks, binary, name, scope,
                execution_environment(**process['environment']), 1800,
                dump_symbols=(scope,), executions=13, owners=len(NAMES))
            parsed = parse_synthetic(executed['output'], role, require_full=True)
            profiles, refusals = synthetic_profile_observations(process, parsed, scope, binary, folder)
            report['refusals'].extend(refusals)
            for row in profiles:
                # Only independently qualified attribution gets annotations; the failed owner stays explicit.
                final = folder/row['selected_parts']['reused']
                command(['callgrind_annotate', '--auto=no', '--inclusive=yes', '--tree=both',
                         '--threshold=95', '--show=Ir', final], role+'-'+row['case']+'-arcs')
                row['run'] = {key: executed[key] for key in ('command', 'exit_code', 'log')}
                report['profiles'].append(row)
                destination.write_text(json.dumps(report, indent=2)+'\n')
        unchanged(seals)
        if report['refusals']:
            raise ValueError('; '.join(row['case']+': '+row['reason'] for row in report['refusals']))
        report['status'] = 'passed'
    except BaseException as error:
        # Preserve the precise failed collection and raw parts instead of emitting qualified attribution.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--revision', required=True)
    options = parser.parse_args()
    profile_current_synthetic(options.report, options.revision)
