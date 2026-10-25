# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_services to execute service-state corpora and record their verdicts.
"""
from functools import partial
from pathlib import Path
import hashlib
import json
from corpus_checks import run_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]



# This feature owns its shared-build execution position and additional fixture inputs.
CORPORA = CorpusGroup(order=30)

# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def accounts_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Fixed account metadata retains independent field equations, JSON records and exact nonempty raw traces.
    from state_accounts_oracle import requests as accounts_requests, published_json as accounts_json, published_traces as accounts_traces, parse as accounts_parse, wire as accounts_wire, key as accounts_key, MAX as accounts_max, SIZE as accounts_size
    lines, expected = accounts_requests()
    source = BUILD/'accounts-requests.txt'
    traces = []
    # Select exact reconstructable C(255, service) keys, never arbitrary hashed keys sharing the first byte.
    for entry in accounts_traces():
        fields = accounts_parse(entry['wire'], accounts_max)
        traces.append(dict(path=entry['path'], phase=entry['phase'], service=entry['service'],
                           key=accounts_key(entry['service']).hex(), bytes=len(entry['wire']), consumed=accounts_size,
                           sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=len(entry['wire']) == accounts_size and accounts_wire(fields) == entry['wire']))
    # Independent expected fields/bytes/reasons precede execution; native round trips supply no expected answers.
    corpus = execute_corpus(ROOT / 'tests/native/state_accounts_driver.nim', 'state_accounts-codec',
                        source, lines, expected, 'state_accounts-corpus',
                        metadata=dict(published_json_metadata=len(accounts_json()),
                                      published_trace_metadata=traces,
                                      scope='C(255,service) fixed version-zero metadata; no nested maps, account validation or transitions'),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(traces) == 20 and all(row['complete_component_match'] for row in traces)
    announce('independent C(255,service) account metadata corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def service_values_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Storage/preimage constructors use independent hash equations; raw trace capture remains explicitly unclassified.
    from state_service_values_oracle import requests as service_values_requests, published as service_values_published, published_traces as service_values_traces
    lines, expected = service_values_requests()
    source = BUILD/'service-values-requests.txt'
    sources = service_values_published()
    traces = [dict(path=entry['path'], phase=entry['phase'], service=entry['service'], key=entry['key'].hex(),
                   bytes=len(entry['value']), sha256=hashlib.sha256(entry['value']).hexdigest(),
                   namespace='opaque; not recoverable from key') for entry in service_values_traces()]
    # Native observations expose retained fields after caller mutation; expected answers precede execution.
    corpus = execute_corpus(ROOT / 'tests/native/state_service_values_driver.nim', 'state_service_values-codec',
                        source, lines, expected, 'state_service_values-corpus',
                        metadata=dict(published_json_storage=sum(row[0] == 'S' for row in sources),
                                      published_json_preimages=sum(row[0] == 'P' for row in sources),
                                      published_opaque_trace_values=traces,
                                      scope='keyed storage/preimage serialization and opaque capture; no namespace recovery, hash/content invariant or transitions'),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(traces) == 16 and corpus['published_json_storage'] == 12 and corpus['published_json_preimages'] == 16
    announce('independent service storage/preimage keys and opaque raw-value corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def requests_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Request histories preserve the full E4 domain and the maintainer-parked namespace question.
    from state_requests_oracle import requests as requests_requests, published as requests_published, published_traces as requests_traces, parse as requests_parse, wire as requests_wire
    lines, expected = requests_requests()
    source = BUILD/'requests-requests.txt'
    published = requests_published()
    traces = []
    # Identities come from exact content/preimage/request relationships in one state, never guessed hashed namespaces.
    for entry in requests_traces():
        slots, consumed = requests_parse(entry['wire'], (3, 13))
        traces.append(dict(path=entry['path'], phase=entry['phase'], service=entry['service'], length=entry['length'],
                           key=entry['key'].hex(), bytes=len(entry['wire']), count=len(slots), consumed=consumed,
                           sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=consumed == len(entry['wire']) and requests_wire(slots) == entry['wire']))
    # Independent expected fields/bytes/reasons precede execution; source and input mutation cannot change observations.
    corpus = execute_corpus(ROOT / 'tests/native/state_requests_driver.nim', 'state_requests-codec',
                        source, lines, expected, 'state_requests-corpus',
                        metadata=dict(published_json_histories=len(published),
                                      published_json_shapes={str(n): sum(len(row[3]) == n for row in published) for n in range(4)},
                                      published_trace_histories=traces,
                                      namespace_overlap=dict(status='parked_by_maintainer_until_graypaper_0.8.1_or_0.8.2', lengths=[2**32-2, 2**32-1],
                    observation='full stated domain preserved; overlapping keys reject at trie composition; no restriction inferred'),
                                      scope='request key/history framing only; no chronology, availability or lifecycle transitions'),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(traces) == 20 and all(row['complete_component_match'] for row in traces)
    announce('independent service request-history key/shape corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def composition_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Exact chapter/service composition compares every mapping byte as well as root and topology counts.
    from state_composition_oracle import requests as composition_requests
    lines, expected, components, whole = composition_requests()
    source = BUILD/'composition-requests.txt'
    # Expected complete mappings and roots precede execution; embedded ownership/association selftests also run.
    corpus = execute_corpus(ROOT / 'tests/native/state_composition_driver.nim', 'state_composition-codec',
                        source, lines, expected, 'state_composition-corpus',
                        metadata=dict(published_component_observations=components,
                                      published_composed_states=whole,
                                      published_exact_captures=sum(row['verdict'] == 'ok' for row in components),
                                      scope='exact typed chapter capture and complete mappings; opaque service values explicit; no transitions'),
                        crypto_library=crypto_library)
    corpus['passed'] = corpus['passed'] and len(components) == 224 and corpus['published_exact_captures'] == 224 and len(whole) == 14
    announce('independent exact chapter/service and whole-state composition corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case(requires=('trie_corpus',))
def state_roots_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Raw full-map roots remain separate from typed composition and preserve their existing sensitivity variants.
    from state_roots_oracle import published as roots_published, requests as roots_requests
    observations = roots_published()
    lines, expected, records = roots_requests(observations)
    source = BUILD/'state-roots-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    result = command([BUILD/'trie-codec', source], 'state-roots-corpus') if report['trie_corpus']['build']['exit_code'] == 0 else dict(exit_code=1, output='Trie driver build failed')
    output = result.pop('output')
    actual = output.splitlines()
    corpus = dict(requests=len(lines), run=result,
                  passed=result['exit_code'] == 0 and actual == expected,
                  driver_build=report['trie_corpus']['build'], published_maps=[row for _, row in observations], variants=records,
                  distinct_published_roots=len({row['state_root'] for _, row in observations}),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  actual_sha256=hashlib.sha256(output.encode()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    announce('independent raw published whole-state root corpus', corpus['passed'])
    return corpus


# Reuse the declared composition build and preserve each witness family's exact predicates.
def state_witness(family, compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Specification identity checks verify pristine pinned inputs, without advancing protocol decisions.
    # Reuse the successfully compiled composition driver; never execute a stale binary after a failed build.
    from state_widths_oracle import requests as width_requests
    from request_namespace_oracle import requests as namespace_requests
    composition_build = report['composition_corpus']['build']
    pins = json.loads((ROOT/'spec/pins.json').read_text())
    # These are the already cited witness sources; replaying their equations does not reopen normative review.
    normative = ('text/accounts.tex', 'text/definitions.tex', 'text/pvm_invocations.tex',
                 'text/accumulation.tex', 'text/merklization.tex')
    normative_hashes = {name: hashlib.sha256((ROOT/pins['graypaper']['path']/name).read_bytes()).hexdigest()
                        for name in normative}
    normative_match = all(digest == pins['graypaper']['source_sha256'][name]
                          for name, digest in normative_hashes.items())
    # Freeze independent requests and expectations before executing either regression family.
    if family == 'state_widths':
        # Preserve every published exact extent, profile and original candidate/metadata observation.
        lines, expected, records, binaries, traces = width_requests()
        evidence = dict(captures=records, binary_privilege_fields=[e for _, e in binaries],
                        raw_trace_observations=[e for _, _, e in traces],
                        gas_encoding_policy='canonical JAM compact naturals; no fallback')
    else:
        # Preserve the funded tiny-payload witnesses and full request-length domain unchanged.
        lines, expected, witnesses = namespace_requests()
        evidence = dict(witnesses=witnesses, normative_sources=normative_hashes,
                        namespace_policy='parked until Gray Paper 0.8.1/0.8.2; no new restriction',
                        scope='local account predicates and composition; no PVM or genesis reachability')
    source = BUILD/(family+'-requests.txt')
    source.write_text('\n'.join(lines)+'\n')
    result = (command([BUILD/'state_composition-codec', source], family+'-corpus')
              if composition_build['exit_code'] == 0 else dict(exit_code=1, output='Composition driver build failed'))
    output = result.pop('output')
    actual = output.splitlines()
    passed = result['exit_code'] == 0 and actual == expected
    if family == 'state_widths':
        # All 36 original published values must capture exactly, without a compatibility fallback.
        passed = passed and len(lines) == 37 and actual[1:] == ['ok']*36
    else:
        # Four successful controls/predecessors and two duplicate-key post-states retain the existing policy.
        passed = passed and normative_match and len(lines) == 7 and len(witnesses) == 2
    corpus = dict(requests=len(lines), run=result, driver_build=composition_build,
                  passed=passed, evidence=evidence,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  actual_sha256=hashlib.sha256(output.encode()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    if not passed:
        # Retain length mismatches too; adjacent logs preserve complete native observations.
        corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    announce('unchanged '+family+' regression corpus', passed)
    return corpus


# Retain this witness family as a separately required, independently checked result.
@CORPORA.case(requires=('composition_corpus',))
def state_widths_corpus(compiler, report, checks, libraries):
    return state_witness('state_widths', compiler, report, checks, libraries)


# Retain this witness family as a separately required, independently checked result.
@CORPORA.case(requires=('composition_corpus',))
def request_namespace_corpus(compiler, report, checks, libraries):
    return state_witness('request_namespace', compiler, report, checks, libraries)


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_services = CORPORA.run
