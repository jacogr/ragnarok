#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Profile unchanged canonical Sieve and Pinky images on their qualified Linux x86 CI host.

The short Sieve and real Pinky frame cover both policies; large Sieve stays native-only. Complete
original thirteen-call processes retain state/backend checks. Calibrated return dumps
separate the cold public invocation from the final reused call; all profile clocks are discarded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

from native_checks import NativeChecks, ROOT
from pvm_ci_performance import execution_environment, parse_application
from pvm_guest_compare import unchanged
from pvm_instruction_profile import calibrate_scope, collect, profile_counts, exclusive_costs
from pvm_native_ci import host_identity
from pvm_performance_report import validate_current_report
from pvm_x86_jit_profile import (canonical_source_identity, canonical_tooling_seals,
                                 matching_native_activity, selected_symbol)


def canonical_guest_plan(cohort, revision, limits):
    """Require a passed current cohort and exact original image, build recipe and full-call inputs."""
    validate_current_report(cohort)
    if (re.fullmatch('[0-9a-f]{40}', revision) is None or cohort['revision'] != revision
            or cohort['architecture'] != 'x86_64' or cohort['scope'] != 'all'):
        raise ValueError('Canonical guest source, architecture or scope disagreement')
    if not limits or len(set(limits)) != len(limits) or any(
            value not in (100000, 10000000) for value in limits):
        raise ValueError('Unsupported or duplicate Sieve profile sizes')
    identity = cohort['identity']
    files = identity['files']
    drivers = [Path(name) for name in files if name.endswith('/tests/performance/pvm_sieve.nim')]
    if len(drivers) != 1 or not drivers[0].is_absolute():
        raise ValueError('Missing or ambiguous canonical guest source root')
    source = drivers[0].parents[2]
    build, = [row for row in cohort['builds'] if row['family'] == 'guest']
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld',
             '-d:pvmX86Jit', '-d:pvmArm64JitOwnerReceipt',
             '--passC:-I'+str(source/'tests/performance'),
             '--passC:-I'+str(source/'native/pvm_jit')]
    command = build['run']['command']
    if (len(command) != len(flags)+5 or command[1:2] != ['c'] or command[2:-3] != flags
            or not command[-3].startswith('--nimcache:')
            or command[-2:] != ['--out:'+build['binary'], str(drivers[0])]
            or files.get(command[0]) != identity['compiler']['sha256']):
        raise ValueError('Canonical guest checked build recipe disagreement')
    if not isinstance(identity.get('clang'), str) or not identity['clang'].strip() or not isinstance(
            identity.get('build_environment'), dict):
        raise ValueError('Missing canonical compiler or build environment identity')
    rows = []
    selections = [('sieve', limit, role) for limit in limits
                  for role in (('interpreted', 'jit') if limit == 100000 else ('jit',))]
    selections += [('pinky', 1, role) for role in ('interpreted', 'jit')]
    for guest, limit, role in selections:
        # The original order-zero image/inputs are authoritative; no substitute driver is compiled.
        row, = [row for row in cohort['runs'] if (row['case_id'], row['role'], row['order']) ==
                (guest+'-'+str(limit), role, 0)]
        native = row['parsed']['native']
        policy = row['parsed']['policy']
        # These hot inputs must exercise the named backend; fallback cannot attribute native cost.
        if policy['requested'] != role or policy['actual'] != role or (role == 'jit' and any(
                native[key] <= 0 for key in ('fragments', 'calls', 'operations', 'code_bytes'))):
            raise ValueError('Canonical guest did not exercise the selected backend')
        env = row['run']['benchmark_environment']
        data = Path(env.get('RAGNAROK_PVM_SIEVE_INPUT', ''))
        expected = data.parent/('expected-'+str(limit)+'.bin')
        environment = dict(RAGNAROK_PVM_BACKEND=role, RAGNAROK_PVM_PERFORMANCE='1',
            RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_PRICING='prepared',
            RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_CLOCK='1',
            RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
            RAGNAROK_PVM_SIEVE_EXPECTED=str(expected))
        members = [data, expected]
        if guest == 'sieve':
            # Sieve restores an external compact artifact; Pinky's snapshot contains its program.
            artifact = source/'tests/fixtures/pvm-sieve/sieve.polkavm'
            environment['RAGNAROK_PVM_SIEVE_ARTIFACT'] = str(artifact)
            members.append(artifact)
        if (env != environment or not data.is_absolute() or data.name != 'input-'+str(limit)+'.bin'
                or row['run']['command'] != [build['binary']]):
            raise ValueError('Canonical guest invocation recipe disagreement')
        inputs = {str(path): files.get(str(path)) for path in members}
        if any(value is None for value in inputs.values()):
            raise ValueError('Unsealed canonical guest input')
        rows.append(dict(case=guest, limit=limit, role=role, environment=environment,
                         inputs=inputs, native=native))
    return dict(revision=revision, source_root=str(source), build=build, rows=rows,
                compiler=identity['compiler'], clang=identity['clang'], toolchain=identity['toolchain'],
                build_environment=identity['build_environment'])


def profile_current_guest(cohort_path, revision, limits, folder=None):
    """Keep fail-closed partial evidence; only original sealed images on native x86 Linux may execute."""
    folder = Path(folder or ROOT/'build/tests/pvm-guest-profile')
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'results.json'
    report = dict(schema='pvm-canonical-guest-profile-v1', status='incomplete',
        clock_policy='discarded', hardware_counters=False, boundary_protocol='symbol-returns-v1',
        thread_scheduling='fair-required', scheduling_quantum=1000,
        scope='one public execute: private memory construction, native execution and publication; '
              'excludes constructor, runtime startup and complete-state driver oracles',
        image_authority='original-sealed-image', controls=[], builds=[], profiles=[])
    try:
        # No build, calibration or guest work is reachable on a foreign host or outside CI.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Current guest profiles are CI-only')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise ValueError('Current guest profiles require native Linux x86_64')
        path = Path(cohort_path)
        seals = {path: hashlib.sha256(path.read_bytes()).hexdigest(), **canonical_tooling_seals()}
        # Retain this entry point even when invoked from a development path outside tools/.
        seals[Path(__file__).resolve()] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        cohort = json.loads(path.read_text())
        if host != cohort['identity']['host']:
            raise ValueError('Guest profile host differs from the canonical runner instance')
        plan = canonical_guest_plan(cohort, revision, limits)
        source = canonical_source_identity(cohort, plan)
        binary = Path(plan['build']['binary'])
        if not binary.is_file():
            raise ValueError('Original sealed guest image is absent; implicit rebuilds are forbidden')
        seals[binary] = plan['build']['binary_sha256']
        for row in plan['rows']:
            seals.update({Path(name): value for name, value in row['inputs'].items()})
        if any(member.is_symlink() for member in seals):
            raise ValueError('Redirected canonical guest diagnostic input')
        unchanged(seals)
        report.update(host=host, source=source, compiler=plan['compiler'], clang=plan['clang'],
            toolchain=plan['toolchain'], build_environment=plan['build_environment'],
            files={str(name): value for name, value in seals.items()}, image=plan['build'])
        checks = NativeChecks(folder)
        original = checks.command

        def command(arguments, name, **options):
            """Protect every calibration/tool/guest call against live input changes and process failure."""
            unchanged(seals)
            # The async compiler must get CPU time: Valgrind's default pipe scheduler is unfair.
            # Keep all native-activity checks; unavailable fair scheduling is a collection failure.
            arguments = list(arguments)
            if arguments[:2] == ['valgrind', '--tool=callgrind']:
                # Short quanta let a newly queued compiler run between public invocations.
                arguments[1:1] = ['--fair-sched=yes', '--scheduling-quantum=1000']
            options.setdefault('environment', execution_environment())
            result = original(arguments, name, **options)
            unchanged(seals)
            if result['exit_code']:
                raise RuntimeError('Current guest profile command failed: '+name)
            return result

        checks.command = command
        version = command(['valgrind', '--version'], 'version')['output']
        if re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version.strip()
        calibrate_scope(checks, report)
        symbols = command(['nm', '--defined-only', binary], 'guest-symbols')['output']
        scope = selected_symbol(symbols, 'runPreparedKernel')
        for row in plan['rows']:
            # Keep all thirteen checked calls. Instrumented clocks never enter the derived profile.
            guest, role, limit = row['case'], row['role'], row['limit']
            name = guest+'-'+str(limit)+'-'+role
            executed, final = collect(checks, binary, name, scope,
                execution_environment(**row['environment']), 1800,
                dump_symbols=(scope,), executions=13)
            parsed = parse_application(executed['output'], role, guest, limit, require_full=True)
            if parsed['policy']['actual'] != role:
                # Instrumentation must not turn a native process into a successful interpreted fallback.
                raise ValueError('Profiled guest changed actual backend')
            matching_native_activity(row['native'], parsed['native'])
            cold = folder/(name+'.callgrind.1')
            texts = [cold.read_text(), final.read_text()]
            counts = [profile_counts(text) for text in texts]
            if any(set(value) != {'Ir', 'Bc', 'Bcm', 'Bi', 'Bim'} for value in counts):
                raise ValueError('Missing guest profile instruction or branch counters')
            costs = [exclusive_costs(text) for text in texts]
            command(['callgrind_annotate', '--auto=no', '--inclusive=no', '--threshold=99',
                     '--show=Ir,Bc,Bcm,Bi,Bim', final], name+'-self')
            command(['callgrind_annotate', '--auto=no', '--inclusive=yes', '--tree=both',
                     '--threshold=95', '--show=Ir', final], name+'-arcs')
            report['profiles'].append(dict(case=guest, limit=limit, role=role,
                checked_calls=13, native=parsed['native'], policy=parsed['policy'], scope=scope,
                cold=counts[0], reused=counts[1], cold_self_costs=costs[0], self_costs=costs[1],
                profile_hashes={member.name: hashlib.sha256(member.read_bytes()).hexdigest()
                    for member in sorted(folder.glob(name+'.callgrind*'))}, inputs=row['inputs'],
                run={key: executed[key] for key in ('command', 'exit_code', 'log')}))
            destination.write_text(json.dumps(report, indent=2)+'\n')
        unchanged(seals)
        report['status'] = 'passed'
    except BaseException as error:
        # Failure retains explicit incomplete state and every available raw part instead of claiming success.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--limits', type=int, nargs='+', default=[100000, 10000000])
    options = parser.parse_args()
    profile_current_guest(options.report, options.revision, options.limits)
