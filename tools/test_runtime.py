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
from corpus_codec import run_codecs
from corpus_state import run_state
from corpus_services import run_services
from corpus_crypto import run_bandersnatch, run_crypto
from corpus_network import run_network
from failure_checks import probe_failure, run_failure_suite
from verification_inventory import (
    AVAILABILITY_MEMBERS, BS_MEMBERS, COMPOSITION_MEMBERS,
    CORPUS_NAMES, FAILURE_COUNTS, WORKQUEUES_MEMBERS,
)
from native_tests import UNIT_SUITES, unit_batches, unit_work_directory, unit_command, unit_environment, unit_evidence, ARC_SUITES
from native_preparation import prepare_libraries, prepare_integration, prepare_unit_fixtures

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/runtime'
# Each selected workload owns its workspace; other jobs use independent native-check instances.
checks = NativeChecks(BUILD)
command, build = checks.command, checks.build


# Require every native suite and independent corpus, without borrowing another job's verdict.
def unit_passed(report):
    rows = report.get('suites', [])
    names = [row.get('name') for row in rows]
    return (len(names) == len(UNIT_SUITES) and set(names) == set(UNIT_SUITES)
            and all(row.get('passed') is True for row in rows)
            and {key for key in report if key.endswith('_corpus')} == set(CORPUS_NAMES)
            and all(report[name].get('passed') is True for name in CORPUS_NAMES)
            and not set(FAILURE_COUNTS).intersection(report))


# Missing, duplicate or failed contract probes cannot be masked by successful sibling families.
def failures_passed(report):
    for family, count in FAILURE_COUNTS.items():
        # Each historical workload must produce exactly its original ordered set of distinct records.
        rows = report.get(family, [])
        identities = [json.dumps({key: value for key, value in row.items()
                                 if key not in ('run', 'check', 'passed')}, sort_keys=True) for row in rows]
        if len(rows) != count or len(set(identities)) != count or not all(row.get('passed') is True for row in rows):
            # Incomplete evidence remains a failing job even when all emitted rows happened to pass.
            return False
    return (report.get('store_controls', {}).get('passed') is True and 'suites' not in report
            and not any(key.endswith('_corpus') for key in report))


# Execute ordinary Hastur suites and independent references with the existing fixture/linking contracts.
def run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires):
    for batch, members, target in unit_batches():
        # Compatible codecs share one directory run; linked/resource profiles retain isolated runs.
        checked = command(unit_command(compiler, target, libraries), batch+'-hastur',
                          unit_environment(compiler, target, fixtures=fixtures),
                          cwd=unit_work_directory(compiler))
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
    # Feature calls retain the original order, including shared driver-build dependencies.
    run_codecs(compiler, report, checks, libraries)
    run_state(compiler, report, checks, libraries)
    run_services(compiler, report, checks, libraries)
    run_bandersnatch(compiler, report, checks, libraries)
    run_network(compiler, report, checks, libraries, quic_fixtures, integration_wires)
    run_crypto(compiler, report, checks, libraries)


# Execute strict crash/contract probes separately; compilation alone cannot prove these preconditions.
def run_failures(compiler, report, libraries, availability_fixture, composition_fixture):
    from bandersnatch_native import OWNER_DEFINES
    crypto_library = libraries['crypto']
    crypto_observer = libraries['observer']
    bs_library = libraries['bandersnatch']
    bs_libraries = (libraries['bandersnatch_observer'], bs_library)
    quic_library = libraries['quic']
    # Public store payloads/views require their own contracts, independent of ordinary success suites.
    compiled, binary = build(compiler, ROOT/'tests/native/state_store_results.nim', 'state-store-results', crypto_library)
    report['store_build'] = compiled
    report['store_controls'] = dict(passed=False)
    if compiled['exit_code'] == 0:
        # Actual and default failures cover every public generic payload family.
        cases = [(member, origin, 'outcome.status == None')
                 for member in ('store', 'snapshot', 'lookup') for origin in ('default', 'error')]
        cases += [('metadata', 'default', 'not snapshot.data == nil'),
                  ('length', 'default', 'not view.owner.data == nil'),
                  ('bytes', 'default', 'not view.owner.data == nil')]
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
    # Proposed entry and committed-snapshot payloads are independently guarded on default and real failures.
    run_failure_suite(compiler, report, libraries, build, command, 'authorization_transition')
    # Root, proposed entry and committed snapshot payload families require independent checked guards.
    run_failure_suite(compiler, report, libraries, build, command, 'history_transition')
    # Updated fixed words/time and committed snapshots each require default and actual failure guards.
    run_failure_suite(compiler, report, libraries, build, command, 'entropy_transition')
    # Both default and actual failed plans reject payload extraction through the intended checked contract.
    run_failure_suite(compiler, report, libraries, build, command, 'validator_rotation')
    # Isolate default and actual failed publication results; require the intended access contract.
    run_failure_suite(compiler, report, libraries, build, command, 'validator_state')
    # Default and real failed admission candidates reject owner extraction through the intended contract.
    run_failure_suite(compiler, report, libraries, build, command, 'ticket_admission')
    # Publication snapshots require successful selection for both default and actually refused results.
    run_failure_suite(compiler, report, libraries, build, command, 'ticket_state')
    # Default and actually refused schedule results must not expose candidate payloads.
    run_failure_suite(compiler, report, libraries, build, command, 'sealer_schedule')
    # Default and actually refused schedule results must not expose candidate payloads.
    run_failure_suite(compiler, report, libraries, build, command, 'sealer_state')
    # Default and actually refused schedule results must not expose candidate payloads.
    run_failure_suite(compiler, report, libraries, build, command, 'safrole_markers')
    # Default and actually refused schedule results must not expose candidate payloads.
    run_failure_suite(compiler, report, libraries, build, command, 'safrole_authentication')
    # Coordinator success and each typed failure reason require their own selected result alternative.
    run_failure_suite(compiler, report, libraries, build, command, 'safrole_transition')
    # A refused commitment must never expose a default digest as a successful application value.
    run_failure_suite(compiler, report, libraries, build, command, 'extrinsic_commitment')
    # Isolate bound-owner, composed success and each stage-reason accessor from all other guards.
    run_failure_suite(compiler, report, libraries, build, command, 'block_admission')
    # Disputes plans, derived-owner access and composed failure causes require their exact selected contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'disputes_transition')
    # Availability plans, reports and typed context causes require their own successful/failed alternative.
    run_failure_suite(compiler, report, libraries, build, command, 'availability_transition')
    run_failure_suite(compiler, report, libraries, build, command, 'guarantor_assignments')
    run_failure_suite(compiler, report, libraries, build, command, 'guarantee_credentials')
    run_failure_suite(compiler, report, libraries, build, command, 'report_policy')
    run_failure_suite(compiler, report, libraries, build, command, 'report_anchors')
    # PVM scalar success and page-fault reason access require their exact selected alternatives.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_machine')
    # Register results publish values only after successful opcode evaluation.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_registers')
    # Gas failures never expose a partial or uninitialized block charge.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_gas')
    # Local step failures never expose a partially charged machine.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_step')
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_memory_step')
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_execution')
    # Fetch local refusals must not expose a completed host response.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_fetch')
    # Host dispatch and shared instruction budgets never expose failed execution payloads.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_host_execution')
    # Terminal gas deficits cannot bypass canonical state or success selection.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_host_gas')
    # Failed host range copies never expose partial buffers or memory owners.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_host_memory')
    # Host replies publish only valid posterior snapshots and no stale suspension metadata.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_host_response')
    # Initialization failures never expose a partially prepared machine.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_initialization')
    # Local return-buffer refusals never expose bytes or a copied prefix.
    run_failure_suite(compiler, report, libraries, build, command, 'pvm_output')
    run_failure_suite(compiler, report, libraries, build, command, 'report_packages')
    run_failure_suite(compiler, report, libraries, build, command, 'report_assignments')
    run_failure_suite(compiler, report, libraries, build, command, 'report_admission')
    run_failure_suite(compiler, report, libraries, build, command, 'report_transition')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_queue')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_operands')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_inputs')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_invocation')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_round')
    run_failure_suite(compiler, report, libraries, build, command, 'accumulation_service')
    # Transcript and count access on every actual/default context failure must terminate at the success contract.
    run_failure_suite(compiler, report, libraries, build, command, 'assurance_context')
    # Failed/default guarantee signing messages cannot expose an all-zero or partial domain/hash payload.
    run_failure_suite(compiler, report, libraries, build, command, 'guarantee_message')
    # Actual/default result access must reject for every fixed proof/output, sequence and opaque native owner.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_bandersnatch_results.nim', 'bandersnatch-results',
                             native_libraries=bs_libraries, cflags=OWNER_DEFINES)
    report['bandersnatch_build'] = compiled
    if compiled['exit_code'] == 0:
        # Separate processes prevent prior contract failures or test-observer flags from concealing later checks.
        for origin in ('default', 'error'):
            for member in BS_MEMBERS:
                probe_failure(command, report['bandersnatch'], [binary, member, origin],
                              'bs-' + origin + '-' + member, 'value.status == None',
                              origin + ' Bandersnatch ' + member + ' runtime guard', origin=origin, member=member)
    # Default/failed/pending frame metadata and default/failed E4 lengths cannot bypass result access contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'quic_protocol')
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
            for origin in ('default', 'empty'):
                environment = {**os.environ, 'RAGNAROK_OFFLOAD_FIXTURE': str(offload_wire),
                               'RAGNAROK_OFFLOAD_REPEATS': '1', 'RAGNAROK_OFFLOAD_GATE': ''}
                probe_failure(command, report['offload'], [binary, origin],
                              'offload-result-' + str(enabled) + '-' + origin, 'value.hasCompletion',
                              'offload ' + str(enabled) + ' ' + origin + ' completion runtime guard', environment=environment, enabled=enabled, origin=origin)
    # Every default/actual integration result family must reject value access before use.
    run_failure_suite(compiler, report, libraries, build, command, 'integration')
    # Wrapping is the accepted Nimony language policy; assertions and bounds must still reject.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_runtime_guards.nim', 'runtime')
    report['runtime_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every observation is separate so a prior assertion failure cannot conceal wrapping behavior.
        for mode, sentinel in (('assertion', 'trial assertion sentinel'), ('bounds', '[AssertionDefect]'),
                               ('wrapping', '-9223372036854775808')):
            result = command([binary, mode], mode+'-runtime')
            expected_exit = 0 if mode == 'wrapping' else 1
            passed = result['exit_code'] == expected_exit and sentinel in result['output']
            report['runtime'].append(dict(name=mode, passed=passed, run=result))
            announce(mode+' behavior', passed)
    # Each of six public coordinates/counts must reject both defaults and actual operation failures.
    run_failure_suite(compiler, report, libraries, build, command, 'bounded')
    # Primitive success payloads are guarded on defaults/errors; error reasons are guarded on success.
    run_failure_suite(compiler, report, libraries, build, command, 'primitive')
    # Composite results, nested variants and explicit constructor preconditions are independently guarded.
    run_failure_suite(compiler, report, libraries, build, command, 'composite')
    # Generic owned payloads, absent/error metadata and explicit factories retain independent guards.
    run_failure_suite(compiler, report, libraries, build, command, 'owned')
    # Report/header and newly instantiated owned results reject all failed/default payload access.
    run_failure_suite(compiler, report, libraries, build, command, 'reports')
    # Decoder and inspection progress share the same result type but must reject each failing operation independently.
    run_failure_suite(compiler, report, libraries, build, command, 'assurances')
    # Every public guarantee result instantiation must protect failed/default values, including inspection tuples.
    run_failure_suite(compiler, report, libraries, build, command, 'guarantees')
    # Ticket write, decode and inspection APIs reject progress reads on defaults and actual typed failures.
    run_failure_suite(compiler, report, libraries, build, command, 'tickets')
    # Every public dispute result type and explicit failure construction retain success contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'disputes')
    # Every public package result instantiation and both import identity alternatives retain checked access.
    run_failure_suite(compiler, report, libraries, build, command, 'packages')
    # Guard all public header result instantiations and both source/metadata optional alternatives.
    run_failure_suite(compiler, report, libraries, build, command, 'headers')
    # Parent values and nested component reasons require independent checked alternatives.
    run_failure_suite(compiler, report, libraries, build, command, 'blocks')
    # All Boolean/bitstring result types and public operations retain success-only value access.
    run_failure_suite(compiler, report, libraries, build, command, 'bits')
    # Every collection/scalar result shape keeps failure/default application access guarded.
    run_failure_suite(compiler, report, libraries, build, command, 'collections')
    # Guard every C.2 result and selected work/source/metadata/decoded union alternative independently.
    run_failure_suite(compiler, report, libraries, build, command, 'c2')
    run_failure_suite(compiler, report, libraries, build, command, 'crypto')
    # Guard every default/failed layout result and both wrong alternatives for every metadata field.
    run_failure_suite(compiler, report, libraries, build, command, 'layout')
    # Public commitment and private recursive child-hash results must reject failed/default payload reads.
    run_failure_suite(compiler, report, libraries, build, command, 'trie')
    # Every default/failed component result must reject values, owners, copied records and consumed progress.
    run_failure_suite(compiler, report, libraries, build, command, 'safrole')
    # Public authorization fields and internal framing tuples must reject every default/failed payload read.
    run_failure_suite(compiler, report, libraries, build, command, 'authorization')
    # Chapter-local results and closed source alternatives guard every inactive/default observation.
    run_failure_suite(compiler, report, libraries, build, command, 'consensus')
    # All public result shapes and private scan layouts require success before payload access.
    run_failure_suite(compiler, report, libraries, build, command, 'state_disputes')
    # Public/private results and runtime-selected absent peak copies require exact supported contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'history')
    # Every public/private result and each inactive assignment field must retain its exact contract.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_availability_results.nim', 'availability-results', crypto_library)
    report['availability_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and dynamic absence origins execute independently, retaining their own diagnostics.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in AVAILABILITY_MEMBERS]
        cases += [('absent-'+field, origin, 'assignment.isPresent') for origin in ('default', 'source', 'decoded') for field in ('guarantee', 'registered')]
        for member, origin, sentinel in cases:
            probe_failure(command, report['availability'], [binary, member, origin, availability_fixture],
                          'availability-' + origin + '-' + member, sentinel,
                          origin + ' availability ' + member + ' runtime guard', origin=origin, member=member)
    # Every public result shape and private natural/layout proof requires success before payload access.
    run_failure_suite(compiler, report, libraries, build, command, 'privileges')
    # All public and internal tuple/natural/layout payloads require exact successful selection.
    run_failure_suite(compiler, report, libraries, build, command, 'statistics')
    # Both queue domains and internal count/layout proofs require successful payload selection.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_workqueues_results.nim', 'workqueues-results', crypto_library)
    report['workqueues_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures execute separately so one rejected access cannot conceal another.
        for origin in ('default', 'error'):
            for member in WORKQUEUES_MEMBERS:
                probe_failure(command, report['workqueues'], [binary, member, origin, availability_fixture],
                              'workqueues-' + origin + '-' + member, 'value.status == None',
                              origin + ' workqueues ' + member + ' runtime guard', origin=origin, member=member)
    # Public entry/read/count/pair payloads and internal extent proofs retain exact success contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'outputs')
    # Fixed metadata and encoded entries require exact success, even though records need no retained heap owner.
    run_failure_suite(compiler, report, libraries, build, command, 'accounts')
    # Backend refusals and private alias misuse execute through a test-only observer, never production binaries.
    run_failure_suite(compiler, report, libraries, build, command, 'service_values')
    # Result payloads and every inactive timestamp require supported success/shape contracts.
    run_failure_suite(compiler, report, libraries, build, command, 'requests')
    # Complete composition payloads require exact success, including backend and association failures.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_composition_results.nim', 'composition-results', crypto_observer)
    report['composition_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual and default failures execute separately so one protected read never conceals another.
        for origin in ('default', 'error'):
            for member in COMPOSITION_MEMBERS:
                probe_failure(command, report['composition'], [binary, member, origin, composition_fixture],
                              'composition-' + origin + '-' + member, 'value.status == None',
                              origin + ' composition ' + member + ' runtime guard', origin=origin, member=member)


# Select one independent workload and invalidate stale evidence before any setup or compilation.
def main():
    global BUILD, checks, command, build
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--group', choices=('unit', 'failures'), default='unit')
    args = parser.parse_args()
    # Private reports, caches and logs allow the two workloads to run on independent CI runners.
    BUILD = ROOT/('build/tests/runtime' if args.group == 'unit' else 'build/tests/failures')
    checks = NativeChecks(BUILD)
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
    else:
        # Every runtime family must be populated by this invocation, including after a prior successful run.
        report.update({family: [] for family in FAILURE_COUNTS})
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
                              for path in sorted(sources)}
    # The existing native guarantee suite consumes an independently authored minimal report fixture.
    sys.path.insert(0, str(ROOT/'tests'))
    libraries, quic_fixtures, native_evidence = prepare_libraries(BUILD)
    report.update(native_evidence)
    integration_wires, integration_reload, report['integration_fixtures'] = prepare_integration(BUILD)
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
        fixtures, fixture_evidence = prepare_unit_fixtures(BUILD, quic_fixtures, integration_wires, integration_reload)
        report.update(fixture_evidence)
        run_unit(compiler, report, libraries, fixtures, quic_fixtures, integration_wires)
        step_passed = unit_passed(report)
    else:
        # Contract checks keep their diagnostic predicates and positive controls unchanged.
        run_failures(compiler, report, libraries, availability_fixture, composition_fixture)
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
