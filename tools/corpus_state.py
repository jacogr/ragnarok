# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_state to execute state serialization/composition corpora and record their verdicts.
"""
from functools import partial
from pathlib import Path
import hashlib
import json
from corpus_checks import run_corpus, compare_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]



# This feature owns its shared-build execution position and additional fixture inputs.
CORPORA = CorpusGroup(order=20)

# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def layout_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve the independent C/B/L equations, every hostile header/padding request and labelled historical projections.
    from state_layout_oracle import requests as layout_requests, legacy_singletons
    lines, expected = layout_requests()
    source = BUILD/'layout-requests.txt'
    # The reference computes keys/fields/padding/hash bytes independently before native execution.
    corpus = execute_corpus(ROOT / 'tests/native/state_layout_driver.nim', 'layout-codec',
                        source, lines, expected, 'layout-corpus',
                        metadata=dict(historical_projected_singletons=len(legacy_singletons())),
                        crypto_library=crypto_library)
    announce('independent state-key/node layout and hash corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def trie_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Compare independent unsorted-list partitions, every key divergence bit and labelled historical projections.
    from state_trie_oracle import requests as trie_requests, legacy_maps
    lines, expected = trie_requests()
    source = BUILD/'trie-requests.txt'
    # Every result compares exact root/counts or a typed reason; caller preservation is checked by the adapter.
    corpus = execute_corpus(ROOT / 'tests/native/state_trie_driver.nim', 'trie-codec',
                        source, lines, expected, 'trie-corpus',
                        metadata=dict(historical_projected_maps=len(legacy_maps())),
                        crypto_library=crypto_library)
    announce('independent bounded state trie root corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def safrole_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent entropy/time/roster bytes, malformed inputs, published derived fixtures and partial roots.
    from state_safrole_oracle import requests as safrole_requests, published as safrole_published
    lines, expected = safrole_requests()
    source = BUILD/'safrole-requests.txt'
    # Native fields/consumed counts and roots are compared only with independently authored expectations.
    corpus = execute_corpus(ROOT / 'tests/native/state_safrole_driver.nim', 'safrole-codec',
                        source, lines, expected, 'safrole-corpus',
                        metadata=dict(published_derived_state_sources=len(safrole_published())),
                        crypto_library=crypto_library)
    announce('independent entropy/validator-roster/timeslot state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def authorization_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent ordered core/row equations, malformed inputs, derived fixtures and partial commitments.
    from state_authorization_oracle import requests as authorization_requests, published as authorization_published
    lines, expected = authorization_requests()
    source = BUILD/'authorization-requests.txt'
    # Observe fixed hashes and owner-bound boundaries after destructive caller mutation, comparing independent bytes.
    corpus = execute_corpus(ROOT / 'tests/native/state_authorization_driver.nim', 'authorization-codec',
                        source, lines, expected, 'authorization-corpus',
                        metadata=dict(published_derived_state_sources=len(authorization_published())),
                        crypto_library=crypto_library)
    announce('independent authorization pool/queue state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def consensus_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-4 byte/field equations, derived fixtures and partial single-entry roots.
    from state_consensus_oracle import requests as consensus_requests, published as consensus_published
    lines, expected = consensus_requests()
    source = BUILD/'consensus-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_consensus_driver.nim', 'consensus-codec',
                        source, lines, expected, 'consensus-corpus',
                        metadata=dict(published_derived_state_sources=len(consensus_published())),
                        crypto_library=crypto_library)
    announce('independent chapter-4 Safrole basic state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def state_disputes_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-5 byte/field equations, derived fixtures and partial single-entry roots.
    from state_disputes_oracle import requests as state_disputes_requests, published as state_disputes_published
    lines, expected = state_disputes_requests()
    source = BUILD/'state_disputes-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_disputes_driver.nim', 'state_disputes-codec',
                        source, lines, expected, 'state_disputes-corpus',
                        metadata=dict(published_derived_state_sources=len(state_disputes_published())),
                        crypto_library=crypto_library)
    announce('independent chapter-5 dispute judgment/offender state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def history_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-3 byte/field equations, derived fixtures and partial single-entry roots.
    from state_history_oracle import requests as state_history_requests, published as state_history_published
    lines, expected = state_history_requests()
    source = BUILD/'state_history-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_history_driver.nim', 'state_history-codec',
                        source, lines, expected, 'state_history-corpus',
                        metadata=dict(published_derived_state_sources=len(state_history_published())),
                        crypto_library=crypto_library)
    announce('independent chapter-3 recent history state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def availability_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-10 byte/field equations, derived fixtures and partial single-entry roots.
    from state_availability_oracle import requests as state_availability_requests, published as state_availability_published, published_verdicts as availability_verdicts
    lines, expected = state_availability_requests()
    source = BUILD/'state_availability-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_availability_driver.nim', 'state_availability-codec',
                        source, lines, expected, 'state_availability-corpus',
                        metadata=dict(published_derived_state_sources=len(state_availability_published()),
                                      published_decode_verdicts=availability_verdicts()),
                        crypto_library=crypto_library)
    announce('independent chapter-10 availability assignment state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def privileges_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-12 byte/field equations, derived fixtures and partial single-entry roots.
    from state_privileges_oracle import requests as state_privileges_requests, published as state_privileges_published
    lines, expected = state_privileges_requests()
    source = BUILD/'state_privileges-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_privileges_driver.nim', 'state_privileges-codec',
                        source, lines, expected, 'state_privileges-corpus',
                        metadata=dict(published_derived_state_sources=len(state_privileges_published())),
                        crypto_library=crypto_library)
    announce('independent chapter-12 privileged service state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def statistics_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve independent chapter-13 byte/field equations, derived fixtures and partial single-entry roots.
    from state_statistics_oracle import requests as state_statistics_requests, published_validators as state_statistics_published, trace_evidence as statistics_traces
    lines, expected = state_statistics_requests()
    source = BUILD/'state_statistics-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_statistics_driver.nim', 'state_statistics-codec',
                        source, lines, expected, 'state_statistics-corpus',
                        metadata=dict(published_partial_validator_sources=len(state_statistics_published()),
                                      published_trace_components=statistics_traces(),
                                      gas_encoding_policy="accepted canonical compact naturals; no fallback"),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(corpus['published_trace_components']) == 6 and all(row['complete_component_match'] for row in corpus['published_trace_components'])
    announce('independent chapter-13 activity statistics state corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def workqueues_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Chapters 14/15 retain independent literal, derived JSON and exact raw trace evidence.
    from state_workqueues_oracle import requests as workqueue_requests, published as workqueue_published, published_traces as workqueue_traces, parse as workqueue_parse, wire as workqueue_wire
    lines, expected = workqueue_requests()
    source = BUILD/'workqueues-requests.txt'
    traces = []
    # Whole-component trace replay is separate from sorted JSON-derived mathematical sets.
    for kind, data, config in workqueue_traces():
        rows, consumed, items, dependencies = workqueue_parse(kind, data, config)
        traces.append(dict(kind=kind, bytes=len(data), consumed=consumed, items=items,
                           dependencies=dependencies, sha256=hashlib.sha256(data).hexdigest(),
                           complete_component_match=consumed == len(data) and workqueue_wire(kind, rows) == data))
    # Expected observations come from the independent reference, never a native round trip.
    corpus = execute_corpus(ROOT / 'tests/native/state_workqueues_driver.nim', 'state_workqueues-codec',
                        source, lines, expected, 'state_workqueues-corpus',
                        metadata=dict(published_json_components=len(workqueue_published()),
                                      published_trace_components=traces),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(traces) == 12 and all(row['complete_component_match'] for row in traces)
    announce('independent chapters 14/15 ready/accumulated queue corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def outputs_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Chapter 16 preserves the independent ordered fixed-pair corpus and exact empty published traces.
    from state_outputs_oracle import requests as outputs_requests, published as outputs_published, parse as outputs_parse, wire as outputs_wire, DEFAULT as outputs_default
    lines, expected = outputs_requests()
    source = BUILD/'outputs-requests.txt'
    traces = []
    # Selected trace entries are empty logs; authored cases supply nonempty field/order coverage.
    for entry in outputs_published():
        values, consumed = outputs_parse(entry['wire'], outputs_default)
        traces.append(dict(path=entry['path'], phase=entry['phase'], bytes=len(entry['wire']),
                           items=len(values), consumed=consumed, sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=consumed == len(entry['wire']) and outputs_wire(values) == entry['wire']))
    # All expected fields/bytes/reasons come from independent equations computed before native execution.
    corpus = execute_corpus(ROOT / 'tests/native/state_outputs_driver.nim', 'state_outputs-codec',
                        source, lines, expected, 'state_outputs-corpus',
                        metadata=dict(published_trace_components=traces,
                                      scope='ordered fixed pairs; published traces empty, nonempty coverage authored; no accumulation execution'),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(traces) == 8 and all(row['complete_component_match'] for row in traces)
    announce('independent chapter-16 last accumulation outputs corpus', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_corpus(compiler, report, checks, libraries):
    """Compare genuine current candidate execution against complete independently computed maps."""
    from current_stf_oracle import expected_observations, verify_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    # Freeze all expected inputs/outputs before any native compilation or transition execution.
    expected = expected_observations()
    evidence = verify_observations(expected)
    for identity in ('current_stf', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_driver.nim',
        'current-stf', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  scope='complete current-schema same-epoch empty-body STF; two explicit services')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'current-stf-corpus', expected)
    announce('independent complete current-schema STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_forks_corpus(compiler, report, checks, libraries):
    """Compare independently calculated sibling whole maps through actual fuzzer imports and state queries."""
    from jam_fuzzer_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('jam_fuzzer_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    expected, evidence = expected_observations()
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_forks_driver.nim',
        'jam-fuzzer-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'jam-fuzzer-forks-corpus', expected)
    announce('independent depth-one fuzzer sibling STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_ancestry_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_ancestry_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-ancestry-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_ancestry_driver.nim',
        'jam-fuzzer-ancestry', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-ancestry-corpus', expected)
    announce('independent fuzzer reporting ancestry whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_ancestry_retention_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_ancestry_retention_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry_retention', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-ancestry-retention-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_ancestry_retention_driver.nim',
        'jam-fuzzer-ancestry-retention', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-ancestry-retention-corpus', expected)
    announce('independent fuzzer bounded ancestry retention whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_report_forks_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_report_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry', 'jam_fuzzer_report_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-report-forks-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_report_forks_driver.nim',
        'jam-fuzzer-report-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-report-forks-corpus', expected)
    announce('independent fuzzer nonempty reporting sibling whole STF maps', corpus['passed'])
    return corpus


def run_fuzzer_guest_reference(compiler, report, checks, libraries, reference, identities,
                               *, input_requests=True, profiles=None, forks=False, anchor_checks=False, headers=False):
    """Share exact-input replay builds while each source-owned corpus retains its own frozen reference and verdict."""
    from jam_fuzzer_guest_reference import replay
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in (*identities, 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = replay(reference, input_requests=input_requests, profiles=profiles, forks=forks, anchor_checks=anchor_checks, headers=headers)
    label = 'jam-fuzzer-'+reference.FIXTURE.stem.removeprefix('current-stf-')
    source = checks.folder/(label+'.txt')
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_guest_replay.nim',
        'jam-fuzzer-guest-replay', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], label+'-corpus', expected)
    announce(label+' independent whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_report_guests_corpus(compiler, report, checks, libraries):
    """Compare actual fuzzer report-to-guest execution with independent complete-map STF calculations."""
    import current_stf_report_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects', 'current_stf_report_guests'))


@CORPORA.case
def jam_fuzzer_storage_effects_corpus(compiler, report, checks, libraries):
    """Compare nonempty preimage extrinsics and guest storage replacement/deletion/exception selection."""
    import current_stf_effects_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects',), input_requests=False)


@CORPORA.case
def jam_fuzzer_request_effects_corpus(compiler, report, checks, libraries):
    """Compare selected request creation, forgetting and checkpointed namespace versions through the fuzz backend."""
    import current_stf_request_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_request_lifecycle', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_preimage_effects_corpus(compiler, report, checks, libraries):
    """Compare queued provision relevance and actual canonical preimage fulfillment across guest selections."""
    import current_stf_preimage_provision_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_preimage_provision', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_transfers_corpus(compiler, report, checks, libraries):
    """Execute transfers through fuzz requests against independent complete STF maps."""
    import current_stf_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfers', 'current_stf_report_guests'))


@CORPORA.case
def jam_fuzzer_supervised_transfers_corpus(compiler, report, checks, libraries):
    """Execute supervised transfers through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_transfers', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_forwarded_transfers_corpus(compiler, report, checks, libraries):
    """Execute forwarded transfers through fuzz requests against independent complete STF maps."""
    import current_stf_forwarded_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_forwarded_transfers', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_transfer_pools_corpus(compiler, report, checks, libraries):
    """Execute transfer pools through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_pools_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_pools', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_transfer_admission_corpus(compiler, report, checks, libraries):
    """Execute transfer admission through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_admission_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_admission', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_transfer_memos_corpus(compiler, report, checks, libraries):
    """Execute transfer memos through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_memos_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_memos', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_service_upgrades_corpus(compiler, report, checks, libraries):
    """Execute service upgrades through fuzz requests against independent complete STF maps."""
    import current_stf_service_upgrades_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_upgrades', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervisor_lifecycle_corpus(compiler, report, checks, libraries):
    """Execute supervisor lifecycle through fuzz requests against independent complete STF maps."""
    import current_stf_supervisor_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervisor_lifecycle', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_service_creation_corpus(compiler, report, checks, libraries):
    """Execute service creation through fuzz requests against independent complete STF maps."""
    import current_stf_service_creation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_creation', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_service_ejection_corpus(compiler, report, checks, libraries):
    """Execute service ejection through fuzz requests against independent complete STF maps."""
    import current_stf_service_ejection_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_ejection', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_manager_handoff_corpus(compiler, report, checks, libraries):
    """Execute manager handoff through fuzz requests against independent complete STF maps."""
    import current_stf_manager_handoff_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_manager_handoff', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_authorization_assign_corpus(compiler, report, checks, libraries):
    """Execute authorization assign through fuzz requests against independent complete STF maps."""
    import current_stf_authorization_assign_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in json.loads(reference.FIXTURE.read_text())['max_service_code_sizes']]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_authorization_assign', 'current_stf_transfers'), profiles=profiles)


@CORPORA.case
def jam_fuzzer_role_precedence_corpus(compiler, report, checks, libraries):
    """Execute role precedence through fuzz requests against independent complete STF maps."""
    import current_stf_role_precedence_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in [json.loads(reference.FIXTURE.read_text())['max_service_code_size']]*len(reference.PROFILES)]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_role_precedence', 'current_stf_transfers'), profiles=profiles)


@CORPORA.case
def jam_fuzzer_validator_designation_corpus(compiler, report, checks, libraries):
    """Execute validator designation through fuzz requests against independent complete STF maps."""
    import current_stf_validator_designation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in [json.loads(reference.FIXTURE.read_text())['max_service_code_size']]*len(reference.PROFILES)]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_validator_designation', 'current_stf_transfers'), profiles=profiles)


@CORPORA.case
def jam_fuzzer_bless_allowances_corpus(compiler, report, checks, libraries):
    """Execute bless allowances through fuzz requests against independent complete STF maps."""
    import current_stf_bless_allowances_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_bless_allowances', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_allowance_revocation_corpus(compiler, report, checks, libraries):
    """Execute allowance revocation through fuzz requests against independent complete STF maps."""
    import current_stf_allowance_revocation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_allowance_revocation', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_allowance_eligibility_corpus(compiler, report, checks, libraries):
    """Execute allowance eligibility through fuzz requests against independent complete STF maps."""
    import current_stf_allowance_eligibility_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_allowance_eligibility', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervised_storage_corpus(compiler, report, checks, libraries):
    """Execute supervised storage through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_storage_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_storage', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervised_requests_corpus(compiler, report, checks, libraries):
    """Execute supervised requests through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_requests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_requests', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervised_upgrades_corpus(compiler, report, checks, libraries):
    """Execute supervised upgrades through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_upgrades_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_upgrades', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervised_conflicts_corpus(compiler, report, checks, libraries):
    """Execute supervised conflicts through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_conflicts_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_conflicts', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_supervised_handoff_corpus(compiler, report, checks, libraries):
    """Execute supervised handoff through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_handoff_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_handoff', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_reserved_creation_corpus(compiler, report, checks, libraries):
    """Execute reserved creation through fuzz requests against independent complete STF maps."""
    import current_stf_reserved_creation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_reserved_creation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))


@CORPORA.case
def jam_fuzzer_child_readiness_corpus(compiler, report, checks, libraries):
    """Execute child readiness through fuzz requests against independent complete STF maps."""
    import current_stf_child_readiness_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_readiness', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_child_retirement_corpus(compiler, report, checks, libraries):
    """Execute child retirement through fuzz requests against independent complete STF maps."""
    import current_stf_child_retirement_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_retirement', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))


@CORPORA.case
def jam_fuzzer_child_recreation_corpus(compiler, report, checks, libraries):
    """Execute child recreation through fuzz requests against independent complete STF maps."""
    import current_stf_child_recreation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_recreation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))


@CORPORA.case
def jam_fuzzer_incarnation_authority_corpus(compiler, report, checks, libraries):
    """Execute incarnation authority through fuzz requests against independent complete STF maps."""
    import current_stf_incarnation_authority_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_incarnation_authority', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_foreign_creation_corpus(compiler, report, checks, libraries):
    """Execute foreign creation through fuzz requests against independent complete STF maps."""
    import current_stf_foreign_creation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_foreign_creation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))


@CORPORA.case
def jam_fuzzer_foreign_transfers_corpus(compiler, report, checks, libraries):
    """Execute foreign transfers through fuzz requests against independent complete STF maps."""
    import current_stf_foreign_transfers_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_foreign_transfers', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))


@CORPORA.case
def jam_fuzzer_queued_incarnation_corpus(compiler, report, checks, libraries):
    """Execute queued incarnation through fuzz requests against independent complete STF maps."""
    import current_stf_queued_incarnation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_queued_incarnation', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_dependency_waves_corpus(compiler, report, checks, libraries):
    """Execute dependency waves through fuzz requests against independent complete STF maps."""
    import current_stf_dependency_waves_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects', 'current_stf_report_guests', 'current_stf_dependency_waves'))


@CORPORA.case
def jam_fuzzer_budget_retention_corpus(compiler, report, checks, libraries):
    """Execute budget retention through fuzz requests against independent complete STF maps."""
    import current_stf_budget_retention_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_budget_retention', 'current_stf_dependency_waves'))


@CORPORA.case
def jam_fuzzer_gas_exits_corpus(compiler, report, checks, libraries):
    """Execute gas exits through fuzz requests against independent complete STF maps."""
    import current_stf_gas_exits_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_gas_exits', 'current_stf_report_guests'))


@CORPORA.case
def jam_fuzzer_late_code_corpus(compiler, report, checks, libraries):
    """Execute late code through fuzz requests against independent complete STF maps."""
    import current_stf_late_code_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_late_code', 'current_stf_report_guests'))


@CORPORA.case
def jam_fuzzer_epoch_drain_corpus(compiler, report, checks, libraries):
    """Execute epoch drain through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_drain_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_drain', 'current_stf_dependency_waves'))


@CORPORA.case
def jam_fuzzer_ready_expiry_corpus(compiler, report, checks, libraries):
    """Execute ready expiry through fuzz requests against independent complete STF maps."""
    import current_stf_ready_expiry_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_ready_expiry', 'current_stf_epoch_drain'))


@CORPORA.case
def jam_fuzzer_epoch_lifecycle_corpus(compiler, report, checks, libraries):
    """Execute epoch lifecycle through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_lifecycle', 'current_stf_transfers'))


@CORPORA.case
def jam_fuzzer_epoch_composition_corpus(compiler, report, checks, libraries):
    """Execute epoch composition through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_composition_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=4096 if 107 <= mode <= 122 and mode != 112 else 512,
                                deposits=(7, 1, 100) if mode in range(123, 131) or mode in range(141, 155) else (0, 0, 0))
                for _, _, mode in reference.CASES]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_composition', 'current_stf_transfers'), profiles=profiles)


@CORPORA.case
def jam_fuzzer_guest_forks_corpus(compiler, report, checks, libraries):
    """Compare guest-bearing siblings and original-last continuation with independent complete maps."""
    import jam_fuzzer_guest_forks_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_report_guests', 'jam_fuzzer_guest_forks'), forks=True)


@CORPORA.case
def jam_fuzzer_parameter_aging_corpus(compiler, report, checks, libraries):
    """Use authoritative GP lookup age for genuine reporting, strict aging and contradictory-policy controls."""
    import jam_fuzzer_parameter_aging_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_preimage_aging', 'jam_fuzzer_parameter_aging'),
        profiles=[host_parameters(lookup_age=reference.LOOKUP_AGE)] * len(reference.source.PROFILES),
        anchor_checks=True)


@CORPORA.case
def jam_fuzzer_seed_guests_corpus(compiler, report, checks, libraries):
    """Execute exact genesis-like seed pairs while retaining both GP chronology checks and production isolation."""
    import jam_fuzzer_seed_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_effects', 'jam_fuzzer_seed_guests'), headers=True)


@CORPORA.case
def jam_fuzzer_checkpoint_guests_corpus(compiler, report, checks, libraries):
    """Resume independently authored whole-map guest checkpoints with exact minimal ancestry evidence."""
    import jam_fuzzer_checkpoint_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_report_guests', 'jam_fuzzer_checkpoint_guests'), headers=True)


@CORPORA.case
def jam_fuzzer_stf_corpus(compiler, report, checks, libraries):
    """Compare actual fuzzer requests and whole-state replies with frozen independent STF maps."""
    from current_stf_oracle import expected_observations, verify_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    # Freeze complete independent pre/block/post expectations before the backend is built or run.
    expected = expected_observations()
    evidence = verify_observations(expected)
    for identity in ('current_stf', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_stf_driver.nim',
        'jam-fuzzer-stf', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence,
                  scope='native fuzzer requests; two linear current-profile chains; whole GetState maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'jam-fuzzer-stf-corpus', expected)
    announce('independent whole-map JAM fuzzer STF backend', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_effects_corpus(compiler, report, checks, libraries):
    """Compare complete preimage/storage/yield/checkpoint successor maps with independent equations."""
    from current_stf_effects_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_effects', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Independent code assembly, gas simulation, credentials and all successor bytes precede native execution.
    expected, evidence = expected_observations()
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_effects_driver.nim',
        'current-stf-effects', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  scope='five two-block current STF chains; nonempty preimages and literal guest effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'current-stf-effects-corpus', expected)
    announce('independent nonempty-extrinsic and guest-effect whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_epoch_corpus(compiler, report, checks, libraries):
    """Execute epoch rotation, cutoff markers and real RingVRF admission against independent complete maps."""
    from current_stf_epoch_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Frozen Ring/KZG witnesses are input data; every score, Thin credential and successor map is independently calculated.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-epoch-proofs.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_epoch_driver.nim',
        'current-stf-epoch', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-epoch-corpus', expected)
    announce('independent epoch/ticket whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_epoch_forks_corpus(compiler, report, checks, libraries):
    """Execute epoch rotation, cutoff markers and real RingVRF admission against independent complete maps."""
    from jam_fuzzer_epoch_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'jam_fuzzer_epoch_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Frozen Ring/KZG witnesses are input data; every score, Thin credential and successor map is independently calculated.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-epoch-forks-proofs.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_epoch_forks_driver.nim',
        'jam-fuzzer-epoch-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-epoch-forks-corpus', expected)
    announce('independent epoch/ticket whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_population_corpus(compiler, report, checks, libraries):
    """Compare real culprit evidence, independently sized validator rosters and every complete successor byte."""
    from current_stf_population_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'current_stf_population', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Original-map reconstruction, OpenSSL credentials and independent posterior maps precede native execution.
    expected, evidence = expected_observations()
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_population_driver.nim',
        'current-stf-population', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence, dispute_refusals=3,
                  null_author_refusals=1, profile_refusals=54, profile_admissions=12)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], '--run'], 'current-stf-population-corpus', expected)
    announce('independent offender/population whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_eviction_corpus(compiler, report, checks, libraries):
    """Verify whole-map contest replacement and typed non-retention with fixed Ring inputs."""
    from current_stf_eviction_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'current_stf_eviction', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # The reference decides the single eviction, every winner and all output bytes before the driver runs.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-eviction-proofs.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_eviction_driver.nim',
        'current-stf-eviction', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence, nonretention_refusals=2,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-eviction-corpus', expected)
    announce('independent ticket contest eviction whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_verdict_corpus(compiler, report, checks, libraries):
    """Compare signed verdict/fault judgments, assignment cancellation and every complete successor byte."""
    from current_stf_verdict_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'current_stf_population', 'current_stf_verdicts', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Independent signatures, parent-selected quorums and all expected maps exist before the native build/run.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-verdict-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_verdict_driver.nim',
        'current-stf-verdicts', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  reference='OpenSSL Ed25519, mathematical Thin and independent complete-map verdict/fault STF')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-verdict-corpus', expected)
    announce('independent verdict/fault whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_reporting_corpus(compiler, report, checks, libraries):
    """Compare real guarantee/assurance publication with independent complete maps and contextual refusals."""
    from current_stf_reporting_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # OpenSSL signatures, mathematical Thin, report projections and every map exist before native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-reporting-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_reporting_driver.nim',
        'current-stf-reporting', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  reference='OpenSSL Ed25519, mathematical Thin and independent report/availability whole-map STF')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-reporting-corpus', expected)
    announce('independent guarantee/assurance whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_epoch_reporting_corpus(compiler, report, checks, libraries):
    """Compare epoch-boundary guarantee/assurance publication with independent complete maps and contextual refusals."""
    from current_stf_epoch_reporting_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_epoch', 'current_stf_epoch_reporting', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # OpenSSL signatures, mathematical Thin, report projections and every map exist before native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-epoch-reporting-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_epoch_reporting_driver.nim',
        'current-stf-epoch-reporting', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  reference='OpenSSL Ed25519, mathematical Thin and independent report/availability whole-map STF')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-epoch-reporting-corpus', expected)
    announce('independent epoch/reporting whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_report_guests_corpus(compiler, report, checks, libraries):
    """Compare report-driven real guest execution against independently calculated complete maps."""
    from current_stf_report_guests_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_effects', 'current_stf_report_guests', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # All mathematical guest effects, gas charges, signed children and roots precede native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-report-guests-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-report-guests', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  reference='mathematical Thin, OpenSSL Ed25519, literal guest semantics and independent GP gas')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-report-guests-corpus', expected)
    announce('independent report-driven guest whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_dependency_waves_corpus(compiler, report, checks, libraries):
    """Compare deferred E/Q priority waves, cycles and gas continuation against complete independent maps."""
    from current_stf_dependency_waves_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_effects', 'current_stf_report_guests', 'current_stf_dependency_waves', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Shared genuine driver consumes only bodies; independent E/Q/accseq maps and traces already exist.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-dependency-waves-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-dependency-waves', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP E/Q/accseq, literal guest semantics, mathematical Thin and OpenSSL Ed25519')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-dependency-waves-corpus', expected)
    announce('independent deferred dependency-wave whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_budget_retention_corpus(compiler, report, checks, libraries):
    """Compare budget-exhausted ready retention and later drain against independently calculated full maps."""
    from current_stf_budget_retention_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_budget_retention', 'current_stf_dependency_waves', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-budget-retention-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-budget-retention', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP E/Q/accseq and literal guest gas; whole-map retention/drain')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-budget-retention-corpus', expected)
    announce('independent budget-retention whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_gas_exits_corpus(compiler, report, checks, libraries):
    """Compare gas-limited guest exits and pooled operands against independently calculated full maps."""
    from current_stf_gas_exits_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_gas_exits', 'current_stf_report_guests', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-gas-exits-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-gas-exits', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent prepaid-block/host gas, pooled budgets and literal guest implications')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-gas-exits-corpus', expected)
    announce('independent gas-exits whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_late_code_corpus(compiler, report, checks, libraries):
    """Compare late code-preimage phase ordering against independently calculated full maps."""
    from current_stf_late_code_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_late_code', 'current_stf_report_guests', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-late-code-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-late-code', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent missing-code skips, late fulfillment and literal guest implications')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-late-code-corpus', expected)
    announce('independent late-code whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_epoch_drain_corpus(compiler, report, checks, libraries):
    """Compare epoch-spanning deferred guest execution against independently calculated full maps."""
    from current_stf_epoch_drain_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch_drain', 'current_stf_dependency_waves', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-epoch-drain-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-epoch-drain', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent Safrole/header equations, deferred budgets and literal guest effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-epoch-drain-corpus', expected)
    announce('independent epoch-drain whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_ready_expiry_corpus(compiler, report, checks, libraries):
    """Compare skipped-time ready expiry after actual execution against independently calculated full maps."""
    from current_stf_ready_expiry_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_ready_expiry', 'current_stf_epoch_drain', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-ready-expiry-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-ready-expiry', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP Q/accseq then elapsed-slot expiry and mathematical epoch headers')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-ready-expiry-corpus', expected)
    announce('independent ready-expiry whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_transfers_corpus(compiler, report, checks, libraries):
    """Compare deferred transfer delivery and terminal selection against independently calculated full maps."""
    from current_stf_transfers_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_transfers', 'current_stf_report_guests', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-transfers-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-transfers', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent literal transfer debit/credit, prepaid gas, terminal selection and full maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-transfers-corpus', expected)
    announce('independent transfers whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_transfers_corpus(compiler, report, checks, libraries):
    """Compare supervised transfer scheduling and exact incarnation fallbacks against independently calculated full maps."""
    from current_stf_supervised_transfers_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_transfers', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-transfers-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-transfers', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP stable partition, declared/actual accseq budgets and full transfer effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-transfers-corpus', expected)
    announce('independent supervised-transfer whole STF maps', corpus['passed'])
    return corpus





@CORPORA.case
def current_stf_forwarded_transfers_corpus(compiler, report, checks, libraries):
    """Compare repeated forwarding and transfer-only gas exits against independently calculated full maps."""
    from current_stf_forwarded_transfers_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_forwarded_transfers', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-forwarded-transfers-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-forwarded-transfers', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent accseq forwarding, prepaid gas, exceptional selection and transfer-only effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-forwarded-transfers-corpus', expected)
    announce('independent forwarded-transfer whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_transfer_pools_corpus(compiler, report, checks, libraries):
    """Compare direct and deferred balance-pool combinations against independently calculated full maps."""
    from current_stf_transfer_pools_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_transfer_pools', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-transfer-pools-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-transfer-pools', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent transfer pool selection, direct-credit authority and full participant maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-transfer-pools-corpus', expected)
    announce('independent transfer-pool whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_transfer_admission_corpus(compiler, report, checks, libraries):
    """Compare transfer admission and exact host/recipient gas boundaries against independently calculated full maps."""
    from current_stf_transfer_admission_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_transfer_admission', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-transfer-admission-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-transfer-admission', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent endpoint/funding/memo predicates, host gas and prepaid recipient blocks')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-transfer-admission-corpus', expected)
    announce('independent transfer-admission whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_transfer_memos_corpus(compiler, report, checks, libraries):
    """Compare memo-driven fetched storage and yielded outputs against independently calculated full maps."""
    from current_stf_transfer_memos_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_transfer_memos', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-transfer-memos-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-transfer-memos', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent C.2 input framing, fetch slices/gas, write footprint and C16/history outputs')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-transfer-memos-corpus', expected)
    announce('independent transfer-memo whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_service_upgrades_corpus(compiler, report, checks, libraries):
    """Compare self-upgrade selection and later current-code invocation against independently calculated full maps."""
    from current_stf_service_upgrades_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_service_upgrades', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-service-upgrades-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-service-upgrades', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent self-upgrade metadata, prior-code lookup, missing code and host gas')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-service-upgrades-corpus', expected)
    announce('independent service-upgrade whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervisor_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare supervisor reassignment and current protected-funding authority against independently calculated full maps."""
    from current_stf_supervisor_lifecycle_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervisor_lifecycle', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervisor-lifecycle-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervisor-lifecycle', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent self-supervisor mutation, protected funding, checkpoint selection and whole maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervisor-lifecycle-corpus', expected)
    announce('independent supervisor-lifecycle whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_service_creation_corpus(compiler, report, checks, libraries):
    """Compare public creation cursors and child namespace publication against independently calculated full maps."""
    from current_stf_service_creation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_service_creation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-service-creation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-service-creation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent compact entropy seed, public cursor, child metadata and code-request maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-service-creation-corpus', expected)
    announce('independent service-creation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_request_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare selected solicit/forget namespaces and exact reserved footprints against independent full maps."""
    from current_stf_request_lifecycle_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_request_lifecycle', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-request-lifecycle-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-request-lifecycle', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP solicit/forget, checkpoint selection and full request maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-request-lifecycle-corpus', expected)
    announce('independent request lifecycle whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_preimage_provision_corpus(compiler, report, checks, libraries):
    """Compare selected queued provision relevance and canonical fulfillment against independent complete maps."""
    from current_stf_preimage_provision_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_preimage_provision', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-preimage-provision-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-preimage-provision', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP queued provisions, selected request relevance and complete maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-preimage-provision-corpus', expected)
    announce('independent provision lifecycle whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_service_ejection_corpus(compiler, report, checks, libraries):
    """Compare selected empty-junior ejection and both-pool refund against independent complete maps."""
    from current_stf_service_ejection_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_service_ejection', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-service-ejection-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-service-ejection', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP empty service ejection and exactly-once liquid refund')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-service-ejection-corpus', expected)
    announce('independent service ejection whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_manager_handoff_corpus(compiler, report, checks, libraries):
    """Compare sole-manager role handoff and sequential authority against independent full maps."""
    from current_stf_manager_handoff_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_manager_handoff', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-manager-handoff-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-manager-handoff', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP sole-manager handoff, authority recheck and checkpoint selection')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-manager-handoff-corpus', expected)
    announce('independent manager handoff whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_checkpoint_replay_corpus(compiler, report, checks, libraries):
    """Compare five exact independent lifecycle transcripts after full checkpoint reconstruction at every block."""
    from current_stf_checkpoint_replay_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_checkpoint_replay', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-checkpoint-replay-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-checkpoint-replay', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent unchanged lifecycle equations across new full-store and chain owners')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-checkpoint-replay-corpus', expected)
    announce('independent full checkpoint replay STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_epoch_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare queued provision/request lifecycle with independently derived epoch rotation and signed boundary markers."""
    from current_stf_epoch_lifecycle_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch_lifecycle', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-epoch-lifecycle-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-epoch-lifecycle', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP epoch rotation composed with request relevance and selected provision histories')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-epoch-lifecycle-corpus', expected)
    announce('independent epoch lifecycle whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_storage_corpus(compiler, report, checks, libraries):
    """Compare supervised foreign storage and inactive-target publication against independent full maps."""
    from current_stf_supervised_storage_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_storage', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-storage-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-storage', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP supervised storage selection, incarnation authority and full maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-storage-corpus', expected)
    announce('independent supervised storage whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_requests_corpus(compiler, report, checks, libraries):
    """Compare supervised foreign request selection, canonical histories and complete reservation footprints."""
    from current_stf_supervised_requests_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_requests', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-requests-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-requests', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP foreign solicit/forget selection, checkpoint histories and exact whole maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-requests-corpus', expected)
    announce('independent supervised requests whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_upgrades_corpus(compiler, report, checks, libraries):
    """Compare supervised upgrades, minimum gas and subsequent junior current-code lookup against full maps."""
    from current_stf_supervised_upgrades_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_upgrades', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-upgrades-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-upgrades', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP foreign upgrade selection, honest code availability and junior execution')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-upgrades-corpus', expected)
    announce('independent supervised upgrades whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_conflicts_corpus(compiler, report, checks, libraries):
    """Compare parallel supervisor/junior conflicts, selected account precedence and retained provisions against whole maps."""
    from current_stf_supervised_conflicts_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_conflicts', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-conflicts-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-conflicts', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP N annulment, M account selection, retained gas/provisions and discarded yield')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-conflicts-corpus', expected)
    announce('independent supervised conflicts whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_supervised_handoff_corpus(compiler, report, checks, libraries):
    """Compare original-role foreign supervisor handoff and immediate write-authority loss against complete maps."""
    from current_stf_supervised_handoff_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_supervised_handoff', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-supervised-handoff-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-supervised-handoff', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP prior-role M selection and current-context supervisor authority')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-supervised-handoff-corpus', expected)
    announce('independent supervised handoff whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_authorization_assign_corpus(compiler, report, checks, libraries):
    """Compare ordered authorization queue replacement, handoff and same-block posterior-queue pools against full maps."""
    from current_stf_authorization_assign_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_authorization_assign', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-authorization-assign-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-authorization-assign', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP assigner handoff, posterior queue selection and complete C1/C2/C12 maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-authorization-assign-corpus', expected)
    announce('independent authorization assignment whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_role_precedence_corpus(compiler, report, checks, libraries):
    """Compare simultaneous manager/assigner GP R precedence and original-role queue publication against full maps."""
    from current_stf_role_precedence_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_role_precedence', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-role-precedence-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-role-precedence', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP R original-role precedence, selected terminal globals and posterior queue pools')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-role-precedence-corpus', expected)
    announce('independent privileged role precedence whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_validator_designation_corpus(compiler, report, checks, libraries):
    """Compare selected designation through two epoch rotations with exact signed headers and complete maps."""
    from current_stf_validator_designation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_validator_designation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-validator-designation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-validator-designation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP designation selection, attributed ring inputs and staging/pending/active epoch equations')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-validator-designation-corpus', expected)
    announce('independent validator designation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_reserved_creation_corpus(compiler, report, checks, libraries):
    """Compare reserved-ID creation with independently calculated deposits, four pool combinations and repeated admission."""
    from current_stf_reserved_creation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_reserved_creation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-reserved-creation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-reserved-creation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP reserved creation, integer deposit thresholds, exact debit/credit pools and selected account maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-reserved-creation-corpus', expected)
    announce('independent funded reserved creation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_child_readiness_corpus(compiler, report, checks, libraries):
    """Compare public child creation, same-invocation code provision and later execution against independent maps."""
    from current_stf_child_readiness_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_child_readiness', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-child-readiness-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-child-readiness', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP public IDs, selected creation/provision pairs, exact request histories and actual gas')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-child-readiness-corpus', expected)
    announce('independent child readiness whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_preimage_aging_corpus(compiler, report, checks, libraries):
    """Compare strict request expiry, live preimage retention and restored-history compaction against independent maps."""
    from current_stf_preimage_aging_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_preimage_aging', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-preimage-aging-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-preimage-aging', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent widened strict-expiry equations, history transitions, exact reservation release and selected maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-preimage-aging-corpus', expected)
    announce('independent preimage aging whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_child_retirement_corpus(compiler, report, checks, libraries):
    """Compare funded child birth, pending reservation cleanup, same-slot eject refusal and later pool refunds."""
    from current_stf_child_retirement_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_child_retirement', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-child-retirement-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-child-retirement', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP birth/forget/eject chronology, four funding pools, atomic refund and full maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-child-retirement-corpus', expected)
    announce('independent child retirement whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_child_recreation_corpus(compiler, report, checks, libraries):
    """Compare reserved-ID reuse after retirement with fresh incarnation metadata, Q membership and exact funding pools."""
    from current_stf_child_recreation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_child_recreation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-child-recreation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-child-recreation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP old-incarnation deletion, fresh creation/minima/reservations, funding and checkpoint selection')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-child-recreation-corpus', expected)
    announce('independent child recreation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_profile_replay_corpus(compiler, report, checks, libraries):
    """Compare full-store reconstruction across explicit code-size, deposit, aging and supervisor lifecycle profiles."""
    from current_stf_profile_replay_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_profile_replay', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-profile-replay-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-profile-replay', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent equation-family maps, exact checkpoint reconstruction and unchanged signed continuation under each declared profile')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-profile-replay-corpus', expected)
    announce('independent current-profile checkpoint continuation maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_epoch_composition_corpus(compiler, report, checks, libraries):
    """Compare supervisor, privileged-queue and funded lifecycle effects across signed epoch boundaries and fresh-store continuation."""
    from current_stf_epoch_composition_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch_composition', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-epoch-composition-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-epoch-composition', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent epoch/header/assurance equations composed with supervisor selection, posterior queues and funded lifecycle effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-epoch-composition-corpus', expected)
    announce('independent epoch composition whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_bless_allowances_corpus(compiler, report, checks, libraries):
    """Compare nonempty bless publication, canonical input sets and later always-accumulate scheduling against independent maps."""
    from current_stf_bless_allowances_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_bless_allowances', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-bless-allowances-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-bless-allowances', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP initial allowance scheduling, raw bless charging, canonical dictionaries and exact whole-map effects')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-bless-allowances-corpus', expected)
    announce('independent nonempty bless allowance whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_allowance_revocation_corpus(compiler, report, checks, libraries):
    """Compare scheduled manager takeover, actual allowance revocation and fresh report-driven reauthorization."""
    from current_stf_allowance_revocation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_allowance_revocation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-allowance-revocation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-allowance-revocation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent original-manager selection, initial free dictionary, empty-operand gas and selected revocation maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-allowance-revocation-corpus', expected)
    announce('independent scheduled allowance revocation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_allowance_eligibility_corpus(compiler, report, checks, libraries):
    """Compare zero/exact free-gas membership, basic-block charging and genuine unavailable-code eligibility."""
    from current_stf_allowance_eligibility_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_allowance_eligibility', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-allowance-eligibility-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-allowance-eligibility', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent free-dictionary keys, exact basic-block gas threshold, unavailable-code rules and complete maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-allowance-eligibility-corpus', expected)
    announce('independent allowance eligibility whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_incarnation_authority_corpus(compiler, report, checks, libraries):
    """Compare actual supervisor retirement/recreation, common-prior authority refusal and later explicit incarnation rebinding."""
    from current_stf_incarnation_authority_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_incarnation_authority', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-incarnation-authority-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-incarnation-authority', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent old/new supervisor incarnations, original-context N/M selection, real provision and exact foreign writes')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-incarnation-authority-corpus', expected)
    announce('independent recreated supervisor authority whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_foreign_creation_corpus(compiler, report, checks, libraries):
    """Compare foreign-funded creation, selected source pools and parallel junior annulment against independent complete maps."""
    from current_stf_foreign_creation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_foreign_creation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-foreign-creation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-foreign-creation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent GP foreign funding, four pools, N/M source selection and exactly-once admission/debit')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-foreign-creation-corpus', expected)
    announce('independent foreign-funded creation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_foreign_transfers_corpus(compiler, report, checks, libraries):
    """Compare foreign direct transfers, endpoint pool conservation and parallel junior annulment."""
    from current_stf_foreign_transfers_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_foreign_transfers', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-foreign-transfers-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-foreign-transfers', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent foreign-source/direct-credit equations, original-context N/M selection and exact gas/counts')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-foreign-transfers-corpus', expected)
    announce('independent foreign direct transfer whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_queued_incarnation_corpus(compiler, report, checks, libraries):
    """Compare exact queued old-incarnation report retention and current-code execution after real service recreation."""
    from current_stf_queued_incarnation_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_queued_incarnation', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-queued-incarnation-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-queued-incarnation', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent pending-report identity, current Psi_A code lookup, common-prior rebinding and selected successor maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-queued-incarnation-corpus', expected)
    announce('independent queued incarnation whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_interchange_corpus(compiler, report, checks, libraries):
    """Compare complete current-profile logical export, fresh-store reload and exact-source startup across seven STF families."""
    from current_stf_interchange_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_interchange', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-interchange-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-interchange', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent authored raw-identity enumeration, exact namespace coverage and frozen complete STF maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-interchange-corpus', expected)
    announce('independent current-profile logical interchange whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def state_trace_wire_corpus(compiler, report, checks, libraries):
    """Compare published RawState wire prefixes, complete current STF maps and typed malformed-input refusals."""
    from state_trace_wire_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, digest in FIXTURE_CONTRACTS['state_trace_wire'][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Freeze independently calculated source and full-map evidence before execution.
    requests, expected, evidence = expected_observations()
    return run_corpus(checks.build, checks.command, compiler,
        ROOT/'tests/native/state_trace_wire_driver.nim', 'state-trace-wire',
        checks.folder/'state-trace-wire-requests.txt', requests, expected, 'state-trace-wire-corpus',
        metadata=evidence, crypto_library=libraries['crypto'])


@CORPORA.case
def state_trace_step_corpus(compiler, report, checks, libraries):
    """Compare complete published TraceStep wires, exact typed failures and independent full pre/post maps."""
    from state_trace_step_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('state_trace_step', 'state_trace_step_answers'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Independent fixture identities precede all native execution.
    requests, expected, evidence = expected_observations()
    return run_corpus(checks.build, checks.command, compiler,
        ROOT/'tests/native/state_trace_step_driver.nim', 'state-trace-step',
        checks.folder/'state-trace-step-requests.txt', requests, expected, 'state-trace-step-corpus',
        metadata=evidence, crypto_library=libraries['crypto'])



@CORPORA.case
def current_stf_trace_import_corpus(compiler, report, checks, libraries):
    """Compare actual authenticated trace import, complete advertised pre/post maps and typed refusal isolation."""
    from current_stf_trace_import_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_trace_import', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-trace-import-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-trace-import', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent published full trace framing, exact signed blocks/whole STF maps and wrong-map/seal refusals')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-trace-import-corpus', expected)
    announce('independent authenticated trace import whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_trace_files_corpus(compiler, report, checks, libraries):
    """Compare exact bounded file-backed current STF imports and independent complete-map/refusal observations."""
    from current_stf_trace_files_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_trace_files', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Frozen independent evidence precedes materialization and native execution.
    requests, expected, evidence = expected_observations()
    files = checks.folder/'current-stf-trace-inputs'
    files.mkdir(exist_ok=True)
    invoke = []
    ordinal = 0
    for line in requests:
        if line.startswith('T '):
            path = files/('step-'+str(ordinal).zfill(4)+'.bin')
            path.write_bytes(bytes.fromhex(line[2:]))
            assert hashlib.sha256(path.read_bytes()).hexdigest() == evidence['traces']['file_sha256'][ordinal]
            invoke.append('F '+str(path.resolve()).encode().hex())
            ordinal += 1 # A hexadecimal path transport preserves spaces without inventing another trace file encoding.
        else:
            invoke.append(line) # Actual original-mode declarations preserve the exact explicitly configured profile.
    assert ordinal == evidence['files']
    source = checks.folder/'current-stf-trace-files-requests.txt'
    source.write_text('\n'.join(invoke)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-trace-files', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent exact published files, signed STF blocks/complete maps and refusal isolation')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-trace-files-corpus', expected)
    announce('independent bounded-file current STF whole maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_trace_genesis_corpus(compiler, report, checks, libraries):
    """Compare independently anchored published Genesis bootstrap and exact current-profile STF successors."""
    from current_stf_trace_genesis_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_trace_genesis', 'current_stf_transfers', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-trace-genesis-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_report_guests_driver.nim',
        'current-stf-trace-genesis', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  reference='independent Genesis header/root anchors, explicit full-profile bootstrap and exact signed STF maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-trace-genesis-corpus', expected)
    announce('independent anchored Genesis whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def current_stf_trace_command_corpus(compiler, report, checks, libraries):
    """Compare the public offline command against independent full-profile Genesis/trace files and typed refusals."""
    from current_stf_trace_command_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, digest in FIXTURE_CONTRACTS['current_stf_trace_command'][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Freeze exact independent input/configuration/output evidence before native policy-input generation.
    jobs, expected, evidence = expected_observations()
    invoke = []
    manifest = []
    for ordinal, job in enumerate(jobs):
        folder = checks.folder/'operator bundles'/('case-'+str(ordinal).zfill(4))
        folder.mkdir(parents=True, exist_ok=True)
        chain = folder/'chain.json'
        genesis = folder/'genesis.bin'
        chain.write_text(job['config'])
        genesis.write_bytes(job['genesis'])
        paths = [chain, genesis]
        for index, wire in enumerate(job['steps']):
            path = folder/('step-'+str(index).zfill(4)+'.bin')
            path.write_bytes(wire)
            paths.append(path) # Only independent authored bytes are materialized; filenames carry no profile or expected-success authority.
        invoke.append(' '.join(str(path.resolve()).encode().hex() for path in paths))
        manifest.append(dict(chain=str(chain.resolve()),genesis=str(genesis.resolve()),
            traces=[str(path.resolve()) for path in paths[2:]],expected=expected[ordinal]))
    policy = checks.folder/'current-stf-command-policy.txt'
    (checks.folder/'operator-manifest.json').write_text(json.dumps(
        dict(policy=str(policy.resolve()),cases=manifest),indent=2)+'\n')
    source = checks.folder/'current-stf-trace-command-requests.txt'
    source.write_text('\n'.join(invoke)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_trace_command_driver.nim',
        'current-stf-trace-command',crypto_library=libraries['crypto'],native_libraries=(libraries['bandersnatch'],),quic_library=libraries['quic'])
    corpus = dict(build=compiled,passed=False,**evidence,
        reference='independent explicit full parameter tuples/configured Genesis maps, signed complete trace files and exact command refusals')
    compare_corpus(corpus,checks.command,[binary,source,policy],'current-stf-trace-command-corpus',expected)
    announce('independent offline operator whole-map trace command',corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_trace_observations_corpus(compiler, report, checks, libraries):
    """Compare independently authored observed complete maps with golden authenticated execution, including refusals."""
    from current_stf_trace_observations_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, digest in FIXTURE_CONTRACTS['current_stf_trace_observations'][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Freeze mathematical observations before native execution.
    jobs, expected, evidence = expected_observations()
    requests, manifest = [], []
    for ordinal, job in enumerate(jobs):
        folder = checks.folder/'observed bundles'/('case-'+str(ordinal).zfill(4))
        observed = folder/'observations'
        observed.mkdir(parents=True, exist_ok=True)
        chain, genesis = folder/'chain.json', folder/'genesis.bin'
        chain.write_text(job['config'])
        genesis.write_bytes(job['genesis'])
        paths = [chain, genesis]
        for index, wire in enumerate(job['steps']):
            path = folder/('step-'+str(index).zfill(4)+'.bin')
            path.write_bytes(wire)
            paths.append(path) # Expected blocks/maps remain the original independent bytes.
        for index, wire in enumerate(job['observations']):
            path = observed/('step-'+str(index).zfill(4)+'.bin')
            if wire is not None:
                path.write_bytes(wire) # A missing observation is deliberately absent, never replaced with native output.
            elif path.exists():
                path.unlink() # Rerunning a failed missing-file case cannot inherit an old artifact.
        requests.append('O '+' '.join(str(path.resolve()).encode().hex() for path in [observed,*paths]))
        manifest.append(dict(chain=str(chain.resolve()),genesis=str(genesis.resolve()),
            traces=[str(path.resolve()) for path in paths[2:]],observations=str(observed.resolve()),expected=expected[ordinal]))
    policy = checks.folder/'current-stf-observations-policy.txt'
    (checks.folder/'observation-manifest.json').write_text(json.dumps(dict(policy=str(policy.resolve()),cases=manifest),indent=2)+'\n')
    source = checks.folder/'current-stf-trace-observations-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_trace_command_driver.nim',
        'current-stf-trace-observations',crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],),quic_library=libraries['quic'])
    corpus = dict(build=compiled,passed=False,**evidence,
        reference='independent mathematical observation test doubles; no external engine execution')
    compare_corpus(corpus,checks.command,[binary,source,policy],'current-stf-trace-observations-corpus',expected)
    announce('independent observed whole-map differential checking',corpus['passed'])
    return corpus


@CORPORA.case
def jam_fuzzer_wire_corpus(compiler, report, checks, libraries):
    """Compare pinned known JAM session bytes and independent complete opaque maps under explicit current structural domains."""
    from jam_fuzzer_wire_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, digest in FIXTURE_CONTRACTS['jam_fuzzer_wire'][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Freeze the exact expected observations before native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-wire-requests.txt'
    return run_corpus(checks.build,checks.command,compiler,
        ROOT/'tests/native/jam_fuzzer_wire_driver.nim','jam-fuzzer-wire',source,requests,expected,
        'jam-fuzzer-wire-corpus',metadata=dict(**evidence,
            reference='pinned known JAM historical message bytes; independent current structural framing and complete opaque maps; no STF campaign execution'),
        crypto_library=libraries['crypto'])


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_state = CORPORA.run
