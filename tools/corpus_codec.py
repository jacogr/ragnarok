# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_codecs to execute codec corpora and record independently checked native
observations.
"""
from functools import partial
from pathlib import Path
import hashlib
import sys
from corpus_checks import run_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]



# This feature owns its shared-build execution position and additional fixture inputs.
CORPORA = CorpusGroup(order=10)


# Replay the early independent request families with their original adapters and expected bytes.
def early_corpus(family, adapter, observations, compiler, checks):
    build, command = checks.build, checks.command
    lines, expected, *anchors = observations
    source = checks.folder/(family+'-requests.txt')
    corpus = run_corpus(build, command, compiler, ROOT/f'tests/native/{adapter}.nim',
                      'early-'+family, source, lines, expected, 'early-'+family+'-corpus',
                      metadata=dict(published_checks=anchors[0]), expected_hash=True)
    announce('unchanged independent '+family+' corpus', corpus['passed'])
    return corpus

# Preserve the independent natural corpus and its original native adapter.
@CORPORA.case
def natural_corpus(compiler, report, checks, libraries):
    from test_codec import natural_requests
    return early_corpus('natural', 'codec_driver', natural_requests(), compiler, checks)


# Preserve the independent fixed corpus and its original native adapter.
@CORPORA.case
def fixed_corpus(compiler, report, checks, libraries):
    from test_codec import fixed_requests
    return early_corpus('fixed', 'codec_fixed_driver', fixed_requests(), compiler, checks)


# Preserve the independent bounded corpus and its original native adapter.
@CORPORA.case
def bounded_corpus(compiler, report, checks, libraries):
    from bounded_checks import batch_requests
    from test_codec import reference_encode, reference_decode
    return early_corpus('bounded', 'codec_bounded_driver', batch_requests(reference_encode, reference_decode), compiler, checks)


# Preserve the independent composite corpus and its original native adapter.
@CORPORA.case
def composite_corpus(compiler, report, checks, libraries):
    from composite_checks import batch_requests
    from test_codec import reference_encode, reference_decode
    return early_corpus('composite', 'codec_composite_driver', batch_requests(reference_encode, reference_decode), compiler, checks)


# Preserve the independent digest corpus and its original native adapter.
@CORPORA.case
def digest_corpus(compiler, report, checks, libraries):
    from digest_checks import batch_requests
    from test_codec import reference_encode, reference_decode
    return early_corpus('digest', 'codec_digest_driver', batch_requests(reference_encode, reference_decode), compiler, checks)


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def report_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # The full report driver retains the unchanged codec batch and exposes credential composition separately.
    sys.path.insert(0, str(ROOT/'tests'))
    from report_oracle import requests
    lines, expected = requests()
    source = BUILD/'report-requests.txt'
    # Compare all encoded bytes and decoded semantic fields, including malformed and published fixtures.
    corpus = execute_corpus(ROOT / 'tests/native/state_report_driver.nim', 'report-codec',
                        source, lines, expected, 'report-corpus',
                        crypto_library=crypto_library)
    announce('independent report corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case(requires=('report_corpus',))
def report_signature_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
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
    announce('independent full-report guarantee signature composition corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def assurance_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
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
    corpus = execute_corpus(ROOT / 'tests/native/codec_assurances_driver.nim', 'assurances-codec',
                        source, lines, expected, 'assurances-corpus',
                        metadata=dict(codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    announce('independent assurance codec/inspection corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def assurance_context_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve the complete independently signed assurance-context corpus and frozen source/expected identities.
    from assurance_crypto_oracle import requests as assurance_context_requests
    provider, lines, expected = assurance_context_requests()
    source = BUILD/'assurance-context-requests.txt'
    # Ordinary OpenSSL signatures and hashlib transcripts precede native execution; compare every complete result.
    corpus = execute_corpus(ROOT / 'tests/native/codec_assurance_crypto_driver.nim', 'assurance-context-codec',
                        source, lines, expected, 'assurance-context-corpus',
                        metadata=dict(provider=provider,
                                      scope='fixed transcript and stateless validator-key/parent checks; no state eligibility or point-policy change'), expected_hash=True, complete=len(lines) == 2087,
                        crypto_library=crypto_library)
    announce('independent assurance transcript/context/signature corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def guarantee_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Keep the original guarantee corpus intact and independently check inspection and standalone APIs.
    from guarantees_checks import requests as guarantee_requests
    lines, expected, counts = guarantee_requests()
    source = BUILD/'guarantee-requests.txt'
    # Native assertions additionally cover input mutation, copied metadata and whole-output atomicity.
    corpus = execute_corpus(ROOT / 'tests/native/codec_guarantees_driver.nim', 'guarantees-codec',
                        source, lines, expected, 'guarantees-corpus',
                        metadata=dict(request_groups=counts))
    announce('independent guarantee extrinsic/inspection/standalone corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def ticket_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
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
    corpus = execute_corpus(ROOT / 'tests/native/codec_tickets_driver.nim', 'tickets-codec',
                        source, lines, expected, 'tickets-corpus',
                        metadata=dict(original_requests=original_count,
                                      codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    announce('independent ticket codec/inspection corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def dispute_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    from test_codec import reference_encode as ticket_natural
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
    corpus = execute_corpus(ROOT / 'tests/native/codec_disputes_driver.nim', 'disputes-codec',
                        source, lines, expected, 'disputes-corpus',
                        metadata=dict(original_requests=original_count,
                                      codec_requests=codec_count,
                                      inspection_requests=len(lines)-codec_count))
    announce('independent dispute codec/inspection corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def package_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # The unchanged package oracle covers context, import, commitment, standalone item and complete package APIs.
    from package_oracle import requests as package_requests
    lines, expected = package_requests()
    groups = {kind: sum(line.split(' ', 2)[1] == kind for line in lines) for kind in ('C', 'R', 'X', 'I', 'P')}
    source = BUILD/'package-requests.txt'
    # Every typed field/payload is observed independently after original input mutation; failures retain sentinels.
    corpus = execute_corpus(ROOT / 'tests/native/codec_package_driver.nim', 'package-codec',
                        source, lines, expected, 'package-corpus',
                        metadata=dict(request_groups=groups))
    announce('independent context/import/commitment/item/package corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def header_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
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
    corpus = execute_corpus(ROOT / 'tests/native/codec_header_driver.nim', 'header-codec',
                        source, lines, expected, 'header-corpus',
                        metadata=dict(original_requests=original_count,
                                      request_groups=groups,
                                      inspection_requests=len(lines)-original_count))
    announce('independent ticket/epoch/winner/unsigned/full-header corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def block_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve every independent whole-block/extrinsic expectation, including actual published policy failures.
    from block_oracle import requests as block_requests
    lines, expected = block_requests()
    source = BUILD/'block-requests.txt'
    groups = {operation+'-'+kind: sum(line.startswith(operation+' '+kind+' ') for line in lines)
              for operation in ('D', 'E') for kind in ('E', 'B')}
    # Compare all six exact child wires/counts after source erasure and on-demand materialization.
    corpus = execute_corpus(ROOT / 'tests/native/codec_block_driver.nim', 'block-codec',
                        source, lines, expected, 'block-corpus',
                        metadata=dict(request_groups=groups))
    announce('independent complete extrinsic/block corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def bits_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve all exhaustive Boolean/padding cases and pinned profile-field checks from the independent oracle.
    from bits_oracle import requests as bits_requests
    lines, expected = bits_requests()
    source = BUILD/'bits-requests.txt'
    groups = {operation: sum(line.startswith(operation+' ') for line in lines)
              for operation in ('BD', 'BE', 'D', 'E')}
    # Observe every logical bit/count/extent after input erasure and compare both owner framing forms.
    corpus = execute_corpus(ROOT / 'tests/native/codec_bits_driver.nim', 'bits-codec',
                        source, lines, expected, 'bits-corpus',
                        metadata=dict(request_groups=groups))
    announce('independent Boolean/fixed/variable bitstring corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def collection_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    # Preserve the unchanged collection oracle: numeric/byte ordering, pairing and zero-width singleton domains.
    from collections_oracle import requests as collection_requests
    lines, expected = collection_requests()
    source = BUILD/'collection-requests.txt'
    groups = {kind: sum(line.split()[1] == kind for line in lines) for kind in ('F', 'S', 'M')}
    assert sum(groups.values()) == len(lines), groups
    # Compare copied logical fields, canonical wire, consumed progress and typed reasons after input erasure.
    corpus = execute_corpus(ROOT / 'tests/native/codec_collections_driver.nim', 'collection-codec',
                        source, lines, expected, 'collection-corpus',
                        metadata=dict(request_groups=groups))
    announce('independent canonical fixed/variable set/dictionary corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def c2_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
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
    corpus = execute_corpus(ROOT / 'tests/native/codec_c2_driver.nim', 'c2-codec',
                        source, lines, expected, 'c2-corpus',
                        metadata=dict(request_groups=groups))
    announce('independent availability/transfer/operand/accumulation corpus', corpus['passed'])
    return corpus


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_codecs = CORPORA.run
