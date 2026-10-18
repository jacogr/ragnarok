# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_state to execute state serialization/composition corpora and record their verdicts.
"""
from functools import partial
from pathlib import Path
import hashlib
from corpus_checks import run_corpus
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]


# Run the state corpora with explicit process, workspace and library inputs.
def run_state(compiler, report, checks, libraries):
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
    report['layout_corpus'] = corpus
    announce('independent state-key/node layout and hash corpus', corpus['passed'])
    # Compare independent unsorted-list partitions, every key divergence bit and labelled historical projections.
    from state_trie_oracle import requests as trie_requests, legacy_maps
    lines, expected = trie_requests()
    source = BUILD/'trie-requests.txt'
    # Every result compares exact root/counts or a typed reason; caller preservation is checked by the adapter.
    corpus = execute_corpus(ROOT / 'tests/native/state_trie_driver.nim', 'trie-codec',
                        source, lines, expected, 'trie-corpus',
                        metadata=dict(historical_projected_maps=len(legacy_maps())),
                        crypto_library=crypto_library)
    report['trie_corpus'] = corpus
    announce('independent bounded state trie root corpus', corpus['passed'])
    # Preserve independent entropy/time/roster bytes, malformed inputs, published derived fixtures and partial roots.
    from state_safrole_oracle import requests as safrole_requests, published as safrole_published
    lines, expected = safrole_requests()
    source = BUILD/'safrole-requests.txt'
    # Native fields/consumed counts and roots are compared only with independently authored expectations.
    corpus = execute_corpus(ROOT / 'tests/native/state_safrole_driver.nim', 'safrole-codec',
                        source, lines, expected, 'safrole-corpus',
                        metadata=dict(published_derived_state_sources=len(safrole_published())),
                        crypto_library=crypto_library)
    report['safrole_corpus'] = corpus
    announce('independent entropy/validator-roster/timeslot state corpus', corpus['passed'])
    # Preserve independent ordered core/row equations, malformed inputs, derived fixtures and partial commitments.
    from state_authorization_oracle import requests as authorization_requests, published as authorization_published
    lines, expected = authorization_requests()
    source = BUILD/'authorization-requests.txt'
    # Observe fixed hashes and owner-bound boundaries after destructive caller mutation, comparing independent bytes.
    corpus = execute_corpus(ROOT / 'tests/native/state_authorization_driver.nim', 'authorization-codec',
                        source, lines, expected, 'authorization-corpus',
                        metadata=dict(published_derived_state_sources=len(authorization_published())),
                        crypto_library=crypto_library)
    report['authorization_corpus'] = corpus
    announce('independent authorization pool/queue state corpus', corpus['passed'])
    # Preserve independent chapter-4 byte/field equations, derived fixtures and partial single-entry roots.
    from state_consensus_oracle import requests as consensus_requests, published as consensus_published
    lines, expected = consensus_requests()
    source = BUILD/'consensus-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_consensus_driver.nim', 'consensus-codec',
                        source, lines, expected, 'consensus-corpus',
                        metadata=dict(published_derived_state_sources=len(consensus_published())),
                        crypto_library=crypto_library)
    report['consensus_corpus'] = corpus
    announce('independent chapter-4 Safrole basic state corpus', corpus['passed'])
    # Preserve independent chapter-5 byte/field equations, derived fixtures and partial single-entry roots.
    from state_disputes_oracle import requests as state_disputes_requests, published as state_disputes_published
    lines, expected = state_disputes_requests()
    source = BUILD/'state_disputes-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_disputes_driver.nim', 'state_disputes-codec',
                        source, lines, expected, 'state_disputes-corpus',
                        metadata=dict(published_derived_state_sources=len(state_disputes_published())),
                        crypto_library=crypto_library)
    report['state_disputes_corpus'] = corpus
    announce('independent chapter-5 dispute judgment/offender state corpus', corpus['passed'])
    # Preserve independent chapter-3 byte/field equations, derived fixtures and partial single-entry roots.
    from state_history_oracle import requests as state_history_requests, published as state_history_published
    lines, expected = state_history_requests()
    source = BUILD/'state_history-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_history_driver.nim', 'state_history-codec',
                        source, lines, expected, 'state_history-corpus',
                        metadata=dict(published_derived_state_sources=len(state_history_published())),
                        crypto_library=crypto_library)
    report['history_corpus'] = corpus
    announce('independent chapter-3 recent history state corpus', corpus['passed'])
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
    report['availability_corpus'] = corpus
    announce('independent chapter-10 availability assignment state corpus', corpus['passed'])
    # Preserve independent chapter-12 byte/field equations, derived fixtures and partial single-entry roots.
    from state_privileges_oracle import requests as state_privileges_requests, published as state_privileges_published
    lines, expected = state_privileges_requests()
    source = BUILD/'state_privileges-requests.txt'
    # Observe every child field after caller mutation; no native round trip supplies an expected answer.
    corpus = execute_corpus(ROOT / 'tests/native/state_privileges_driver.nim', 'state_privileges-codec',
                        source, lines, expected, 'state_privileges-corpus',
                        metadata=dict(published_derived_state_sources=len(state_privileges_published())),
                        crypto_library=crypto_library)
    report['privileges_corpus'] = corpus
    announce('independent chapter-12 privileged service state corpus', corpus['passed'])
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
    report['statistics_corpus'] = corpus
    announce('independent chapter-13 activity statistics state corpus', corpus['passed'])
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
    report['workqueues_corpus'] = corpus
    announce('independent chapters 14/15 ready/accumulated queue corpus', corpus['passed'])
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
    report['outputs_corpus'] = corpus
    announce('independent chapter-16 last accumulation outputs corpus', corpus['passed'])
