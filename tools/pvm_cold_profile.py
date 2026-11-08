#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Attribute three inclusive Sieve1000 scopes in a qualified unchanged Linux image; discard clocks.

Consumes only current canonical qualification and live sealed images/inputs. The maintained
collector owns calibration and exact return dumps; neither guest hooks nor rebuilds are supplied.
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
from pvm_instruction_profile import calibrate_scope, collect, exclusive_costs, profile_counts
from pvm_native_ci import host_identity
from pvm_performance_report import validate_current_report
from pvm_x86_jit_profile import (canonical_image_authority, canonical_source_identity,
                                 canonical_tooling_seals, selected_symbol)

SCOPES = (('decodeArtifact', 1), ('prepareIndependent', 1), ('runPreparedKernel', 13))


def sieve_plan(cohort, revision):
    """Admit one original interpreted Sieve1000 recipe from a complete current micro/all cohort."""
    validate_current_report(cohort)
    if (cohort['revision'] != revision or re.fullmatch('[0-9a-f]{40}', revision) is None
            or cohort['architecture'] != 'x86_64' or cohort['scope'] not in ('all', 'micro')):
        raise ValueError('Cold profile source, architecture or coverage disagreement')
    identity = cohort['identity']
    files = identity['files']
    drivers = [Path(name) for name in files if name.endswith('/tests/performance/pvm_sieve.nim')]
    if len(drivers) != 1 or not drivers[0].is_absolute():
        raise ValueError('Missing or ambiguous canonical guest source root')
    source = drivers[0].parents[2]
    build, = [row for row in cohort['builds'] if row.get('family') == 'guest']
    command = build['run'].get('command', [])
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld',
             '-d:pvmX86Jit', '-d:pvmArm64JitOwnerReceipt',
             '--passC:-I'+str(source/'tests/performance'),
             '--passC:-I'+str(source/'native/pvm_jit')]
    if (len(command) != len(flags)+5 or command[1:2] != ['c'] or command[2:-3] != flags
            or not command[-3].startswith('--nimcache:')
            or command[-2:] != ['--out:'+build['binary'], str(drivers[0])]
            or files.get(command[0]) != identity['compiler']['sha256']):
        raise ValueError('Canonical guest checked build recipe disagreement')
    if (not isinstance(identity.get('clang'), str) or not identity['clang'].strip()
            or not isinstance(identity.get('build_environment'), dict)):
        raise ValueError('Missing canonical compiler or build environment identity')
    row, = [row for row in cohort['runs'] if
            (row['case_id'], row['role'], row['order']) == ('sieve-1000', 'interpreted', 0)]
    env = row['run'].get('benchmark_environment', {})
    data = Path(env.get('RAGNAROK_PVM_SIEVE_INPUT', ''))
    expected = Path(env.get('RAGNAROK_PVM_SIEVE_EXPECTED', ''))
    artifact = source/'tests/fixtures/pvm-sieve/sieve.polkavm'
    recipe = dict(RAGNAROK_PVM_BACKEND='interpreted', RAGNAROK_PVM_PERFORMANCE='1',
        RAGNAROK_PVM_GUEST='sieve', RAGNAROK_PVM_PRICING='prepared',
        RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_CLOCK='1',
        RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
        RAGNAROK_PVM_SIEVE_EXPECTED=str(expected), RAGNAROK_PVM_SIEVE_ARTIFACT=str(artifact))
    if (env != recipe or not data.is_absolute() or not expected.is_absolute()
            or row['run']['command'] != [build['binary']]):
        raise ValueError('Canonical Sieve1000 invocation recipe disagreement')
    inputs = {str(path): files.get(str(path)) for path in (data, expected, artifact)}
    if any(value is None for value in inputs.values()):
        raise ValueError('Unsealed canonical Sieve1000 input')
    return dict(revision=revision, source_root=str(source), build=build,
        rows=[dict(case='sieve-1000', environment=recipe, inputs=inputs)],
        compiler=identity['compiler'], clang=identity['clang'], toolchain=identity['toolchain'],
        build_environment=identity['build_environment'])


def sieve_observation(output):
    """Require the full original process and absent runtime, retaining no instrumented clock values."""
    parsed = parse_application(output, 'interpreted', 'sieve', 1000, require_full=True)
    native, policy = parsed['native'], parsed['policy']
    if (len(parsed['invocation']['samples']) != 13 or any(native.values())
            or policy['requested'] != 'interpreted' or policy['actual'] != 'interpreted'):
        raise ValueError('Cold profile has native activity or incomplete calls')
    return dict(checked_calls=13, runtime='absent', native=native, policy=policy,
        runtime_none=parsed['diagnostics']['scope_observations']['runtime_none'])


def profile_sieve(cohort_path, revision, rebuilt_path=None, folder=None):
    """Run three calibrated named scopes only after current source/image/input qualification."""
    folder = Path(folder or ROOT/'build/tests/pvm-cold-profile')
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder/'results.json'
    report = dict(schema='pvm-sieve-cold-host-profile-v1', status='incomplete', architecture='x86_64',
        profiles=[], controls=[], builds=[], clock_policy='discarded', hardware_counters=False,
        boundary_protocol='symbol-returns-v1', scope='separate inclusive named functions; not enclosing cold time',
        image_authority='independent-rebuild' if rebuilt_path else 'original-sealed-image')
    destination.write_text(json.dumps(report, indent=2)+'\n')
    try:
        # Refuse foreign hosts and incomplete authority before any tool or calibration is reachable.
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('Cold profiles are CI-only')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] != 'x86_64':
            raise ValueError('Cold profiles require native Linux x86_64')
        documents = [Path(cohort_path), *([Path(rebuilt_path)] if rebuilt_path else [])]
        seals = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in documents}
        tooling = canonical_tooling_seals()
        seals.update(tooling)
        cohorts = [json.loads(path.read_text()) for path in documents]
        plans = [sieve_plan(value, revision) for value in cohorts]
        sources = [canonical_source_identity(value, plan) for value, plan in zip(cohorts, plans)]
        canonical_image_authority(plans[0], plans[-1])
        plan = plans[-1]
        build, selected = plan['build'], plan['rows'][0]
        binary = Path(build['binary'])
        if not binary.is_file():
            raise ValueError('Selected sealed guest image is absent; no implicit rebuild')
        seals.update({Path(name): value for name, value in selected['inputs'].items()})
        seals[binary] = build['binary_sha256']
        if any(path.is_symlink() for path in seals):
            raise ValueError('Redirected cold diagnostic input')
        unchanged(seals)
        # A coherent report label cannot authorize a different Sieve size in the sealed native input.
        with Path(selected['environment']['RAGNAROK_PVM_SIEVE_INPUT']).open('rb') as stream:
            header = stream.read(136)
        if len(header) != 136 or header[:8] != b'PVMSIV01' or int.from_bytes(header[16:20], 'little') != 1000:
            raise ValueError('Canonical cold workload is not Sieve1000')
        report.update(host=host, source=sources[-1], source_root=plan['source_root'],
            compiler=plan['compiler'], clang=plan['clang'],
            toolchain=plan['toolchain'], build_environment=plan['build_environment'],
            image=dict(path=str(binary), sha256=build['binary_sha256'], build=build),
            cohorts={str(path): seals[path] for path in documents},
            qualification_ci={str(path): value['identity']['ci'] for path, value in zip(documents, cohorts)},
            tooling_files={str(path): value for path, value in tooling.items()},
            profiler_ci={key: os.environ.get(key) for key in
                ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA', 'GITHUB_JOB')})
        checks = NativeChecks(folder)
        raw_command = checks.command

        def sealed_command(arguments, name, **options):
            """Check live authority around every child, including calibration and annotation tools."""
            unchanged(seals)
            options.setdefault('environment', execution_environment())
            options.setdefault('cwd', Path(plan['source_root']))
            result = raw_command(arguments, name, **options)
            unchanged(seals)
            if result['exit_code']:
                raise RuntimeError('Cold profile tool failed: '+name)
            return result

        checks.command = sealed_command
        version = checks.command(['valgrind', '--version'], 'version')
        if re.fullmatch(r'valgrind-[0-9]+\.[0-9]+\.[0-9]+\s*', version['output']) is None:
            raise ValueError('Invalid Valgrind version')
        report['valgrind'] = version['output'].strip()
        symbols = checks.command(['nm', '--defined-only', binary], 'guest-symbols')
        scopes = [(selected_symbol(symbols['output'], prefix), returns) for prefix, returns in SCOPES]
        calibrate_scope(checks, report)
        for scope, returns in scopes:
            # Each independent process retains the identical complete13-call recipe and state checks.
            name = scope+'-interpreted'
            executed, final = collect(checks, binary, name, scope,
                execution_environment(**selected['environment']), 1200,
                dump_symbols=(scope,), executions=returns)
            # Annotation and later collectors must not alter any already accepted raw return part.
            raw_seals = {path: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted(folder.glob(name+'.callgrind*'))}
            seals.update(raw_seals)
            observation = sieve_observation(executed['output'])
            parts = []
            for index in range(1, returns+1):
                path = folder/(name+'.callgrind.'+str(index))
                text = path.read_text()
                counts = profile_counts(text)
                if set(counts) != {'Ir', 'Bc', 'Bcm', 'Bi', 'Bim'}:
                    raise ValueError('Missing cold host branch counters')
                parts.append(dict(return_index=index, counts=counts, self_costs=exclusive_costs(text),
                    path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
            checks.command(['callgrind_annotate', '--auto=no', '--inclusive=no', '--threshold=99',
                            '--show=Ir,Bc,Bcm,Bi,Bim', final], name+'-self')
            checks.command(['callgrind_annotate', '--auto=no', '--inclusive=yes', '--tree=both',
                            '--threshold=95', '--show=Ir', final], name+'-arcs')
            report['profiles'].append(dict(case='sieve-1000', role='interpreted', scope=scope,
                expected_returns=returns, parts=parts, inputs=selected['inputs'], **observation,
                profile_hashes={path.name: seal for path, seal in raw_seals.items()},
                run=dict({key: executed[key] for key in ('command', 'exit_code', 'log')},
                         cwd=plan['source_root'])))
            destination.write_text(json.dumps(report, indent=2)+'\n')
        unchanged(seals)
        report['status'] = 'passed'
    except BaseException as error:
        # Partial dumps and original errors survive, while stale success cannot certify this attempt.
        report.update(status='failed', error=str(error))
        raise
    finally:
        destination.write_text(json.dumps(report, indent=2)+'\n')
    return report


def main():
    """Require explicit current-source authority; Make supplies no implicit image build or cohort."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, default=os.environ.get('PVM_COLD_REPORT') or None)
    parser.add_argument('--source-revision', default=os.environ.get('PVM_COLD_SOURCE_REVISION'))
    parser.add_argument('--rebuilt-report', type=Path, default=os.environ.get('PVM_COLD_REBUILT_REPORT') or None)
    options = parser.parse_args()
    if not options.report or not options.source_revision:
        parser.error('Cold profiling requires an explicit current report and immutable source revision')
    profile_sieve(options.report, options.source_revision, options.rebuilt_report)


if __name__ == '__main__':
    main()
