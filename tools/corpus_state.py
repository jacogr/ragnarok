# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Register Unit state corpora; expected results remain in independent test oracles.

Dedicated interface corpora register separately in jam_fuzz_corpora for Fuzz / JAM.
"""
from functools import partial
from pathlib import Path
import hashlib
import json
from native_fixture_contracts import validate_fixture_contracts
from corpus_checks import run_corpus, compare_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]


# This feature owns its shared-build execution position and additional fixture inputs.
CORPORA = CorpusGroup(order=20)


def guest_scenario(compiler, checks, libraries, oracle, fixtures, *, name, reference, message):
    """Execute shared guest-driver plumbing; each case owns its pinned inputs and independent equations."""
    from native_fixture_contracts import FIXTURE_CONTRACTS
    validate_fixture_contracts(fixtures)
    # Expected complete maps must exist before any native compilation or observation.
    requests, expected, evidence = oracle()
    corpus = run_corpus(checks.build, checks.command, compiler,
        ROOT/'tests/native/current_stf_report_guests_driver.nim', name,
        checks.folder/(name+'-requests.txt'), requests, expected, name+'-corpus',
        metadata=dict(**evidence, reference=reference), request_evidence=False,
        arguments=(FIXTURE_CONTRACTS['state_report'][1],),
        crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    announce(message, corpus['passed'])
    return corpus


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
    validate_fixture_contracts(('current_stf', 'state_report'))
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
    validate_fixture_contracts(('current_stf_effects', 'state_report'))
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
    validate_fixture_contracts(('current_stf_epoch', 'state_report'))
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
    validate_fixture_contracts(('current_stf_epoch', 'current_stf_population', 'state_report'))
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
    validate_fixture_contracts(('current_stf_epoch', 'current_stf_eviction', 'state_report'))
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
    validate_fixture_contracts(('current_stf_epoch', 'current_stf_population', 'current_stf_verdicts', 'state_report'))
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
    validate_fixture_contracts(('current_stf', 'current_stf_reporting', 'state_report'))
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
    validate_fixture_contracts(('current_stf', 'current_stf_epoch', 'current_stf_epoch_reporting', 'state_report'))
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
def current_stf_population_reporting_corpus(compiler, report, checks, libraries):
    """Compare population-changing guarantee/assurance publication with independent complete maps and contextual refusals."""
    from current_stf_population_reporting_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    validate_fixture_contracts(('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_population_reporting', 'state_report'))
    # OpenSSL signatures, mathematical Thin, report projections and every map exist before native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'current-stf-population-reporting-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/current_stf_population_reporting_driver.nim',
        'current-stf-population-reporting', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    corpus = dict(build=compiled, passed=False, **evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  reference='OpenSSL Ed25519, mathematical Thin and independent report/availability whole-map STF')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'current-stf-population-reporting-corpus', expected)
    announce('independent population/reporting whole STF maps', corpus['passed'])
    return corpus


@CORPORA.case
def current_stf_report_guests_corpus(compiler, report, checks, libraries):
    """Compare report-driven real guest execution against independently calculated complete maps."""
    from current_stf_report_guests_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    validate_fixture_contracts(('current_stf_effects', 'current_stf_report_guests', 'state_report'))
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
    # Shared genuine driver consumes only bodies; independent E/Q/accseq maps and traces already exist.
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_effects', 'current_stf_report_guests', 'current_stf_dependency_waves', 'state_report'),
        name='current-stf-dependency-waves',
        reference='independent GP E/Q/accseq, literal guest semantics, mathematical Thin and OpenSSL Ed25519',
        message='independent deferred dependency-wave whole STF maps')


@CORPORA.case
def current_stf_budget_retention_corpus(compiler, report, checks, libraries):
    """Compare budget-exhausted ready retention and later drain against independently calculated full maps."""
    from current_stf_budget_retention_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_budget_retention', 'current_stf_dependency_waves', 'state_report'),
        name='current-stf-budget-retention',
        reference='independent GP E/Q/accseq and literal guest gas; whole-map retention/drain',
        message='independent budget-retention whole STF maps')


@CORPORA.case
def current_stf_gas_exits_corpus(compiler, report, checks, libraries):
    """Compare gas-limited guest exits and pooled operands against independently calculated full maps."""
    from current_stf_gas_exits_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_gas_exits', 'current_stf_report_guests', 'state_report'),
        name='current-stf-gas-exits',
        reference='independent prepaid-block/host gas, pooled budgets and literal guest implications',
        message='independent gas-exits whole STF maps')


@CORPORA.case
def current_stf_late_code_corpus(compiler, report, checks, libraries):
    """Compare late code-preimage phase ordering against independently calculated full maps."""
    from current_stf_late_code_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_late_code', 'current_stf_report_guests', 'state_report'),
        name='current-stf-late-code',
        reference='independent missing-code skips, late fulfillment and literal guest implications',
        message='independent late-code whole STF maps')


@CORPORA.case
def current_stf_epoch_drain_corpus(compiler, report, checks, libraries):
    """Compare epoch-spanning deferred guest execution against independently calculated full maps."""
    from current_stf_epoch_drain_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_epoch_drain', 'current_stf_dependency_waves', 'state_report'),
        name='current-stf-epoch-drain',
        reference='independent Safrole/header equations, deferred budgets and literal guest effects',
        message='independent epoch-drain whole STF maps')


@CORPORA.case
def current_stf_ready_expiry_corpus(compiler, report, checks, libraries):
    """Compare skipped-time ready expiry after actual execution against independently calculated full maps."""
    from current_stf_ready_expiry_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_ready_expiry', 'current_stf_epoch_drain', 'state_report'),
        name='current-stf-ready-expiry',
        reference='independent GP Q/accseq then elapsed-slot expiry and mathematical epoch headers',
        message='independent ready-expiry whole STF maps')


@CORPORA.case
def current_stf_transfers_corpus(compiler, report, checks, libraries):
    """Compare deferred transfer delivery and terminal selection against independently calculated full maps."""
    from current_stf_transfers_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_transfers', 'current_stf_report_guests', 'state_report'),
        name='current-stf-transfers',
        reference='independent literal transfer debit/credit, prepaid gas, terminal selection and full maps',
        message='independent transfers whole STF maps')


@CORPORA.case
def current_stf_supervised_transfers_corpus(compiler, report, checks, libraries):
    """Compare supervised transfer scheduling and exact incarnation fallbacks against independently calculated full maps."""
    from current_stf_supervised_transfers_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_transfers', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-transfers',
        reference='independent GP stable partition, declared/actual accseq budgets and full transfer effects',
        message='independent supervised-transfer whole STF maps')


@CORPORA.case
def current_stf_forwarded_transfers_corpus(compiler, report, checks, libraries):
    """Compare repeated forwarding and transfer-only gas exits against independently calculated full maps."""
    from current_stf_forwarded_transfers_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_forwarded_transfers', 'current_stf_transfers', 'state_report'),
        name='current-stf-forwarded-transfers',
        reference='independent accseq forwarding, prepaid gas, exceptional selection and transfer-only effects',
        message='independent forwarded-transfer whole STF maps')


@CORPORA.case
def current_stf_transfer_pools_corpus(compiler, report, checks, libraries):
    """Compare direct and deferred balance-pool combinations against independently calculated full maps."""
    from current_stf_transfer_pools_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_transfer_pools', 'current_stf_transfers', 'state_report'),
        name='current-stf-transfer-pools',
        reference='independent transfer pool selection, direct-credit authority and full participant maps',
        message='independent transfer-pool whole STF maps')


@CORPORA.case
def current_stf_transfer_admission_corpus(compiler, report, checks, libraries):
    """Compare transfer admission and exact host/recipient gas boundaries against independently calculated full maps."""
    from current_stf_transfer_admission_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_transfer_admission', 'current_stf_transfers', 'state_report'),
        name='current-stf-transfer-admission',
        reference='independent endpoint/funding/memo predicates, host gas and prepaid recipient blocks',
        message='independent transfer-admission whole STF maps')


@CORPORA.case
def current_stf_transfer_memos_corpus(compiler, report, checks, libraries):
    """Compare memo-driven fetched storage and yielded outputs against independently calculated full maps."""
    from current_stf_transfer_memos_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_transfer_memos', 'current_stf_transfers', 'state_report'),
        name='current-stf-transfer-memos',
        reference='independent C.2 input framing, fetch slices/gas, write footprint and C16/history outputs',
        message='independent transfer-memo whole STF maps')


@CORPORA.case
def current_stf_service_upgrades_corpus(compiler, report, checks, libraries):
    """Compare self-upgrade selection and later current-code invocation against independently calculated full maps."""
    from current_stf_service_upgrades_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_service_upgrades', 'current_stf_transfers', 'state_report'),
        name='current-stf-service-upgrades',
        reference='independent self-upgrade metadata, prior-code lookup, missing code and host gas',
        message='independent service-upgrade whole STF maps')


@CORPORA.case
def current_stf_supervisor_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare supervisor reassignment and current protected-funding authority against independently calculated full maps."""
    from current_stf_supervisor_lifecycle_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervisor_lifecycle', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervisor-lifecycle',
        reference='independent self-supervisor mutation, protected funding, checkpoint selection and whole maps',
        message='independent supervisor-lifecycle whole STF maps')


@CORPORA.case
def current_stf_service_creation_corpus(compiler, report, checks, libraries):
    """Compare public creation cursors and child namespace publication against independently calculated full maps."""
    from current_stf_service_creation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_service_creation', 'current_stf_transfers', 'state_report'),
        name='current-stf-service-creation',
        reference='independent compact entropy seed, public cursor, child metadata and code-request maps',
        message='independent service-creation whole STF maps')


@CORPORA.case
def current_stf_request_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare selected solicit/forget namespaces and exact reserved footprints against independent full maps."""
    from current_stf_request_lifecycle_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_request_lifecycle', 'current_stf_transfers', 'state_report'),
        name='current-stf-request-lifecycle',
        reference='independent GP solicit/forget, checkpoint selection and full request maps',
        message='independent request lifecycle whole STF maps')


@CORPORA.case
def current_stf_preimage_provision_corpus(compiler, report, checks, libraries):
    """Compare selected queued provision relevance and canonical fulfillment against independent complete maps."""
    from current_stf_preimage_provision_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_preimage_provision', 'current_stf_transfers', 'state_report'),
        name='current-stf-preimage-provision',
        reference='independent GP queued provisions, selected request relevance and complete maps',
        message='independent provision lifecycle whole STF maps')


@CORPORA.case
def current_stf_service_ejection_corpus(compiler, report, checks, libraries):
    """Compare selected empty-junior ejection and both-pool refund against independent complete maps."""
    from current_stf_service_ejection_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_service_ejection', 'current_stf_transfers', 'state_report'),
        name='current-stf-service-ejection',
        reference='independent GP empty service ejection and exactly-once liquid refund',
        message='independent service ejection whole STF maps')


@CORPORA.case
def current_stf_manager_handoff_corpus(compiler, report, checks, libraries):
    """Compare sole-manager role handoff and sequential authority against independent full maps."""
    from current_stf_manager_handoff_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_manager_handoff', 'current_stf_transfers', 'state_report'),
        name='current-stf-manager-handoff',
        reference='independent GP sole-manager handoff, authority recheck and checkpoint selection',
        message='independent manager handoff whole STF maps')


@CORPORA.case
def current_stf_checkpoint_replay_corpus(compiler, report, checks, libraries):
    """Compare five exact independent lifecycle transcripts after full checkpoint reconstruction at every block."""
    from current_stf_checkpoint_replay_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_checkpoint_replay', 'current_stf_transfers', 'state_report'),
        name='current-stf-checkpoint-replay',
        reference='independent unchanged lifecycle equations across new full-store and chain owners',
        message='independent full checkpoint replay STF maps')


@CORPORA.case
def current_stf_epoch_lifecycle_corpus(compiler, report, checks, libraries):
    """Compare queued provision/request lifecycle with independently derived epoch rotation and signed boundary markers."""
    from current_stf_epoch_lifecycle_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_epoch_lifecycle', 'current_stf_transfers', 'state_report'),
        name='current-stf-epoch-lifecycle',
        reference='independent GP epoch rotation composed with request relevance and selected provision histories',
        message='independent epoch lifecycle whole STF maps')


@CORPORA.case
def current_stf_supervised_storage_corpus(compiler, report, checks, libraries):
    """Compare supervised foreign storage and inactive-target publication against independent full maps."""
    from current_stf_supervised_storage_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_storage', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-storage',
        reference='independent GP supervised storage selection, incarnation authority and full maps',
        message='independent supervised storage whole STF maps')


@CORPORA.case
def current_stf_supervised_requests_corpus(compiler, report, checks, libraries):
    """Compare supervised foreign request selection, canonical histories and complete reservation footprints."""
    from current_stf_supervised_requests_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_requests', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-requests',
        reference='independent GP foreign solicit/forget selection, checkpoint histories and exact whole maps',
        message='independent supervised requests whole STF maps')


@CORPORA.case
def current_stf_supervised_upgrades_corpus(compiler, report, checks, libraries):
    """Compare supervised upgrades, minimum gas and subsequent junior current-code lookup against full maps."""
    from current_stf_supervised_upgrades_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_upgrades', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-upgrades',
        reference='independent GP foreign upgrade selection, honest code availability and junior execution',
        message='independent supervised upgrades whole STF maps')


@CORPORA.case
def current_stf_supervised_conflicts_corpus(compiler, report, checks, libraries):
    """Compare parallel supervisor/junior conflicts, selected account precedence and retained provisions against whole maps."""
    from current_stf_supervised_conflicts_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_conflicts', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-conflicts',
        reference='independent GP N annulment, M account selection, retained gas/provisions and discarded yield',
        message='independent supervised conflicts whole STF maps')


@CORPORA.case
def current_stf_supervised_handoff_corpus(compiler, report, checks, libraries):
    """Compare original-role foreign supervisor handoff and immediate write-authority loss against complete maps."""
    from current_stf_supervised_handoff_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_supervised_handoff', 'current_stf_transfers', 'state_report'),
        name='current-stf-supervised-handoff',
        reference='independent GP prior-role M selection and current-context supervisor authority',
        message='independent supervised handoff whole STF maps')


@CORPORA.case
def current_stf_authorization_assign_corpus(compiler, report, checks, libraries):
    """Compare ordered authorization queue replacement, handoff and same-block posterior-queue pools against full maps."""
    from current_stf_authorization_assign_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_authorization_assign', 'current_stf_transfers', 'state_report'),
        name='current-stf-authorization-assign',
        reference='independent GP assigner handoff, posterior queue selection and complete C1/C2/C12 maps',
        message='independent authorization assignment whole STF maps')


@CORPORA.case
def current_stf_role_precedence_corpus(compiler, report, checks, libraries):
    """Compare simultaneous manager/assigner GP R precedence and original-role queue publication against full maps."""
    from current_stf_role_precedence_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_role_precedence', 'current_stf_transfers', 'state_report'),
        name='current-stf-role-precedence',
        reference='independent GP R original-role precedence, selected terminal globals and posterior queue pools',
        message='independent privileged role precedence whole STF maps')


@CORPORA.case
def current_stf_validator_designation_corpus(compiler, report, checks, libraries):
    """Compare selected designation through two epoch rotations with exact signed headers and complete maps."""
    from current_stf_validator_designation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_validator_designation', 'current_stf_transfers', 'state_report'),
        name='current-stf-validator-designation',
        reference='independent GP designation selection, attributed ring inputs and staging/pending/active epoch equations',
        message='independent validator designation whole STF maps')


@CORPORA.case
def current_stf_reserved_creation_corpus(compiler, report, checks, libraries):
    """Compare reserved-ID creation with independently calculated deposits, four pool combinations and repeated admission."""
    from current_stf_reserved_creation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_reserved_creation', 'current_stf_transfers', 'state_report'),
        name='current-stf-reserved-creation',
        reference='independent GP reserved creation, integer deposit thresholds, exact debit/credit pools and selected account maps',
        message='independent funded reserved creation whole STF maps')


@CORPORA.case
def current_stf_child_readiness_corpus(compiler, report, checks, libraries):
    """Compare public child creation, same-invocation code provision and later execution against independent maps."""
    from current_stf_child_readiness_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_child_readiness', 'current_stf_transfers', 'state_report'),
        name='current-stf-child-readiness',
        reference='independent GP public IDs, selected creation/provision pairs, exact request histories and actual gas',
        message='independent child readiness whole STF maps')


@CORPORA.case
def current_stf_preimage_aging_corpus(compiler, report, checks, libraries):
    """Compare strict request expiry, live preimage retention and restored-history compaction against independent maps."""
    from current_stf_preimage_aging_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_preimage_aging', 'current_stf_transfers', 'state_report'),
        name='current-stf-preimage-aging',
        reference='independent widened strict-expiry equations, history transitions, exact reservation release and selected maps',
        message='independent preimage aging whole STF maps')


@CORPORA.case
def current_stf_child_retirement_corpus(compiler, report, checks, libraries):
    """Compare funded child birth, pending reservation cleanup, same-slot eject refusal and later pool refunds."""
    from current_stf_child_retirement_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_child_retirement', 'current_stf_transfers', 'state_report'),
        name='current-stf-child-retirement',
        reference='independent GP birth/forget/eject chronology, four funding pools, atomic refund and full maps',
        message='independent child retirement whole STF maps')


@CORPORA.case
def current_stf_child_recreation_corpus(compiler, report, checks, libraries):
    """Compare reserved-ID reuse after retirement with fresh incarnation metadata, Q membership and exact funding pools."""
    from current_stf_child_recreation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_child_recreation', 'current_stf_transfers', 'state_report'),
        name='current-stf-child-recreation',
        reference='independent GP old-incarnation deletion, fresh creation/minima/reservations, funding and checkpoint selection',
        message='independent child recreation whole STF maps')


@CORPORA.case
def current_stf_profile_replay_corpus(compiler, report, checks, libraries):
    """Compare full-store reconstruction across explicit code-size, deposit, aging and supervisor lifecycle profiles."""
    from current_stf_profile_replay_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_profile_replay', 'current_stf_transfers', 'state_report'),
        name='current-stf-profile-replay',
        reference='independent equation-family maps, exact checkpoint reconstruction and unchanged signed continuation under each declared profile',
        message='independent current-profile checkpoint continuation maps')


@CORPORA.case
def current_stf_epoch_composition_corpus(compiler, report, checks, libraries):
    """Compare supervisor, privileged-queue and funded lifecycle effects across signed epoch boundaries and fresh-store continuation."""
    from current_stf_epoch_composition_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_epoch_composition', 'current_stf_transfers', 'state_report'),
        name='current-stf-epoch-composition',
        reference='independent epoch/header/assurance equations composed with supervisor selection, posterior queues and funded lifecycle effects',
        message='independent epoch composition whole STF maps')


@CORPORA.case
def current_stf_bless_allowances_corpus(compiler, report, checks, libraries):
    """Compare nonempty bless publication, canonical input sets and later always-accumulate scheduling against independent maps."""
    from current_stf_bless_allowances_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_bless_allowances', 'current_stf_transfers', 'state_report'),
        name='current-stf-bless-allowances',
        reference='independent GP initial allowance scheduling, raw bless charging, canonical dictionaries and exact whole-map effects',
        message='independent nonempty bless allowance whole STF maps')


@CORPORA.case
def current_stf_allowance_revocation_corpus(compiler, report, checks, libraries):
    """Compare scheduled manager takeover, actual allowance revocation and fresh report-driven reauthorization."""
    from current_stf_allowance_revocation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_allowance_revocation', 'current_stf_transfers', 'state_report'),
        name='current-stf-allowance-revocation',
        reference='independent original-manager selection, initial free dictionary, empty-operand gas and selected revocation maps',
        message='independent scheduled allowance revocation whole STF maps')


@CORPORA.case
def current_stf_allowance_eligibility_corpus(compiler, report, checks, libraries):
    """Compare zero/exact free-gas membership, basic-block charging and genuine unavailable-code eligibility."""
    from current_stf_allowance_eligibility_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_allowance_eligibility', 'current_stf_transfers', 'state_report'),
        name='current-stf-allowance-eligibility',
        reference='independent free-dictionary keys, exact basic-block gas threshold, unavailable-code rules and complete maps',
        message='independent allowance eligibility whole STF maps')


@CORPORA.case
def current_stf_incarnation_authority_corpus(compiler, report, checks, libraries):
    """Compare actual supervisor retirement/recreation, common-prior authority refusal and later explicit incarnation rebinding."""
    from current_stf_incarnation_authority_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_incarnation_authority', 'current_stf_transfers', 'state_report'),
        name='current-stf-incarnation-authority',
        reference='independent old/new supervisor incarnations, original-context N/M selection, real provision and exact foreign writes',
        message='independent recreated supervisor authority whole STF maps')


@CORPORA.case
def current_stf_foreign_creation_corpus(compiler, report, checks, libraries):
    """Compare foreign-funded creation, selected source pools and parallel junior annulment against independent complete maps."""
    from current_stf_foreign_creation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_foreign_creation', 'current_stf_transfers', 'state_report'),
        name='current-stf-foreign-creation',
        reference='independent GP foreign funding, four pools, N/M source selection and exactly-once admission/debit',
        message='independent foreign-funded creation whole STF maps')


@CORPORA.case
def current_stf_foreign_transfers_corpus(compiler, report, checks, libraries):
    """Compare foreign direct transfers, endpoint pool conservation and parallel junior annulment."""
    from current_stf_foreign_transfers_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_foreign_transfers', 'current_stf_transfers', 'state_report'),
        name='current-stf-foreign-transfers',
        reference='independent foreign-source/direct-credit equations, original-context N/M selection and exact gas/counts',
        message='independent foreign direct transfer whole STF maps')


@CORPORA.case
def current_stf_queued_incarnation_corpus(compiler, report, checks, libraries):
    """Compare exact queued old-incarnation report retention and current-code execution after real service recreation."""
    from current_stf_queued_incarnation_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_queued_incarnation', 'current_stf_transfers', 'state_report'),
        name='current-stf-queued-incarnation',
        reference='independent pending-report identity, current Psi_A code lookup, common-prior rebinding and selected successor maps',
        message='independent queued incarnation whole STF maps')


@CORPORA.case
def current_stf_interchange_corpus(compiler, report, checks, libraries):
    """Compare complete current-profile logical export, fresh-store reload and exact-source startup across seven STF families."""
    from current_stf_interchange_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_interchange', 'current_stf_transfers', 'state_report'),
        name='current-stf-interchange',
        reference='independent authored raw-identity enumeration, exact namespace coverage and frozen complete STF maps',
        message='independent current-profile logical interchange whole STF maps')


@CORPORA.case
def state_trace_wire_corpus(compiler, report, checks, libraries):
    """Compare published RawState wire prefixes, complete current STF maps and typed malformed-input refusals."""
    from state_trace_wire_oracle import expected_observations
    # Freeze independently calculated source and full-map evidence before execution.
    validate_fixture_contracts(('state_trace_wire',))
    requests, expected, evidence = expected_observations()
    return run_corpus(checks.build, checks.command, compiler,
        ROOT/'tests/native/state_trace_wire_driver.nim', 'state-trace-wire',
        checks.folder/'state-trace-wire-requests.txt', requests, expected, 'state-trace-wire-corpus',
        metadata=evidence, crypto_library=libraries['crypto'])


@CORPORA.case
def state_trace_step_corpus(compiler, report, checks, libraries):
    """Compare complete published TraceStep wires, exact typed failures and independent full pre/post maps."""
    from state_trace_step_oracle import expected_observations
    # Independent fixture identities precede all native execution.
    validate_fixture_contracts(('state_trace_step', 'state_trace_step_answers'))
    requests, expected, evidence = expected_observations()
    return run_corpus(checks.build, checks.command, compiler,
        ROOT/'tests/native/state_trace_step_driver.nim', 'state-trace-step',
        checks.folder/'state-trace-step-requests.txt', requests, expected, 'state-trace-step-corpus',
        metadata=evidence, crypto_library=libraries['crypto'])


@CORPORA.case
def current_stf_trace_import_corpus(compiler, report, checks, libraries):
    """Compare actual authenticated trace import, complete advertised pre/post maps and typed refusal isolation."""
    from current_stf_trace_import_oracle import expected_observations
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_trace_import', 'current_stf_transfers', 'state_report'),
        name='current-stf-trace-import',
        reference='independent published full trace framing, exact signed blocks/whole STF maps and wrong-map/seal refusals',
        message='independent authenticated trace import whole STF maps')


@CORPORA.case
def current_stf_trace_files_corpus(compiler, report, checks, libraries):
    """Compare exact bounded file-backed current STF imports and independent complete-map/refusal observations."""
    from current_stf_trace_files_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    # Frozen independent evidence precedes materialization and native execution.
    validate_fixture_contracts(('current_stf_trace_files', 'current_stf_transfers', 'state_report'))
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
    return guest_scenario(compiler, checks, libraries, expected_observations,
        ('current_stf_trace_genesis', 'current_stf_transfers', 'state_report'),
        name='current-stf-trace-genesis',
        reference='independent Genesis header/root anchors, explicit full-profile bootstrap and exact signed STF maps',
        message='independent anchored Genesis whole STF maps')


@CORPORA.case
def current_stf_trace_command_corpus(compiler, report, checks, libraries):
    """Compare the public offline command against independent full-profile Genesis/trace files and typed refusals."""
    from current_stf_trace_command_oracle import expected_observations
    # Freeze exact independent input/configuration/output evidence before native policy-input generation.
    validate_fixture_contracts(('current_stf_trace_command',))
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
    # Freeze mathematical observations before native execution.
    validate_fixture_contracts(('current_stf_trace_observations',))
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


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_state = CORPORA.run
