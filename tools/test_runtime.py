#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify checked native suites, independent corpora and runtime misuse contracts.

Exposes unit/failure verdicts and run_unit/run_failures; main selects the verification group and
writes its report. Checked native compilation, fixtures and evidence remain group-owned.
"""
import argparse
import os
import hashlib
import json
import platform
from pathlib import Path
import sys
from native_checks import NativeChecks, announce
from corpus_catalog import CORPUS_NAMES, run_corpora
from failure_checks import probe_failure, run_failure_suites, FAILURE_SUITES
from failure_plans import (FAILURE_PLANS, FAILURE_COUNTS, SPECIAL_CASES, SPECIAL_DRIVERS,
                           check_driver_modes, failure_partition, parse_failure_shard, failure_libraries)
from native_tests import UNIT_SUITES, unit_work_directory, unit_command, unit_environment, unit_evidence, unit_cache_lock, unit_partition, parse_unit_shard, ARC_SUITES
from native_preparation import prepare_libraries, prepare_integration, prepare_unit_fixtures, prepare_partition_fixtures

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/runtime'
# Each selected workload owns its workspace; other jobs use independent native-check instances.
checks = NativeChecks(BUILD)
command, build = checks.command, checks.build


# Require every native suite and independent corpus, without borrowing another job's verdict.
def unit_passed(report):
    try:
        # Every shard has a source-derived exact scope; partial data cannot claim full verification.
        batches, corpora = unit_partition(report.get('unit_shard'))
    except ValueError:
        return False
    expected = {name for _, members, _ in batches for name in members}
    expected_corpora = set(CORPUS_NAMES) if corpora else set()
    rows = report.get('suites', [])
    names = [row.get('name') for row in rows]
    return (len(names) == len(expected) and set(names) == expected
            and all(row.get('passed') is True for row in rows)
            and {key for key in report if key.endswith('_corpus')} == expected_corpora
            and all(report[name].get('passed') is True for name in expected_corpora)
            and not set(FAILURE_COUNTS).intersection(report))


# Missing, duplicate or failed contract probes cannot be masked by successful sibling families.
def failures_passed(report):
    try:
        # Scope is derived before execution and is never inferred from whichever probes happened to pass.
        plans, specialized = failure_partition(report.get('failure_shard'))
    except ValueError:
        return False
    if set(FAILURE_PLANS).intersection(report) != set(plans):
        # Extra sibling-shard results cannot conceal a wrong or incomplete partition declaration.
        return False
    for family, expected in plans.items():
        # Each historical workload must produce exactly its original ordered set of distinct records.
        rows = report.get(family, [])
        identities = [json.dumps({key: value for key, value in row.items()
                                 if key not in ('run', 'check', 'passed')}, sort_keys=True) for row in rows]
        wanted = {json.dumps(identity, sort_keys=True) for identity in expected}
        if (len(rows) != len(expected) or set(identities) != wanted
                or not all(row.get('passed') is True for row in rows)):
            # Incomplete evidence remains a failing job even when all emitted rows happened to pass.
            return False
    if specialized:
        # All specialized enumerations and store positive controls remain mandatory for their owner.
        controls = (report.get('store_controls', {}).get('passed') is True
                    and set(report.get('probe_cases', {})) == set(SPECIAL_DRIVERS)
                    and all(row.get('passed') is True for row in report['probe_cases'].values()))
    else:
        # Ordinary partitions cannot borrow a specialized verdict they did not execute.
        controls = 'store_controls' not in report and 'probe_cases' not in report
    return (controls and 'suites' not in report
            and not any(key.endswith('_corpus') for key in report))


# Execute ordinary Hastur suites and independent references with the existing fixture/linking contracts.
def run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard=None):
    with unit_cache_lock(compiler):
        # A concurrent standalone run must not mutate the shared cache or retire active ARC evidence.
        _run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard)


# Keep the complete execution order and corpus contracts within one compiler-cache lock.
def _run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard):
    batches, corpora = unit_partition(shard)
    for batch, members, target in batches:
        # Compatible codecs share one directory run; linked/resource profiles retain isolated runs.
        print('RUN '+batch+' (Hastur)', flush=True)
        checked = command(unit_command(compiler, target, libraries), batch+'-hastur',
                          unit_environment(compiler, target, fixtures=fixtures, suites=members),
                          cwd=unit_work_directory(compiler))
        print(f'Completed {batch} in {checked["elapsed_seconds"]:.2f}s', flush=True)
        if checked['exit_code'] != 0:
            # A group failure is conservative for every member and retains Hastur's individual diagnostics.
            print(checked['output'], flush=True)
        for name in members:
            # Preserve every historical suite row and fresh per-suite ARC observation in cumulative evidence.
            row = dict(name=name, runner='hastur', batch=batch, check=checked,
                       passed=checked['exit_code'] == 0)
            if row['passed'] and name in ARC_SUITES:
                # A missing or inconsistent current observation cannot reuse an earlier successful report.
                try:
                    report[ARC_SUITES[name]] = unit_evidence(compiler, name)
                except (OSError, ValueError) as error:
                    # Evidence failures remain visible independently of the native verdict.
                    row['passed'] = False
                    row['evidence_error'] = str(error)
            report['suites'].append(row)
            announce(name+' (Hastur)', row['passed'])
    if corpora:
        # Only the final shard owns corpora; shared driver dependencies retain their original order.
        run_corpora(compiler, report, checks, libraries, quic_fixtures, integration_wires)


# Execute strict crash/contract probes separately; compilation alone cannot prove these preconditions.
def run_failures(compiler, report, libraries, availability_fixture, composition_fixture, shard=None):
    plans, specialized = failure_partition(shard)
    groups = tuple(family for family in plans if family in FAILURE_SUITES)
    # Discovered families keep their ordered probes, independent binaries and exact diagnostic predicates.
    run_failure_suites(compiler, report, libraries, build, command, groups=groups)
    if not specialized:
        # Specialized controls and their native resource setup execute once, in the final partition.
        return
    from bandersnatch_native import OWNER_DEFINES
    crypto_library = libraries['crypto']
    crypto_observer = libraries['observer']
    bs_library = libraries['bandersnatch']
    bs_libraries = (libraries['bandersnatch_observer'], bs_library)
    # Public store payloads/views require their own contracts, independent of ordinary success suites.
    compiled, binary = build(compiler, ROOT/'tests/native/state_store_results.nim', 'state-store-results', crypto_library)
    report['store_build'] = compiled
    report['store_controls'] = dict(passed=False)
    if compiled['exit_code'] == 0:
        # Actual and default failures cover every public generic payload family.
        cases = SPECIAL_CASES['store']
        for member, origin, sentinel in cases:
            # Match the supported precondition and exit status, never an unrelated crash or fixture error.
            probe_failure(command, report['store'], [binary, member, origin],
                          'store-' + member + '-' + origin, sentinel,
                          'store ' + member + ' ' + origin + ' runtime guard', member=member, origin=origin)
        controls = {member: command([binary, member, 'valid'], 'store-'+member+'-valid')
                    for member in ('metadata', 'length', 'bytes')}
        report['store_controls'] = dict(checks=controls,
            passed=all(row['exit_code'] == 0 and row['output'].strip() == ('1' if member == 'metadata' else '0')
                       for member, row in controls.items()))
    # Actual/default result access must reject for every fixed proof/output, sequence and opaque native owner.
    compiled, binary = build(compiler, SPECIAL_DRIVERS['bandersnatch'], 'bandersnatch-results',
                             native_libraries=bs_libraries, cflags=OWNER_DEFINES)
    report['bandersnatch_build'] = compiled
    if compiled['exit_code'] == 0:
        # Separate processes prevent prior contract failures or test-observer flags from concealing later checks.
        check_driver_modes(command, binary, 'bandersnatch', report)
        for member, origin, sentinel in SPECIAL_CASES['bandersnatch']:
            # Each declared mode and failure origin retains its own process and supported diagnostic.
            probe_failure(command, report['bandersnatch'], [binary, member, origin],
                          'bs-' + origin + '-' + member, sentinel,
                          origin + ' Bandersnatch ' + member + ' runtime guard', origin=origin, member=member)
    # Completion guards need only their public fixture, not the E2E network/soak workloads.
    from test_quic_offload import corpus as offload_fixture
    offload_wire, _ = offload_fixture(BUILD/'offload-fixture')
    # The same guarded completion API must reject defaults and actual empty polls in both build profiles.
    for enabled in (False, True):
        compiled, binary = build(compiler, ROOT/'tests/native/nimony_offload_results.nim',
                                 'offload-results-'+str(enabled), native_libraries=(bs_library,) if enabled else (),
                                 defines=('offload',) if enabled else ())
        report['offload_results_'+str(enabled)] = compiled
        if compiled['exit_code'] == 0:
            # Enabled empty-poll probes start and join their own workers before attempting the invalid read.
            for selected, origin in SPECIAL_CASES['offload']:
                # Each enabled/disabled build executes only its own planned origins.
                if selected != enabled:
                    continue
                environment = {**os.environ, 'RAGNAROK_OFFLOAD_FIXTURE': str(offload_wire),
                               'RAGNAROK_OFFLOAD_REPEATS': '1', 'RAGNAROK_OFFLOAD_GATE': ''}
                probe_failure(command, report['offload'], [binary, origin],
                              'offload-result-' + str(enabled) + '-' + origin, 'value.hasCompletion',
                              'offload ' + str(enabled) + ' ' + origin + ' completion runtime guard', environment=environment, enabled=enabled, origin=origin)
    # Wrapping is the accepted Nimony language policy; assertions and bounds must still reject.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_runtime_guards.nim', 'runtime')
    report['runtime_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every observation is separate so a prior assertion failure cannot conceal wrapping behavior.
        for mode, sentinel, expected_exit in SPECIAL_CASES['runtime']:
            result = command([binary, mode], mode+'-runtime')
            passed = result['exit_code'] == expected_exit and sentinel in result['output']
            report['runtime'].append(dict(name=mode, passed=passed, run=result))
            announce(mode+' behavior', passed)
    # Every public/private result and each inactive assignment field must retain its exact contract.
    compiled, binary = build(compiler, SPECIAL_DRIVERS['availability'], 'availability-results', crypto_library)
    report['availability_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and dynamic absence origins execute independently, retaining their own diagnostics.
        check_driver_modes(command, binary, 'availability', report)
        cases = SPECIAL_CASES['availability']
        for member, origin, sentinel in cases:
            probe_failure(command, report['availability'], [binary, member, origin, availability_fixture],
                          'availability-' + origin + '-' + member, sentinel,
                          origin + ' availability ' + member + ' runtime guard', origin=origin, member=member)
    # Both queue domains and internal count/layout proofs require successful payload selection.
    compiled, binary = build(compiler, SPECIAL_DRIVERS['workqueues'], 'workqueues-results', crypto_library)
    report['workqueues_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures execute separately so one rejected access cannot conceal another.
        check_driver_modes(command, binary, 'workqueues', report)
        for member, origin, sentinel in SPECIAL_CASES['workqueues']:
            # Execute every declared access in its own process with the original failure expectation.
            probe_failure(command, report['workqueues'], [binary, member, origin, availability_fixture],
                          'workqueues-' + origin + '-' + member, sentinel,
                          origin + ' workqueues ' + member + ' runtime guard', origin=origin, member=member)
    # Complete composition payloads require exact success, including backend and association failures.
    compiled, binary = build(compiler, SPECIAL_DRIVERS['composition'], 'composition-results', crypto_observer)
    report['composition_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual and default failures execute separately so one protected read never conceals another.
        check_driver_modes(command, binary, 'composition', report)
        for member, origin, sentinel in SPECIAL_CASES['composition']:
            # Execute every declared access in its own process with the original failure expectation.
            probe_failure(command, report['composition'], [binary, member, origin, composition_fixture],
                          'composition-' + origin + '-' + member, sentinel,
                          origin + ' composition ' + member + ' runtime guard', origin=origin, member=member)


# Select one independent workload and invalidate stale evidence before any setup or compilation.
def main():
    global BUILD, checks, command, build
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--group', choices=('unit', 'failures'), default='unit')
    parser.add_argument('--unit-shard', type=parse_unit_shard, default=os.environ.get('UNIT_SHARD'),
                        help='Run one discovered unit partition, index/count (at most eight)')
    parser.add_argument('--failure-shard', type=parse_failure_shard, default=os.environ.get('FAILURE_SHARD'),
                        help='Run one discovered contract partition, index/count (at most four)')
    args = parser.parse_args()
    if args.unit_shard is not None and args.group != 'unit':
        # Runtime rejection probes retain their separate complete execution contract.
        parser.error('--unit-shard applies only to the unit group')
    if args.failure_shard is not None and args.group != 'failures':
        # Ordinary unit/corpus verification must not inherit a contract-only partial selection.
        parser.error('--failure-shard applies only to the failures group')
    # Private reports, caches and logs allow the two workloads to run on independent CI runners.
    BUILD = ROOT/('build/tests/runtime' if args.group == 'unit' else 'build/tests/failures')
    checks = NativeChecks(BUILD, reuse_builds=args.group == 'failures')
    command, build = checks.command, checks.build
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    # A failed or timed-out new invocation must never leave an earlier successful report current.
    (BUILD/'results.json').unlink(missing_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), verification_group=args.group)
    if args.group == 'unit':
        # Unit evidence owns suites/corpora only; runtime contracts have a different report.
        report['suites'] = []
        if args.unit_shard is not None:
            # Summaries must identify subset evidence rather than presenting it as the full suite.
            report['unit_shard'] = args.unit_shard
    else:
        # Every runtime family must be populated by this invocation, including after a prior successful run.
        plans, specialized = failure_partition(args.failure_shard)
        report.update({family: [] for family in plans})
        if args.failure_shard is not None:
            # A green partition is visibly partial until the aggregate CI check has passed.
            report['failure_shard'] = args.failure_shard
    metadata = compiler.parent.parent/'NIGHTLY.txt'
    report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
    report['nimony_version'] = command([compiler, '--version'], 'nimony-version')
    report['clang_version'] = command(['clang', '--version'], 'clang-version')
    report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
    # Use the same source expansion as CI's omission check.
    from runtime_provenance import runtime_sources
    sources = runtime_sources()
    # Hash every directly consumed proof/JAM fixture in addition to checking the pinned source trees.
    sys.path.insert(0, str(ROOT/'tests'))
    from test_bandersnatch import fixture_path
    sources += [fixture_path(name) for name in ('ietf.json', 'ring.json', 'jam-tiny.json', 'jam-full.json', 'jam-padding.json')]
    sources += [ROOT/f'vendor/jamtestvectors/codec/{profile}/work_result_{number}.{suffix}'
                for profile in ('tiny', 'full') for number in (0, 1) for suffix in ('json', 'bin')]
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(set(sources))}
    # The existing native guarantee suite consumes an independently authored minimal report fixture.
    sys.path.insert(0, str(ROOT/'tests'))
    selected_suites = None
    needs_corpora = True
    if args.group == 'unit' and args.unit_shard is not None:
        # Provision only the union consumed by this partition; corpora retain their complete dependencies.
        selected_batches, needs_corpora = unit_partition(args.unit_shard)
        selected_suites = [name for _, members, _ in selected_batches for name in members]
        from native_requirements import NATIVE_REQUIREMENTS
        required = {library for name in selected_suites for library in NATIVE_REQUIREMENTS[name]['libraries']}
        libraries, quic_fixtures, native_evidence = prepare_libraries(
            BUILD, required=None if needs_corpora else required)
    elif args.group == 'failures' and args.failure_shard is not None:
        # Ordinary partitions avoid preparing unrelated transport and Rust resources.
        libraries, quic_fixtures, native_evidence = prepare_libraries(
            BUILD, required=failure_libraries(args.failure_shard))
    else:
        # Complete local runs preserve the established aggregate preparation path.
        libraries, quic_fixtures, native_evidence = prepare_libraries(BUILD)
    report.update(native_evidence)
    integration_wires = integration_reload = None
    if (args.group == 'unit' and needs_corpora) or (args.group == 'failures' and specialized):
        # Only independent corpora/failure verification need unconditional CE preparation.
        integration_wires, integration_reload, report['integration_fixtures'] = prepare_integration(BUILD)
    availability_fixture = composition_fixture = None
    if args.group == 'unit' or specialized:
        # Only the specialized contract owner consumes these independent refusal witnesses.
        from state_availability_oracle import record as availability_record
        availability_fixture = BUILD/'availability-report.bin'
        availability_fixture.write_bytes(availability_record(0)['report'])
        # Composition ownership probes consume independent literal chapters, not native round-trip fixtures.
        from state_composition_oracle import chapters as composition_chapters
        composition_fixture = BUILD/'composition-chapters.txt'
        composition_fixture.write_text('\n'.join(raw.hex() for raw in composition_chapters())+'\n')
    if args.group == 'unit':
        # Expensive state replay/rotation fixtures belong only to the ordinary native suites.
        # Every ordinary suite now has one native runner path; omitted/extra identities are a migration failure.
        assert len(UNIT_SUITES) == len(set(UNIT_SUITES))
        if selected_suites is None:
            # Unsharded verification retains all historical fixture evidence fields and preparation order.
            fixtures, fixture_evidence = prepare_unit_fixtures(BUILD, quic_fixtures, integration_wires, integration_reload)
            report.update(fixture_evidence)
        else:
            # Feature providers run once per needed group rather than preparing every suite in every shard.
            integration = (integration_wires, integration_reload) if needs_corpora else None
            fixtures, fixture_evidence = prepare_partition_fixtures(
                BUILD, selected_suites, quic_fixtures, integration)
            report['partition_fixture_preparation'] = fixture_evidence
        run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, args.unit_shard)
        step_passed = unit_passed(report)
    else:
        # Contract checks keep their diagnostic predicates and positive controls unchanged.
        run_failures(compiler, report, libraries, availability_fixture, composition_fixture, args.failure_shard)
        step_passed = failures_passed(report)
    if args.group == 'failures':
        # Preserve the protected-result verdict in its owning job only.
        report['protected_results_increment'] = 'passed' if step_passed else 'failed'
    report['status'] = 'checks-passed' if step_passed else 'failed'
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'{args.group} verification: {report["status"]}')
    print(f'Evidence: {BUILD.relative_to(ROOT)}/results.json')
    raise SystemExit(0 if report['status'] == 'checks-passed' else 1)


# Importing this runner never downloads dependencies or starts a compiler.
if __name__ == '__main__':
    main()
