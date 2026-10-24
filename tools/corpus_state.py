# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_state to execute state serialization/composition corpora and record their verdicts.
"""
from functools import partial
from pathlib import Path
import hashlib
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


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_state = CORPORA.run
