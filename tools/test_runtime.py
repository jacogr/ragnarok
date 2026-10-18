#!/usr/bin/env python3
"""Verify checked native suites, independent corpora, runtime misuse contracts."""
import argparse
from functools import partial
import os
import hashlib
import json
import platform
import re
from pathlib import Path
import subprocess
import sys
from native_checks import NativeChecks, announce
from corpus_checks import run_corpus
from failure_checks import probe_failure, run_failure_suite
from verification_inventory import (
    RUNTIME_SOURCES, AVAILABILITY_MEMBERS, BS_MEMBERS, COMPOSITION_MEMBERS, CONTRACTS,
    CORPUS_NAMES, FAILURE_COUNTS, NOMINAL, PRIVATE, WORKQUEUES_MEMBERS,
)
from native_tests import UNIT_SUITES, unit_batches, unit_jobs, unit_work_directory, unit_source, unit_command, unit_environment, unit_evidence, ARC_SUITES, unit_fixture_sources, unit_runtime_fixtures, unit_store_fixture, unit_authorization_fixture, unit_history_fixture, unit_signing_fixture, unit_entropy_fixture, unit_validator_fixture, unit_ticket_fixture, unit_sealer_fixture

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
    # Bind the group compiler and process runners once; each corpus keeps its explicit build profile.
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    bs_library = libraries['bandersnatch']
    quic_library = libraries['quic']
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
    # Replay all five early independent corpora, preserving original requests before any adapter execution.
    from test_codec import natural_requests, fixed_requests, reference_encode, reference_decode
    from bounded_checks import batch_requests as bounded_requests
    from composite_checks import batch_requests as composite_requests
    from digest_checks import batch_requests as digest_requests
    # File suffixes preserve the existing driver identities; all use this runner's checked LTO build profile.
    early = (('natural', 'driver', natural_requests()), ('fixed', 'fixed_driver', fixed_requests()),
             ('bounded', 'bounded_driver', bounded_requests(reference_encode, reference_decode)),
             ('composite', 'composite_driver', composite_requests(reference_encode, reference_decode)),
             ('digest', 'digest_driver', digest_requests(reference_encode, reference_decode)))
    for family, adapter, observations in early:
        lines, expected, *anchors = observations
        source = BUILD/(family+'-requests.txt')
        # Compare complete byte/field/error observations; adapters retain atomicity and owned-copy assertions.
        corpus = execute_corpus(ROOT / f'tests/native/{adapter}.nim', 'early-' + family,
                            source, lines, expected, 'early-' + family + '-corpus',
                            metadata=dict(published_checks=anchors[0]), expected_hash=True)
        report[family+'_corpus'] = corpus
        announce('unchanged independent '+family+' corpus', corpus['passed'])
    # The full report driver retains the unchanged codec batch and exposes credential composition separately.
    sys.path.insert(0, str(ROOT/'tests'))
    from report_oracle import requests
    lines, expected = requests()
    source = BUILD/'report-requests.txt'
    # Compare all encoded bytes and decoded semantic fields, including malformed and published fixtures.
    corpus = execute_corpus(ROOT / 'tests/native/report_driver.nim', 'report-codec',
                        source, lines, expected, 'report-corpus',
                        crypto_library=crypto_library)
    report['report_corpus'] = corpus
    announce('independent report corpus', corpus['passed'])
    # Independently signed full-report fixtures retain all original key/signature/domain/new-field mutations.
    from report_fixtures import fixtures as signed_report_fixtures, composition_cases
    provider, values = signed_report_fixtures()
    cases = composition_cases(values)
    folder = BUILD/'report-signatures'
    folder.mkdir(exist_ok=True)
    checks = []
    # This shared full-driver build must succeed before any credential command can run.
    compiled = report['report_corpus']['build']
    if compiled['exit_code'] == 0:
        # Each public wire has an independent path and an expected complete echo, exact transcript and verdict.
        for index, case in enumerate(cases):
            source = folder/(str(index)+'.bin')
            source.write_bytes(case['wire'])
            message = b'jam_guarantee'+hashlib.blake2b(case['wire'], digest_size=32).digest()
            expected = 'VERIFY '+case['wire'].hex()+' '+message.hex()+' '+str(int(case['wanted']))+'\n'
            result = command([BUILD/'report-codec', 'check', source,
                              *[raw.hex() for pair in case['credentials'] for raw in pair]], 'report-signature-'+str(index))
            output = result.pop('output')
            checks.append(dict(name=case['name'], passed=result['exit_code'] == 0 and output == expected,
                               wanted=case['wanted'], run=result,
                               wire_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                               expected_sha256=hashlib.sha256(expected.encode()).hexdigest(),
                               actual_sha256=hashlib.sha256(output.encode()).hexdigest()))
    corpus = dict(build=compiled, provider=provider, requests=len(cases), fixtures=len(values), checks=checks,
                  passed=len(cases) == len(checks) == 63 and all(row['passed'] for row in checks),
                  scope='full canonical report bytes and ordinary Ed25519 credential bindings; no assignment or point-policy decision')
    report['report_signature_corpus'] = corpus
    announce('independent full-report guarantee signature composition corpus', corpus['passed'])
    # Preserve the full independent assurance corpus and derive capacity-free inspection expectations separately.
    from assurances_oracle import requests as assurance_requests, decode as assurance_decode
    lines, expected = assurance_requests()
    codec_count = len(lines)
    for line in list(lines):
        # Every decode input also reaches inspectAssurances, independent of caller typed capacity.
        fields = line.split()
        if fields[0] == 'D':
            # The maximum valid profile has 1,023 records; inspection has no output-capacity policy.
            data = bytes.fromhex(fields[4]) if fields[4] != '-' else b''
            result = assurance_decode(int(fields[1]), int(fields[2]), 1024, data)
            parts = result.split()
            lines.append(' '.join(['I', fields[1], fields[2], fields[4]]))
            expected.append(parts[0]+' '+parts[2] if len(parts) == 3 else result)
    source = BUILD/'assurance-requests.txt'
    # Compare complete named fields/bytes and errors; native assertions additionally protect atomic output/lifetimes.
    corpus = execute_corpus(ROOT / 'tests/native/assurances_driver.nim', 'assurances-codec',
                        source, lines, expected, 'assurances-corpus',
                        metadata=dict(codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    report['assurance_corpus'] = corpus
    announce('independent assurance codec/inspection corpus', corpus['passed'])
    # Preserve the complete independently signed assurance-context corpus and frozen source/expected identities.
    from assurance_crypto_oracle import requests as assurance_context_requests
    provider, lines, expected = assurance_context_requests()
    source = BUILD/'assurance-context-requests.txt'
    # Ordinary OpenSSL signatures and hashlib transcripts precede native execution; compare every complete result.
    corpus = execute_corpus(ROOT / 'tests/native/assurance_crypto_driver.nim', 'assurance-context-codec',
                        source, lines, expected, 'assurance-context-corpus',
                        metadata=dict(provider=provider,
                                      scope='fixed transcript and stateless validator-key/parent checks; no state eligibility or point-policy change'), expected_hash=True, complete=len(lines) == 2087,
                        crypto_library=crypto_library)
    report['assurance_context_corpus'] = corpus
    announce('independent assurance transcript/context/signature corpus', corpus['passed'])
    # Keep the original guarantee corpus intact and independently check inspection and standalone APIs.
    from guarantees_checks import requests as guarantee_requests
    lines, expected, counts = guarantee_requests()
    source = BUILD/'guarantee-requests.txt'
    # Native assertions additionally cover input mutation, copied metadata and whole-output atomicity.
    corpus = execute_corpus(ROOT / 'tests/native/guarantees_driver.nim', 'guarantees-codec',
                        source, lines, expected, 'guarantees-corpus',
                        metadata=dict(request_groups=counts))
    report['guarantee_corpus'] = corpus
    announce('independent guarantee extrinsic/inspection/standalone corpus', corpus['passed'])
    # Keep every original ticket request and add unsigned policy extremes before direct inspections.
    from tickets_oracle import requests as ticket_requests, decode as ticket_decode, encode as ticket_encode
    from tickets_oracle import record as ticket_record, wire as ticket_wire
    from test_codec import reference_encode as ticket_natural
    lines, expected = ticket_requests()
    original_count = len(lines)
    for limit, data in ((2**64-1, ticket_natural(2**64-1)), (2**64-1, b'\0'),
                        (0, b'\0'), (0, ticket_wire([ticket_record(255)]))):
        # Huge permitted counts still need a complete raw extent; zero limits allow only empty records.
        lines.append(f'D {limit} 1 {data.hex()}')
        expected.append(ticket_decode(data, limit, 1))
    for limit in (0, 2**64-1):
        # Unsigned policy extremes must neither wrap nor narrow through the fixture parser.
        records = [ticket_record(255)]
        lines.append(f'E {limit} 786 {records[0].hex()}')
        expected.append(ticket_encode(records, limit, 786))
    codec_count = len(lines)
    for line in list(lines):
        # Inspect every original/new decoder input with no caller record capacity limitation.
        fields = line.split()
        if fields[0] == 'D':
            data = bytes.fromhex(fields[3]) if fields[3] != '-' else b''
            result = ticket_decode(data, int(fields[1]), len(data)//785+1)
            parts = result.split()
            lines.append(' '.join(['I', fields[1], '0', fields[3]]))
            expected.append(parts[0]+' '+parts[2] if len(parts) == 3 else result)
    source = BUILD/'ticket-requests.txt'
    # Exact attempts/proofs and consumed metadata are observed independently after source mutation.
    corpus = execute_corpus(ROOT / 'tests/native/tickets_driver.nim', 'tickets-codec',
                        source, lines, expected, 'tickets-corpus',
                        metadata=dict(original_requests=original_count,
                                      codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    report['ticket_corpus'] = corpus
    announce('independent ticket codec/inspection corpus', corpus['passed'])
    # Preserve original dispute semantics, including published ordering rejections, plus unsigned policy extremes.
    from disputes_oracle import requests as dispute_requests, decode as dispute_decode, encode as dispute_encode
    from disputes_oracle import fields as dispute_fields, example as dispute_example
    lines, expected = dispute_requests()
    original_count = len(lines)
    for validators, data in ((6, b'\0\0\0'), (6, b'\0\0\0\xff'),
                             (6, ticket_natural(2**64-1)), (2**64-1, b'')):
        # Huge announced counts are rejected before narrowing; invalid unsigned profiles precede all input access.
        lines.append(f'D {validators} {2**64-1} {data.hex() or "-"}')
        expected.append(dispute_decode(data, validators, 2**64-1))
    for validators in (6, 2**64-1):
        # Empty source descriptors still require a valid profile and a complete three-byte frame.
        value = dispute_example(0, 0, 0, 0)
        lines.append(f'E {validators} {2**64-1} 3 '+dispute_fields(value))
        expected.append(dispute_encode(value, validators, 2**64-1, 3))
    codec_count = len(lines)
    for line in list(lines):
        # Every decoder input also reaches allocation-free inspection with its own count/extent expectation.
        fields = line.split()
        if fields[0] == 'D':
            data = bytes.fromhex(fields[3]) if fields[3] != '-' else b''
            result = dispute_decode(data, int(fields[1]), int(fields[2]))
            parts = result.split()
            lines.append(' '.join(['I', *fields[1:]]))
            if len(parts) == 1:
                # A typed oracle failure has no cardinalities or cursor to inspect.
                expected.append(result)
            else:
                # Select section cardinalities from independent logical fields, never native layout/offsets.
                verdicts, cursor = int(parts[1]), 2
                for _ in range(verdicts):
                    # Each verdict has hash/epoch/count plus three logical fields per judgment.
                    votes = int(parts[cursor+2])
                    cursor += 3+3*votes
                culprits = int(parts[cursor])
                cursor += 1+3*culprits
                faults = int(parts[cursor])
                cursor += 1+4*faults
                assert cursor == len(parts)
                expected.append(f'{verdicts} {culprits} {faults} {parts[0]}')
    source = BUILD/'dispute-requests.txt'
    # Native checks also protect owner copies, exact prefix retention and whole-output failure atomicity.
    corpus = execute_corpus(ROOT / 'tests/native/disputes_driver.nim', 'disputes-codec',
                        source, lines, expected, 'disputes-corpus',
                        metadata=dict(original_requests=original_count,
                                      codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    report['dispute_corpus'] = corpus
    announce('independent dispute codec/inspection corpus', corpus['passed'])
    # The unchanged package oracle covers context, import, commitment, standalone item and complete package APIs.
    from package_oracle import requests as package_requests
    lines, expected = package_requests()
    groups = {kind: sum(line.split(' ', 2)[1] == kind for line in lines) for kind in ('C', 'R', 'X', 'I', 'P')}
    source = BUILD/'package-requests.txt'
    # Every typed field/payload is observed independently after original input mutation; failures retain sentinels.
    corpus = execute_corpus(ROOT / 'tests/native/package_driver.nim', 'package-codec',
                        source, lines, expected, 'package-corpus',
                        metadata=dict(request_groups=groups))
    report['package_corpus'] = corpus
    announce('independent context/import/commitment/item/package corpus', corpus['passed'])
    # Retain the complete five-family header corpus and add direct full-header inspection expectations.
    from header_oracle import requests as header_requests, decode as header_decode
    lines, expected = header_requests()
    original_count = len(lines)
    groups = {kind: sum(line.split(' ', 2)[1] == kind for line in lines) for kind in ('T', 'E', 'W', 'U', 'H')}
    for line in list(lines):
        # Every original full-header decode input also reaches inspection without capturing a snapshot.
        fields = line.split()
        if fields[0] == 'D' and fields[1] == 'H':
            data = bytes.fromhex(fields[6]) if fields[6] != '-' else b''
            result = header_decode('H', data, tuple(map(int, fields[2:6])))
            parts = result.split()
            lines.append('Q '+line[2:])
            if len(parts) == 1:
                # Failed inspection exposes none of the successfully copied header metadata.
                expected.append(result)
            else:
                # Parse the oracle's independent logical marker fields, not native coordinates or serialized offsets.
                cursor = 5
                if parts[cursor] == '0':
                    # Absent epoch metadata contains no entropies, count or key fields.
                    cursor += 1
                else:
                    # Present epoch logical fields carry two entropies and a count followed by key pairs.
                    count = int(parts[cursor+3])
                    cursor += 4+2*count
                if parts[cursor] == '0':
                    # An absent winner marker contributes only its logical presence flag.
                    cursor += 1
                else:
                    # Logical winner fields include the independently known sequence length plus fixed ticket pairs.
                    count = int(parts[cursor+1])
                    cursor += 2+2*count
                author, proof, offenders = parts[cursor:cursor+3]
                assert len(parts) == cursor+4+int(offenders)
                expected.append(' '.join([parts[0], str(int(parts[0])-96), *parts[1:5], author, proof, offenders, parts[-1]]))
    source = BUILD/'header-requests.txt'
    # Independently observe every field after source erasure, marker retention and exact signing-prefix checks.
    corpus = execute_corpus(ROOT / 'tests/native/header_driver.nim', 'header-codec',
                        source, lines, expected, 'header-corpus',
                        metadata=dict(original_requests=original_count,
                                      request_groups=groups,
                                      inspection_requests=len(lines)-original_count))
    report['header_corpus'] = corpus
    announce('independent ticket/epoch/winner/unsigned/full-header corpus', corpus['passed'])
    # Preserve every independent whole-block/extrinsic expectation, including actual published policy failures.
    from block_oracle import requests as block_requests
    lines, expected = block_requests()
    source = BUILD/'block-requests.txt'
    groups = {operation+'-'+kind: sum(line.startswith(operation+' '+kind+' ') for line in lines)
              for operation in ('D', 'E') for kind in ('E', 'B')}
    # Compare all six exact child wires/counts after source erasure and on-demand materialization.
    corpus = execute_corpus(ROOT / 'tests/native/block_driver.nim', 'block-codec',
                        source, lines, expected, 'block-corpus',
                        metadata=dict(request_groups=groups))
    report['block_corpus'] = corpus
    announce('independent complete extrinsic/block corpus', corpus['passed'])
    # Preserve all exhaustive Boolean/padding cases and pinned profile-field checks from the independent oracle.
    from bits_oracle import requests as bits_requests
    lines, expected = bits_requests()
    source = BUILD/'bits-requests.txt'
    groups = {operation: sum(line.startswith(operation+' ') for line in lines)
              for operation in ('BD', 'BE', 'D', 'E')}
    # Observe every logical bit/count/extent after input erasure and compare both owner framing forms.
    corpus = execute_corpus(ROOT / 'tests/native/bits_driver.nim', 'bits-codec',
                        source, lines, expected, 'bits-corpus',
                        metadata=dict(request_groups=groups))
    report['bits_corpus'] = corpus
    announce('independent Boolean/fixed/variable bitstring corpus', corpus['passed'])
    # Preserve the unchanged collection oracle: numeric/byte ordering, pairing and zero-width singleton domains.
    from collections_oracle import requests as collection_requests
    lines, expected = collection_requests()
    source = BUILD/'collection-requests.txt'
    groups = {kind: sum(line.split()[1] == kind for line in lines) for kind in ('F', 'S', 'M')}
    assert sum(groups.values()) == len(lines), groups
    # Compare copied logical fields, canonical wire, consumed progress and typed reasons after input erasure.
    corpus = execute_corpus(ROOT / 'tests/native/collections_driver.nim', 'collection-codec',
                        source, lines, expected, 'collection-corpus',
                        metadata=dict(request_groups=groups))
    report['collection_corpus'] = corpus
    announce('independent canonical fixed/variable set/dictionary corpus', corpus['passed'])
    # Independent C.2 references retain exact availability/transfer/operand framing and tagged-union agreement.
    from c2_oracle import requests as c2_requests
    lines, expected = c2_requests()
    source = BUILD/'c2-requests.txt'
    groups = {}
    # Classify actual request names rather than guessing adapter tags; every request must be included.
    for line in lines:
        parts = line.split()
        key = parts[0]+'-'+parts[1]
        groups[key] = groups.get(key, 0)+1
    assert sum(groups.values()) == len(lines), groups
    # Observe every fixed field, payload/trace copy and exact owned wire after destructive caller mutation.
    corpus = execute_corpus(ROOT / 'tests/native/c2_driver.nim', 'c2-codec',
                        source, lines, expected, 'c2-corpus',
                        metadata=dict(request_groups=groups))
    report['c2_corpus'] = corpus
    announce('independent availability/transfer/operand/accumulation corpus', corpus['passed'])
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
    report['accounts_corpus'] = corpus
    announce('independent C(255,service) account metadata corpus', corpus['passed'])
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
    report['service_values_corpus'] = corpus
    announce('independent service storage/preimage keys and opaque raw-value corpus', corpus['passed'])
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
    report['requests_corpus'] = corpus
    announce('independent service request-history key/shape corpus', corpus['passed'])
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
    report['composition_corpus'] = corpus
    announce('independent exact chapter/service and whole-state composition corpus', corpus['passed'])
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
    report['state_roots_corpus'] = corpus
    announce('independent raw published whole-state root corpus', corpus['passed'])
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
    for family in ('state_widths', 'request_namespace'):
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
        report[family+'_corpus'] = corpus
        announce('unchanged '+family+' regression corpus', passed)
    # Replay the unchanged release-reference proof oracle through the production library, without observer interposition.
    from test_bandersnatch import suite as bs_suite, generated_proofs as bs_generated, bridge_checks as bs_bridge, official_sources as bs_official
    bs_official(False)
    compiled, binary = build(compiler, ROOT/'tests/native/bandersnatch_driver.nim', 'bandersnatch-context',
                             native_libraries=(bs_library,))
    corpus = dict(build=compiled, passed=False, observations=[], reference='spec/bandersnatch-pins.json')
    # Keep each exact fixture request/response and contract diagnostic as reproducible local/CI evidence.
    def bs_query(binary, operation, *values):
        arguments = [(value.hex() or '-') if isinstance(value, bytes) else str(value) for value in values]
        result = command([binary, operation, *arguments], 'bs-context-'+str(len(corpus['observations'])))
        corpus['observations'].append(result)
        assert result['exit_code'] == 0, result
        return result['output'].strip()
    # Failed result access must reject before any default output can be observed.
    def bs_failure(binary):
        result = command([binary, 'F'], 'bs-context-failed-result')
        corpus['failure_probe'] = result
        return result['exit_code'], result['output']
    if compiled['exit_code'] == 0:
        # Preserve original oracle assertions; failures remain visible in the final partial-migration verdict.
        try:
            corpus['vectors'] = bs_suite(binary, query=bs_query, failure_probe=bs_failure)
            corpus['generated'] = bs_generated(binary, query=bs_query)
            corpus['native_boundary'] = bs_bridge()
            corpus['passed'] = True
        except (AssertionError, subprocess.SubprocessError) as error:
            corpus['failure'] = repr(error)
    corpus['requests'] = len(corpus['observations'])
    report['bandersnatch_corpus'] = corpus
    announce('contextual Bandersnatch vectors/native ABI', corpus['passed'])
    # Compare identity/framing outcomes with an independent arbitrary-precision oracle and public DER fixtures.
    from quic_protocol_oracle import requests as protocol_requests
    lines, expected, groups = protocol_requests(quic_fixtures)
    source = BUILD/'quic-protocol-requests.txt'
    # Keep exact status/identity/length/extent observations; incomplete results expose no payload metadata.
    corpus = execute_corpus(ROOT / 'tests/native/quic_protocol_driver.nim', 'quic-protocol-driver',
                        source, lines, expected, 'quic-protocol-corpus',
                        metadata=dict(groups=groups,
                                      scope='pinned SAN/DER identity and structural CE framing; no TLS handshake or fixture eligibility claim'), expected_hash=True,
                        quic_library=quic_library)
    report['quic_protocol_corpus'] = corpus
    announce('independent SAN/DER/frame boundary corpus', corpus['passed'])
    # Compose independently parsed full C.2 wires and hashlib keys through the enabled production ABI.
    from integration_oracle import requests as integration_requests
    lines, expected = integration_requests(integration_wires)
    source = BUILD/'integration-requests.txt'
    # Compare complete serialized bytes and failure ordering, not only a self-generated round trip.
    corpus = execute_corpus(ROOT / 'tests/native/integration_driver.nim', 'integration-driver',
                        source, lines, expected, 'integration-corpus',
                        metadata=dict(scope='CE fixture codec/crypto composition; no authenticated transport or normative digest/preimage relationship'), expected_hash=True,
                        crypto_library=crypto_library,
                        defines=('integration',))
    report['integration_corpus'] = corpus
    announce('independent CE digest capture/hash-binding corpus', corpus['passed'])
    # Preserve every independent primitive vector, ownership check and joined native-thread workload.
    compiled, binary = build(compiler, ROOT/'tests/native/crypto_driver.nim', 'crypto-driver', crypto_library)
    corpus = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # The production-linked corpus has no failure injection or observation wrappers.
        corpus['run'] = command([sys.executable, ROOT/'tests/test_nimony_crypto.py', '--binary', binary], 'crypto-corpus')
        corpus['passed'] = corpus['run']['exit_code'] == 0
        if corpus['passed']:
            # Retain structured independent equation/thread counts alongside the exact reproduction command.
            corpus['counts'] = json.loads(corpus['run']['output'])
    report['crypto_corpus'] = corpus
    announce('crypto corpus', corpus['passed'])


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
    # Literal provenance inputs are merge-friendly data; discovery rules remain explicit.
    sources = [ROOT/path for path in RUNTIME_SOURCES]
    sources += list((ROOT/'src/codec').glob('*.nim')) + list((ROOT/'src/state').glob('*.nim'))
    sources += [unit_source(name) for name in UNIT_SUITES]
    sources += [unit_source(name).with_suffix('.output') for name in UNIT_SUITES]
    sources += unit_fixture_sources()
    sources += list((ROOT/'tests').glob('report_*.py')) + list((ROOT/'tests').glob('guarantees_*.py'))
    sources += list((ROOT/'tests/native').glob('nimony_*.nim'))
    sources += [ROOT/f'tests/native/compile_fail/{name}.nim' for name in (*PRIVATE, *NOMINAL, *CONTRACTS)]
    sources += [Path(__file__).resolve()]
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
    from nimony_crypto import prepare as prepare_crypto
    crypto_library, crypto_observer, report['crypto_native'] = prepare_crypto(BUILD)
    from bandersnatch_native import prepare as prepare_bandersnatch, OWNER_DEFINES
    bs_library, bs_observer, report['bandersnatch_native'] = prepare_bandersnatch(BUILD)
    bs_libraries = (bs_observer, bs_library)
    from nimony_quic import prepare as prepare_quic
    quic_library, quic_fixtures, report['quic_native'] = prepare_quic()
    # Reuse the original independently checked CE integration fixtures; no peer/compiler build runs here.
    import test_integration as integration_fixture
    integration_fixture.BUILD.mkdir(parents=True, exist_ok=True)
    integration_wires, integration_keys = integration_fixture.corpus()
    integration_reload = BUILD/'integration-reload'
    integration_reload.mkdir(exist_ok=True)
    # Different candidate bytes make a late refused reload detect partial publication rather than a no-op reload.
    for index in range(8):
        wire = bytearray((integration_wires/f'{index}.bin').read_bytes())
        wire[0] ^= 128
        (integration_reload/f'{index}.bin').write_bytes(wire)
    report['integration_fixtures'] = dict(keys=integration_keys,
        original={str(index): hashlib.sha256((integration_wires/f'{index}.bin').read_bytes()).hexdigest() for index in range(8)},
        reload={str(index): hashlib.sha256((integration_reload/f'{index}.bin').read_bytes()).hexdigest() for index in range(8)})
    from state_availability_oracle import record as availability_record
    availability_fixture = BUILD/'availability-report.bin'
    availability_fixture.write_bytes(availability_record(0)['report'])
    # Composition ownership probes consume independent literal chapters, not native round-trip fixtures.
    from state_composition_oracle import chapters as composition_chapters
    composition_fixture = BUILD/'composition-chapters.txt'
    composition_fixture.write_text('\n'.join(raw.hex() for raw in composition_chapters())+'\n')
    libraries = dict(crypto=crypto_library, observer=crypto_observer, bandersnatch=bs_library,
                     bandersnatch_observer=bs_observer, quic=quic_library)
    if args.group == 'unit':
        # Expensive state replay/rotation fixtures belong only to the ordinary native suites.
        # Every ordinary suite now has one native runner path; omitted/extra identities are a migration failure.
        assert len(UNIT_SUITES) == len(set(UNIT_SUITES))
        fixtures = unit_runtime_fixtures(quic_fixtures, integration_wires, integration_reload)
        store_fixtures, report['store_replay_fixture'] = unit_store_fixture(BUILD)
        fixtures.update(store_fixtures)
        authorization_fixtures, report['authorization_stf_fixture'] = unit_authorization_fixture(BUILD)
        fixtures.update(authorization_fixtures)
        history_fixtures, report['history_stf_fixture'] = unit_history_fixture(BUILD)
        fixtures.update(history_fixtures)
        signing_fixtures, report['signing_domain_fixture'] = unit_signing_fixture(BUILD)
        fixtures.update(signing_fixtures)
        entropy_fixtures, report['entropy_stf_fixture'] = unit_entropy_fixture(BUILD)
        fixtures.update(entropy_fixtures)
        validator_fixtures, report['validator_stf_fixture'] = unit_validator_fixture(BUILD)
        ticket_fixtures, report['ticket_stf_fixture'] = unit_ticket_fixture(BUILD)
        fixtures.update(validator_fixtures)
        fixtures.update(ticket_fixtures)
        sealer_fixtures, report['sealer_stf_fixture'] = unit_sealer_fixture(BUILD)
        fixtures.update(sealer_fixtures)
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
