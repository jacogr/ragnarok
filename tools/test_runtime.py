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
from contextlib import nullcontext
import sys
from native_checks import NativeChecks, announce
from corpus_catalog import CORPUS_NAMES, run_corpora, corpus_partition, parse_corpus_shard, corpus_directory
from failure_checks import run_failure_suites, FAILURE_SUITES
from failure_plans import (FAILURE_PLANS, FAILURE_COUNTS, SPECIAL_CASES, SPECIAL_DRIVERS,
                           failure_partition, parse_failure_shard, failure_libraries)
from native_tests import UNIT_SUITES, unit_work_directory, unit_command, unit_environment, unit_evidence, unit_cache_lock, unit_partition, parse_unit_shard, ARC_SUITES
from native_preparation import prepare_libraries, prepare_integration, prepare_unit_fixtures, prepare_partition_fixtures

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/runtime'
# Each selected workload owns its workspace; other jobs use independent native-check instances.
checks = NativeChecks(BUILD, reuse_builds=True, lto=False)
command, build = checks.command, checks.build


# Require every native suite and independent corpus, without borrowing another job's verdict.
def unit_passed(report):
    try:
        # Every shard has a source-derived exact scope; partial data cannot claim full verification.
        batches, corpora = unit_partition(report.get('unit_shard'), report.get('shard_seed'),
                                         report.get('unit_scope', 'all'))
        if report.get('corpus_shard') is not None and report.get('unit_scope') != 'corpus':
            return False
        expected_corpora = set(corpus_partition(report.get('corpus_shard'), report.get('shard_seed'))) if corpora else set()
    except ValueError:
        return False
    expected = {name for _, members, _ in batches for name in members}
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
        plans, specialized = failure_partition(report.get('failure_shard'), report.get('shard_seed'))
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
def run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard=None, seed=None, scope='all', corpus_shard=None):
    with nullcontext() if scope == 'corpus' else unit_cache_lock(compiler):
        # Only Hastur suites share ARC evidence; corpus-only runs use their own native build caches.
        _run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard, seed, scope, corpus_shard)


# Keep complete execution order; the corpus scope has private builds and no Hastur evidence to lock.
def _run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, shard, seed, scope, corpus_shard):
    batches, corpora = unit_partition(shard, seed, scope)
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
        # Only the selected owner runs corpora; shared driver dependencies retain their original order.
        options = dict(shard=corpus_shard, seed=seed) if corpus_shard is not None else {}
        run_corpora(compiler, report, checks, libraries, quic_fixtures, integration_wires, **options)


# Execute strict crash/contract probes separately; compilation alone cannot prove these preconditions.
def run_failures(compiler, report, libraries, availability_fixture, composition_fixture, shard=None, seed=None):
    plans, specialized = failure_partition(shard, seed)
    groups = tuple(family for family in plans if family in FAILURE_SUITES)
    # Discovered families keep their ordered probes, independent binaries and exact diagnostic predicates.
    run_failure_suites(compiler, report, libraries, build, command, groups=groups)
    if not specialized:
        # Specialized controls and their native resource setup execute once, in the selected partition.
        return
    from failure_controls import CONTROLS, FailureContext
    context = FailureContext(compiler, report, libraries, build, command, BUILD,
                             availability_fixture, composition_fixture)
    CONTROLS.run(context)


# Select one independent workload and invalidate stale evidence before any setup or compilation.
def main():
    global BUILD, checks, command, build
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--group', choices=('unit', 'failures'), default='unit')
    parser.add_argument('--unit-scope', choices=('all', 'suites', 'corpus'),
                        default=os.environ.get('UNIT_SCOPE', 'all'),
                        help='Run complete local verification, native suites only, or independent corpora only')
    parser.add_argument('--corpus-shard', type=parse_corpus_shard,
                        default=os.environ.get('CORPUS_SHARD') or None,
                        help='Run one dependency-preserving randomized corpus partition, index/count (at most three)')
    parser.add_argument('--unit-shard', type=parse_unit_shard, default=os.environ.get('UNIT_SHARD') or None,
                        help='Run one discovered unit partition, index/count (at most sixteen)')
    parser.add_argument('--failure-shard', type=parse_failure_shard, default=os.environ.get('FAILURE_SHARD'),
                        help='Run one discovered contract partition, index/count (at most six)')
    parser.add_argument('--shard-seed', default=os.environ.get('CI_SHARD_SEED'),
                        help='Shared shuffle seed; CI uses its run ID, retained in each report')
    args = parser.parse_args()
    if args.shard_seed is not None and not args.shard_seed.strip():
        # An empty CI seed must fail before setup instead of selecting an unintended lexical plan.
        parser.error('--shard-seed must be nonempty')
    if args.unit_shard is not None and args.group != 'unit':
        # Runtime rejection probes retain their separate complete execution contract.
        parser.error('--unit-shard applies only to the unit group')
    if args.failure_shard is not None and args.group != 'failures':
        # Ordinary unit/corpus verification must not inherit a contract-only partial selection.
        parser.error('--failure-shard applies only to the failures group')
    if args.unit_scope not in ('all', 'suites', 'corpus'):
        # Argparse does not check choices for environment defaults; reject malformed inherited scope too.
        parser.error('--unit-scope must be all, suites or corpus')
    if args.unit_scope != 'all' and args.group != 'unit':
        # Contract runs must not accept a unit-only workload selector.
        parser.error('--unit-scope applies only to the unit group')
    if args.unit_scope == 'corpus' and args.unit_shard is not None:
        # A corpus-only green report must never hide a requested unit partition.
        parser.error('--unit-shard cannot select corpus-only verification')
    if args.corpus_shard is not None and (args.group != 'unit' or args.unit_scope != 'corpus'):
        # A corpus partition must never narrow complete local units or contract verification implicitly.
        parser.error('--corpus-shard requires --group unit --unit-scope corpus')
    # Private reports, caches and logs allow the workloads to run on independent CI runners.
    directory = 'corpus' if args.unit_scope == 'corpus' else 'runtime'
    BUILD = ROOT/('build/tests/'+directory if args.group == 'unit' else 'build/tests/failures')
    if args.corpus_shard is not None:
        BUILD = corpus_directory(BUILD, args.corpus_shard)
    checks = NativeChecks(BUILD, reuse_builds=True, lto=False)
    command, build = checks.command, checks.build
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    # A failed or timed-out new invocation must never leave an earlier successful report current.
    (BUILD/'results.json').unlink(missing_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), verification_group=args.group)
    if args.shard_seed is not None and (args.unit_shard or args.failure_shard or args.corpus_shard):
        # Report-driven validation and local reproduction use the actual scheduling seed.
        report['shard_seed'] = args.shard_seed
        print('Shard shuffle seed: '+args.shard_seed, flush=True)
    if args.group == 'unit':
        # Unit evidence owns suites/corpora only; runtime contracts have a different report.
        report['suites'] = []
        report['unit_scope'] = args.unit_scope
        if args.corpus_shard is not None:
            report['corpus_shard'] = args.corpus_shard
        if args.unit_shard is not None:
            # Summaries must identify subset evidence rather than presenting it as the full suite.
            report['unit_shard'] = args.unit_shard
    else:
        # Every runtime family must be populated by this invocation, including after a prior successful run.
        plans, specialized = failure_partition(args.failure_shard, args.shard_seed)
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
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(set(sources))}
    # The existing native guarantee suite consumes an independently authored minimal report fixture.
    sys.path.insert(0, str(ROOT/'tests'))
    selected_suites = None
    needs_corpora = True
    if args.group == 'unit' and (args.unit_shard is not None or args.unit_scope != 'all'):
        # Provision only the union consumed by this partition; corpora retain their complete dependencies.
        selected_batches, needs_corpora = unit_partition(args.unit_shard, args.shard_seed, args.unit_scope)
        selected_suites = [name for _, members, _ in selected_batches for name in members]
        from native_requirements import NATIVE_REQUIREMENTS
        required = {library for name in selected_suites for library in NATIVE_REQUIREMENTS[name]['libraries']}
        libraries, quic_fixtures, native_evidence = prepare_libraries(
            BUILD, required=None if needs_corpora else required)
    elif args.group == 'failures' and args.failure_shard is not None:
        # Ordinary partitions avoid preparing unrelated transport and Rust resources.
        libraries, quic_fixtures, native_evidence = prepare_libraries(
            BUILD, required=failure_libraries(args.failure_shard, args.shard_seed))
    else:
        # Complete local runs preserve the established aggregate preparation path.
        libraries, quic_fixtures, native_evidence = prepare_libraries(BUILD)
    report.update(native_evidence)
    integration_wires = integration_reload = None
    if (args.group == 'unit' and needs_corpora) or (args.group == 'failures' and specialized):
        # Only independent corpora/failure verification need unconditional CE preparation.
        integration_wires, integration_reload, report['integration_fixtures'] = prepare_integration(BUILD)
    availability_fixture = composition_fixture = None
    if (args.group == 'unit' and args.unit_scope != 'corpus') or (args.group == 'failures' and specialized):
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
        if args.unit_scope == 'corpus':
            # Corpus inputs have their own integration preparation; no ordinary suite fixture provider runs.
            fixtures = {}
        elif selected_suites is None:
            # Unsharded verification retains all historical fixture evidence fields and preparation order.
            fixtures, fixture_evidence = prepare_unit_fixtures(BUILD, quic_fixtures, integration_wires, integration_reload)
            report.update(fixture_evidence)
        else:
            # Feature providers run once per needed group rather than preparing every suite in every shard.
            integration = (integration_wires, integration_reload) if needs_corpora else None
            fixtures, fixture_evidence = prepare_partition_fixtures(
                BUILD, selected_suites, quic_fixtures, integration)
            report['partition_fixture_preparation'] = fixture_evidence
        run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires, args.unit_shard,
                 args.shard_seed, args.unit_scope, args.corpus_shard)
        step_passed = unit_passed(report)
    else:
        # Contract checks keep their diagnostic predicates and positive controls unchanged.
        run_failures(compiler, report, libraries, availability_fixture, composition_fixture,
                     args.failure_shard, args.shard_seed)
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
