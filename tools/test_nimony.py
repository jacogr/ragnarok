#!/usr/bin/env python3
"""Verify the Nimony-only partial port, guarded codec results and immutable owned snapshots."""
import argparse
import hashlib
import json
import platform
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/nimony-trial/verification'
SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'assurances', 'guarantees', 'tickets', 'disputes', 'work_package', 'header', 'block', 'block_private')
PRIVATE = dict(bounded_blob_private='byteLength', bounded_write_private='byteWritten',
               bounded_sequence_private='elementCount', bounded_retag='status',
               bounded_error_write='error', bounded_forge='status')
PRIMITIVE_PRIVATE = dict(primitive_natural_private='decodedValue', primitive_natural_retag='success',
    primitive_natural_forge='success', primitive_fixed_decode_private='decodedValue',
    primitive_fixed_decode_retag='success', primitive_fixed_decode_forge='success',
    primitive_fixed_encode_private='encodedValue', primitive_fixed_encode_retag='success',
    primitive_fixed_encode_forge='success', primitive_ok_write='ok',
    primitive_error_private='failureReason', primitive_reason_write='error')
COMPOSITE_PRIVATE = dict(
    composite_write_private='byteWritten',
    composite_write_retag='status',
    composite_write_forge='status',
    composite_optional_private='decodedValue',
    composite_optional_retag='status',
    composite_optional_forge='status',
    composite_work_private='decodedValue',
    composite_work_retag='status',
    composite_work_forge='status',
    composite_preimages_private='elementCount',
    composite_preimages_retag='status',
    composite_preimages_forge='status',
    composite_digest_private='decodedValue',
    composite_digest_retag='status',
    composite_digest_forge='status',
    variant_optional_private='payloadSpan',
    variant_optional_retag='isPresent',
    variant_optional_public_tag='present',
    variant_optional_forge='isPresent',
    variant_work_private='payloadSpan',
    variant_work_retag='outputKind',
    variant_work_public_tag='kind',
    variant_work_forge='outputKind',
    composite_error_write='error',
)
OWNED_PRIVATE = dict(
    owned_result_private='completed',
    owned_result_retag='status',
    owned_result_forge='status',
    owned_result_error_write='error',
    owned_frame_private='data',
    owned_optional_private='payloadLength',
    owned_optional_retag='isPresent',
    owned_optional_public_tag='present',
    owned_optional_forge='isPresent',
    owned_work_private='payloadLength',
    owned_work_retag='outputKind',
    owned_work_public_tag='kind',
    owned_work_forge='outputKind',
)
REPORT_PRIVATE = dict(report_value_private='decodedValue', report_retag='status', report_forge='status',
    report_header_private='decodedValue', report_header_retag='status', report_header_forge='status',
    report_error_write='error', report_consumed_private='byteConsumed',
    report_owner_private='data', report_owner_forge='data')
NOMINAL = dict(swapped_report_root='got: ReportHash but wanted: ReportHash',
               swapped_report_slot='got: LookupSlot but wanted: AnchorSlot',
               swapped_lookup_state='got: ReportHash but wanted: ReportHash',
               raw_erasure_shards='got: uint16 but wanted: ErasureShards')
REPORT_MEMBERS = ('report-value', 'report-consumed', 'header-value', 'owner-value',
                  'info-value', 'prerequisite-value', 'lookup-value')
ASSURANCE_PRIVATE = dict(assurances_write_private='byteWritten', assurances_write_retag='status',
    assurances_write_forge='status', assurances_write_error='error', assurances_write_written='written',
    assurances_decode_private='recordCount', assurances_decode_consumed='byteConsumed',
    assurances_decode_retag='status', assurances_decode_forge='status', assurances_decode_error='error',
    assurances_decode_count='count', assurances_decode_progress='consumed')
NOMINAL.update(assurances_anchor='got: AssuranceSignature but wanted: AssuranceAnchor',
               assurances_config='got: ValidatorCount but wanted: CoreCount',
               assurances_index='got: CoreCount but wanted: ValidatorIndex')
ASSURANCE_MEMBERS = ('written', 'count', 'consumed', 'inspect-count', 'inspect-consumed')
GUARANTEE_PRIVATE = dict(guarantee_result_private='completed', guarantee_result_read_private='completed',
    guarantee_result_retag='status', guarantee_result_forge='status', guarantee_result_error='error',
    guarantee_result_value='value', private_guarantees_owner='data', guarantee_owner_forge='data')
NOMINAL.update(swapped_guarantee_slot='got: LookupSlot but wanted: GuaranteeSlot',
               swapped_guarantor_index='got: ValidatorIndex but wanted: GuarantorIndex',
               swapped_guarantee_signature='got: AssuranceSignature but wanted: GuaranteeSignature')
GUARANTEE_MEMBERS = ('owner', 'count', 'consumed', 'single-value', 'single-consumed', 'selected',
                    'encoded', 'owned', 'measured', 'bytes', 'inspect-count', 'inspect-consumed',
                    'record-core', 'record-consumed')
TICKET_PRIVATE = dict(tickets_write_private='byteWritten', tickets_write_retag='status',
    tickets_write_forge='status', tickets_write_error='error', tickets_write_written='written',
    tickets_read_private='recordCount', tickets_read_consumed='byteConsumed', tickets_read_retag='status',
    tickets_read_forge='status', tickets_read_error='error', tickets_read_count='count',
    tickets_read_progress='consumed')
NOMINAL.update(raw_ticket_attempt='got: uint8 but wanted: TicketAttempt',
               swapped_ticket_proof='got: TicketAttempt but wanted: TicketProof')
TICKET_MEMBERS = ('written', 'count', 'consumed', 'inspect-count', 'inspect-consumed')
DISPUTE_PRIVATE = dict(dispute_result_private='completed', dispute_result_info_private='completed',
    dispute_result_retag='status', dispute_result_forge='status', dispute_result_error='error',
    dispute_result_value='value', private_disputes_owner='data', dispute_owner_forge='data')
NOMINAL.update(swapped_dispute_epoch='got: GuaranteeSlot but wanted: DisputeEpoch',
               swapped_judge_index='got: ValidatorIndex but wanted: JudgeIndex',
               swapped_offender_key='got: DisputeHash but wanted: OffenderKey',
               swapped_dispute_signature='got: GuaranteeSignature but wanted: DisputeSignature')
DISPUTE_MEMBERS = ('owner', 'decoded-info', 'info', 'verdict', 'verdict-judgments', 'judgment',
                   'culprit', 'fault', 'written', 'owned-written', 'inspect-verdicts', 'inspect-consumed')
PACKAGE_PRIVATE = dict(package_result_private='completed', package_result_item_private='completed',
    package_result_retag='status', package_result_forge='status', package_result_error='error',
    package_result_value='value', private_package_owner='data', private_item_owner='data',
    package_owner_forge='data', package_item_forge='data', package_item_index='index',
    package_item_rebind='index', import_root_private='rootIdentity', import_package_private='packageIdentity',
    import_retag='referenceKind', import_public_kind='kind', import_forge='referenceKind',
    import_root_write='root', import_package_write='package')
NOMINAL.update(swapped_import_index='got: ValidatorIndex but wanted: ImportIndex',
               swapped_authorizer_host='got: ServiceIndex but wanted: AuthorizerHost',
               swapped_import_identity='[1] expected: ReportHash but got: ReportHash',
               swapped_extrinsic_length='got: BundleLength but wanted: ExtrinsicLength')
PACKAGE_MEMBERS = ('context-value', 'context-consumed', 'import-value', 'import-consumed',
    'commitment-value', 'commitment-consumed', 'package-owner', 'package-consumed', 'item-owner',
    'item-consumed', 'package-info', 'item-info', 'child', 'selected-import', 'selected-commitment',
    'context-written', 'import-written', 'commitment-written', 'item-written', 'package-written',
    'payload', 'blob', 'owned-item', 'owned-package')
HEADER_PRIVATE = {
    'header_result_private': 'completed',
    'header_result_unsigned_private': 'completed',
    'header_result_retag': 'status',
    'header_result_forge': 'status',
    'header_result_error': 'error',
    'header_result_value': 'value',
    'header_owner_forge': 'data',
    'unsigned_header_owner_forge': 'data',
    'epoch_marker_owner_forge': 'data',
    'winners_marker_owner_forge': 'data',
    'source_epoch_entropyValue': 'entropyValue',
    'source_epoch_ticketEntropyValue': 'ticketEntropyValue',
    'source_epoch_validatorValues': 'validatorValues',
    'source_epoch_retag': 'isPresent',
    'source_epoch_forge': 'isPresent',
    'source_epoch_present': 'present',
    'source_epoch_entropy_write': 'entropy',
    'source_epoch_ticketsEntropy_write': 'ticketsEntropy',
    'source_winners_ticketValues': 'ticketValues',
    'source_winners_retag': 'isPresent',
    'source_winners_forge': 'isPresent',
    'source_winners_present': 'present',
    'meta_epoch_entropyValue': 'entropyValue',
    'meta_epoch_ticketEntropyValue': 'ticketEntropyValue',
    'meta_epoch_validatorCount': 'validatorCount',
    'meta_epoch_retag': 'isPresent',
    'meta_epoch_forge': 'isPresent',
    'meta_epoch_present': 'present',
    'meta_epoch_entropy_write': 'entropy',
    'meta_epoch_ticketsEntropy_write': 'ticketsEntropy',
    'meta_epoch_count_write': 'validators',
    'meta_winners_ticketCount': 'ticketCount',
    'meta_winners_retag': 'isPresent',
    'meta_winners_forge': 'isPresent',
    'meta_winners_present': 'present',
    'meta_winners_count_write': 'tickets',
    'private_header_owner': 'data',
    'private_unsigned_header_owner': 'data',
    'private_epoch_marker_owner': 'data',
    'private_winners_marker_owner': 'data',
}
HEADER_MEMBERS = (
    'header-owner', 'header-consumed', 'unsigned-owner', 'unsigned-consumed', 'epoch-owner',
    'epoch-consumed', 'winners-owner', 'winners-consumed', 'fixed-ticket', 'fixed-consumed',
    'info', 'inspection', 'unsigned-info', 'unsigned-view', 'epoch-view', 'winners-view',
    'epoch-info', 'winners-info', 'validator', 'ticket', 'offender', 'header-written',
    'unsigned-written', 'epoch-written', 'winners-written', 'fixed-written', 'owned-header',
    'owned-unsigned', 'owned-epoch', 'owned-winners',
)
HEADER_OPTIONAL = (
    'source-entropy', 'source-tickets-entropy', 'source-validators', 'source-tickets',
    'meta-entropy', 'meta-tickets-entropy', 'meta-validators', 'meta-tickets', 'edit-validators',
    'edit-tickets',
)
NOMINAL.update(swapped_header_root='got: ExtrinsicRoot but wanted: PriorStateRoot',
               swapped_header_author='got: ValidatorIndex but wanted: AuthorIndex',
               swapped_header_proof='got: HeaderSeal but wanted: HeaderEntropyProof',
               swapped_winning_ticket_id='got: EpochEntropy but wanted: WinningTicketId',
               unsigned_as_full_header='expected: OwnedHeader but got: OwnedUnsignedHeader')
BLOCK_PRIVATE = {
    'private_component_snapshot': 'data',
    'private_extrinsic_snapshot': 'data',
    'private_block_snapshot': 'data',
    'frame_result_private': 'completed',
    'frame_result_retag': 'status',
    'frame_result_forge': 'status',
    'frame_result_cause_private': 'nestedCause',
    'frame_result_error_write': 'error',
    'frame_result_value_write': 'value',
    'frame_result_cause_write': 'cause',
    'component_cause_retag': 'schema',
    'component_cause_forge': 'schema',
    'component_cause_kind_write': 'kind',
    'component_header_reason_private': 'headerReason',
    'component_header_reason_write': 'headerError',
    'component_ticket_reason_private': 'ticketReason',
    'component_ticket_reason_write': 'ticketError',
    'component_preimage_reason_private': 'preimageReason',
    'component_preimage_reason_write': 'preimageError',
    'component_guarantee_reason_private': 'guaranteeReason',
    'component_guarantee_reason_write': 'guaranteeError',
    'component_assurance_reason_private': 'assuranceReason',
    'component_assurance_reason_write': 'assuranceError',
    'component_dispute_reason_private': 'disputeReason',
    'component_dispute_reason_write': 'disputeError',
}
BLOCK_MEMBERS = (
    'decode-header', 'decode-tickets', 'decode-preimages', 'decode-guarantees', 'decode-assurances',
    'decode-disputes', 'component-info', 'component-write', 'extrinsic-read', 'extrinsic-own',
    'extrinsic-write', 'extrinsic-info', 'extrinsic-owned-write', 'block-read', 'block-write',
    'block-info', 'block-owned-write', 'block-header', 'block-extrinsic', 'ticket-records',
    'assurance-records', 'child-tickets', 'child-preimages', 'child-guarantees', 'child-assurances',
    'child-disputes',
)
BLOCK_WRONG = (
    ('header-as-ticket', 'Tickets'),
    ('header-as-preimage', 'Preimages'),
    ('header-as-guarantee', 'Guarantees'),
    ('header-as-assurance', 'Assurances'),
    ('header-as-dispute', 'Disputes'),
    ('tickets-as-header', 'Header'),
    ('tickets-as-preimage', 'Preimages'),
    ('tickets-as-guarantee', 'Guarantees'),
    ('tickets-as-assurance', 'Assurances'),
    ('tickets-as-dispute', 'Disputes'),
    ('preimages-as-header', 'Header'),
    ('preimages-as-ticket', 'Tickets'),
    ('preimages-as-guarantee', 'Guarantees'),
    ('preimages-as-assurance', 'Assurances'),
    ('preimages-as-dispute', 'Disputes'),
    ('guarantees-as-header', 'Header'),
    ('guarantees-as-ticket', 'Tickets'),
    ('guarantees-as-preimage', 'Preimages'),
    ('guarantees-as-assurance', 'Assurances'),
    ('guarantees-as-dispute', 'Disputes'),
    ('assurances-as-header', 'Header'),
    ('assurances-as-ticket', 'Tickets'),
    ('assurances-as-preimage', 'Preimages'),
    ('assurances-as-guarantee', 'Guarantees'),
    ('assurances-as-dispute', 'Disputes'),
    ('disputes-as-header', 'Header'),
    ('disputes-as-ticket', 'Tickets'),
    ('disputes-as-preimage', 'Preimages'),
    ('disputes-as-guarantee', 'Guarantees'),
    ('disputes-as-assurance', 'Assurances'),
)
PRIVATE.update(BLOCK_PRIVATE)
NOMINAL.update(swapped_extrinsic_component='got: Component but wanted: Component',
               swapped_block_header='got: Component but wanted: Component',
               block_as_extrinsic='expected: OwnedExtrinsic but got: OwnedBlock')
PRIVATE.update(HEADER_PRIVATE)
PRIVATE.update(PACKAGE_PRIVATE)
PRIVATE.update(DISPUTE_PRIVATE)
PRIVATE.update(TICKET_PRIVATE)
PRIVATE.update(GUARANTEE_PRIVATE)
PRIVATE.update(ASSURANCE_PRIVATE)
PRIVATE.update(REPORT_PRIVATE)
PRIVATE.update(OWNED_PRIVATE)
PRIVATE['wrong_owner_pool'] = 'copyOwnedBlob'
PRIVATE.update(COMPOSITE_PRIVATE)
PRIVATE.update(PRIMITIVE_PRIVATE)
PRIMITIVE_MEMBERS = ('natural-value', 'natural-consumed', 'fixed-value', 'fixed-consumed', 'fixed-encoded')
PRIMITIVE_ERRORS = ('natural-error', 'fixed-decode-error', 'fixed-encode-error')
OWNED_MEMBERS = ('frame', 'info', 'optional', 'work', 'digest', 'service', 'integer', 'boolean')
COMPOSITE_MEMBERS = ('optional-value', 'optional-consumed', 'work-value', 'work-consumed',
                     'preimages-count', 'preimages-consumed', 'written', 'digest-value', 'digest-consumed')
MEMBERS = ('offset', 'length', 'blob-consumed', 'written', 'count', 'sequence-consumed')


# Keep exact arguments, status and output for every build/run, including intentional rejections.
def command(arguments, name):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT,
                            capture_output=True, text=True, timeout=180)
    output = result.stdout+result.stderr
    log = BUILD/(name+'.log')
    log.write_text(output)
    return dict(command=[str(arg) for arg in arguments], exit_code=result.returncode,
                log=str(log.relative_to(ROOT)), output=output)


# Use Nimony ARC/Clang release/LTO with bounds/contracts enabled; never use danger or noAssertions.
def build(compiler, source, name):
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
             '--boundchecks:on', '--passC:-flto', '--passL:-flto']
    if platform.system() == 'Linux':
        # Preserve the established Linux LTO linker choice when the trial reaches that host.
        flags += ['--passL:-fuse-ld=lld']
    binary = BUILD/name
    result = command([compiler, 'c', *flags, f'--nimcache:{BUILD/(name+"-cache")}',
                      f'--out:{binary}', source], name+'-build')
    return result, binary


# Print each independent verdict so a deliberate remaining gate cannot conceal a new regression.
def announce(name, passed):
    print(('PASS ' if passed else 'FAIL ')+name, flush=True)


# Verify the coherent scalar/composite/digest/report slice; other families remain outside this partial trial.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(environment=dict(system=platform.system(), machine=platform.machine(),
                  python=platform.python_version()), suites=[], runtime=[], bounded=[], primitive=[], composite=[], owned=[], reports=[], assurances=[], guarantees=[], tickets=[], disputes=[], packages=[], headers=[], blocks=[], privacy=[], nominal=[])
    metadata = compiler.parent.parent/'NIGHTLY.txt'
    report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
    report['nimony_version'] = command([compiler, '--version'], 'nimony-version')
    report['clang_version'] = command(['clang', '--version'], 'clang-version')
    report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
    sources = (list((ROOT/'src/codec').glob('*.nim'))
               + [ROOT/f'tests/native/test_{name}.nim' for name in SUITES]
               + [ROOT/'tests/native/ownership_checks.nim', ROOT/'tests/native/report_codec_driver.nim']
               + list((ROOT/'tests').glob('report_*.py'))
               + list((ROOT/'tests').glob('guarantees_*.py'))
               + [ROOT/'tests/native/guarantees_driver.nim', ROOT/'tests/native/tickets_driver.nim',
                  ROOT/'tests/tickets_oracle.py', ROOT/'tests/test_tickets_harness.py',
                  ROOT/'tests/disputes_oracle.py', ROOT/'tests/native/disputes_driver.nim',
                  ROOT/'tests/test_disputes_harness.py', ROOT/'tests/package_oracle.py',
                  ROOT/'tests/native/package_driver.nim', ROOT/'tests/test_package_harness.py',
                  ROOT/'tests/header_oracle.py', ROOT/'tests/native/header_driver.nim',
                  ROOT/'tests/test_header_harness.py', ROOT/'tests/block_oracle.py',
                  ROOT/'tests/native/block_driver.nim', ROOT/'tests/test_block_harness.py']
               + [ROOT/'tests/native/assurances_driver.nim', ROOT/'tests/assurances_oracle.py',
                  ROOT/'tests/test_codec.py', ROOT/'tests/digest_checks.py', ROOT/'spec/pins.json']
               + list((ROOT/'tests/native').glob('nimony_*.nim'))
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in (*PRIVATE, *NOMINAL)]
               + [Path(__file__).resolve()])
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(sources)}
    # The existing native guarantee suite consumes an independently authored minimal report fixture.
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantees_oracle import record as guarantee_record
    guarantee_fixture = BUILD/'minimal-report.bin'
    guarantee_fixture.write_bytes(guarantee_record(0)['report'])
    # Native parent tests use independently authored policy-valid child fixtures, never parent decoder output.
    from block_oracle import published as block_published
    block_fixture = BUILD/'block-fixtures'
    block_fixture.mkdir(exist_ok=True)
    # These five children retain their exact independent tiny-profile source identities.
    for name, data in zip(('tickets', 'preimages', 'guarantees', 'assurances', 'disputes'),
                          block_published('tiny', 'E', canonical=True)):
        (block_fixture/(name+'.bin')).write_bytes(data)
    (block_fixture/'header.bin').write_bytes(block_published('tiny', 'B', canonical=True)[0])
    # Existing positive suites retain their exact expected bytes, atomic errors and deterministic fuzzing.
    for name in SUITES:
        compiled, binary = build(compiler, ROOT/f'tests/native/test_{name}.nim', name)
        row = dict(name=name, build=compiled, passed=False)
        if compiled['exit_code'] == 0:
            # Never run stale binaries after a failed build.
            row['run'] = command([binary, *([guarantee_fixture] if name == 'guarantees' else [block_fixture] if name == 'block' else [])], name+'-run')
            row['passed'] = row['run']['exit_code'] == 0
            if name == 'ownership' and row['passed']:
                # Retain public live-memory measurements for the isolated five-schema ARC release workload.
                release = re.search(r'ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Counts refer to live allocator occupancy after warmup, never retained RSS/pages.
                    report['arc_release'] = dict(cycles=1000, schemas=5, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'report_snapshots' and row['passed']:
                # Isolated report retain/replace/drop cycles must return public live occupancy to baseline.
                release = re.search(r'REPORT_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # This is allocator live occupancy, not a general leak-freedom or RSS claim.
                    report['report_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'guarantees' and row['passed']:
                # Report children survive parent retirement; all isolated scopes must release their final ARC references.
                release = re.search(r'GUARANTEE_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Observe only public live occupancy after warmup, never RSS or private reference counts.
                    report['guarantee_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'disputes' and row['passed']:
                # All isolated snapshot aliases, nested source sequences and record copies must release through ARC.
                release = re.search(r'DISPUTE_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy covers this workload, not private reference counts or RSS.
                    report['dispute_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'work_package' and row['passed']:
                # Independent retained children must release their parent snapshots at the last child reference.
                release = re.search(r'PACKAGE_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy measures this warmed workload, not RSS or general leak freedom.
                    report['package_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'header' and row['passed']:
                # Signing and marker views must retain their exact original snapshot until the last view is released.
                release = re.search(r'HEADER_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy observes this isolated warmed ARC workload, not RSS or refcount internals.
                    report['header_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'block' and row['passed']:
                # Replaced parents and all six materialized child families must release their final ARC references.
                release = re.search(r'BLOCK_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy measures this warmed workload, not RSS or general leak freedom.
                    report['block_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        report['suites'].append(row)
        announce(name, row['passed'])
    # Run the unchanged independent report oracle through a codec-only adapter; M2 signatures remain separate.
    sys.path.insert(0, str(ROOT/'tests'))
    from report_oracle import requests
    lines, expected = requests()
    source = BUILD/'report-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/report_codec_driver.nim', 'report-codec')
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare all encoded bytes and decoded semantic fields, including malformed and published fixtures.
        result = command([binary, source], 'report-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Record the first semantic difference while retaining complete output in the adjacent log.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['report_corpus'] = corpus
    announce('independent report corpus', corpus['passed'])
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
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/assurances_driver.nim', 'assurances-codec')
    corpus = dict(build=compiled, codec_requests=codec_count, inspection_requests=len(lines)-codec_count,
                  requests=len(lines), passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare complete named fields/bytes and errors; native assertions additionally protect atomic output/lifetimes.
        result = command([binary, source], 'assurances-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first differing row and full adjacent log for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['assurance_corpus'] = corpus
    announce('independent assurance codec/inspection corpus', corpus['passed'])
    # Keep the original guarantee corpus intact and independently check inspection and standalone APIs.
    from guarantees_checks import requests as guarantee_requests
    lines, expected, counts = guarantee_requests()
    source = BUILD/'guarantee-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/guarantees_driver.nim', 'guarantees-codec')
    corpus = dict(build=compiled, request_groups=counts, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Native assertions additionally cover input mutation, copied metadata and whole-output atomicity.
        result = command([binary, source], 'guarantees-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first differing row and exact full output instead of reporting a round-trip-only success.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
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
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/tickets_driver.nim', 'tickets-codec')
    corpus = dict(build=compiled, original_requests=original_count, codec_requests=codec_count,
                  inspection_requests=len(lines)-codec_count, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Exact attempts/proofs and consumed metadata are observed independently after source mutation.
        result = command([binary, source], 'tickets-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first differing row plus complete output for a reproducible failure.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
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
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/disputes_driver.nim', 'disputes-codec')
    corpus = dict(build=compiled, original_requests=original_count, codec_requests=codec_count,
                  inspection_requests=len(lines)-codec_count, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Native checks also protect owner copies, exact prefix retention and whole-output failure atomicity.
        result = command([binary, source], 'disputes-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Record the first disagreement while keeping complete actual output beside the JSON evidence.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['dispute_corpus'] = corpus
    announce('independent dispute codec/inspection corpus', corpus['passed'])
    # The unchanged package oracle covers context, import, commitment, standalone item and complete package APIs.
    from package_oracle import requests as package_requests
    lines, expected = package_requests()
    groups = {kind: sum(line.split(' ', 2)[1] == kind for line in lines) for kind in ('C', 'R', 'X', 'I', 'P')}
    source = BUILD/'package-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/package_driver.nim', 'package-codec')
    corpus = dict(build=compiled, request_groups=groups, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Every typed field/payload is observed independently after original input mutation; failures retain sentinels.
        result = command([binary, source], 'package-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first semantic disagreement and adjacent complete log for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
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
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/header_driver.nim', 'header-codec')
    corpus = dict(build=compiled, original_requests=original_count, request_groups=groups,
                  inspection_requests=len(lines)-original_count, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Independently observe every field after source erasure, marker retention and exact signing-prefix checks.
        result = command([binary, source], 'header-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first differing row while retaining complete native output beside the evidence JSON.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['header_corpus'] = corpus
    announce('independent ticket/epoch/winner/unsigned/full-header corpus', corpus['passed'])
    # Preserve every independent whole-block/extrinsic expectation, including actual published policy failures.
    from block_oracle import requests as block_requests
    harness = command([sys.executable, ROOT/'tests/test_block_harness.py'], 'block-harness')
    lines, expected = block_requests()
    source = BUILD/'block-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {operation+'-'+kind: sum(line.startswith(operation+' '+kind+' ') for line in lines)
              for operation in ('D', 'E') for kind in ('E', 'B')}
    compiled, binary = build(compiler, ROOT/'tests/native/block_driver.nim', 'block-codec')
    corpus = dict(build=compiled, harness=harness, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare all six exact child wires/counts after source erasure and on-demand materialization.
        result = command([binary, source], 'block-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first mismatch plus complete native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['block_corpus'] = corpus
    announce('independent complete extrinsic/block corpus', corpus['passed'])
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
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_wrong_variant.nim', 'bounded-results')
    report['bounded_build'] = compiled
    if compiled['exit_code'] == 0:
        # Compile once, then exercise all branches independently with runtime-selected input modes.
        for origin in ('default', 'error'):
            # Each member has its own subprocess and exact contract-failure diagnostic.
            for member in MEMBERS:
                result = command([binary, member, origin], 'bounded-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['bounded'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' '+member+' guard', passed)
    # Primitive success payloads are guarded on defaults/errors; error reasons are guarded on success.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_primitive_results.nim', 'primitive-results')
    report['primitive_build'] = compiled
    if compiled['exit_code'] == 0:
        # Ten failure/default payload reads and three success-side error reads each run independently.
        cases = [(member, origin) for origin in ('default', 'error') for member in PRIMITIVE_MEMBERS]
        cases += [(member, 'success') for member in PRIMITIVE_ERRORS]
        for member, origin in cases:
            result = command([binary, member, origin], 'primitive-'+origin+'-'+member)
            passed = (result['exit_code'] == 1 and 'value.success' in result['output']
                      and '[AssertionDefect]' in result['output'])
            report['primitive'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Composite results, nested variants and explicit constructor preconditions are independently guarded.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_composite_results.nim', 'composite-results')
    report['composite_build'] = compiled
    if compiled['exit_code'] == 0:
        # Eighteen failure/default result reads, eight absent/error variant reads and three bad factories.
        cases = [(member, origin) for origin in ('default', 'error') for member in COMPOSITE_MEMBERS]
        cases += [('absent-blob', origin) for origin in ('default', 'absent')]
        cases += [('error-work-blob', str(tag)) for tag in range(1, 7)]
        cases += [('factory-work', 'success'), ('factory-written', 'negative'), ('factory-failure', 'none')]
        for member, origin in cases:
            result = command([binary, member, origin], 'composite-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and '[AssertionDefect]' in result['output']
            # Match the actual precondition, so an unrelated assertion cannot conceal a bad accessor.
            if member in COMPOSITE_MEMBERS:
                passed = passed and 'value.status == None' in result['output']
            elif member == 'absent-blob':
                passed = passed and 'value.isPresent' in result['output']
            elif member == 'error-work-blob':
                passed = passed and 'value.outputKind == Success' in result['output']
            elif member == 'factory-work':
                passed = passed and 'not kind == Success' in result['output']
            elif member == 'factory-written':
                passed = passed and '0 <= extent' in result['output']
            else:
                passed = passed and 'not reason == None' in result['output']
            report['composite'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Generic owned payloads, absent/error metadata and explicit factories retain independent guards.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_owned_results.nim', 'owned-results')
    report['owned_build'] = compiled
    if compiled['exit_code'] == 0:
        # Sixteen failed/default payload reads, eight absent/error lengths and three constructor failures.
        cases = [(member, origin) for origin in ('default', 'error') for member in OWNED_MEMBERS]
        cases += [('absent-length', origin) for origin in ('default', 'absent')]
        cases += [('work-error-length', str(tag)) for tag in range(1, 7)]
        cases += [('factory-failure', 'none'), ('factory-length', 'negative'), ('factory-work', 'success')]
        for member, origin in cases:
            result = command([binary, member, origin], 'owned-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and '[AssertionDefect]' in result['output']
            # Reject unrelated process failures by matching the intended result/variant/factory contract.
            if member in OWNED_MEMBERS:
                passed = passed and 'value.status == None' in result['output']
            elif member == 'absent-length':
                passed = passed and 'value.isPresent' in result['output']
            elif member == 'work-error-length':
                passed = passed and 'value.outputKind == Success' in result['output']
            elif member == 'factory-failure':
                passed = passed and 'not reason == None' in result['output']
            elif member == 'factory-length':
                passed = passed and '0 <= length' in result['output']
            else:
                passed = passed and 'not kind == Success' in result['output']
            report['owned'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' '+member+' guard', passed)
    # Report/header and newly instantiated owned results reject all failed/default payload access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_report_results.nim', 'report-results')
    report['reports_build'] = compiled
    if compiled['exit_code'] == 0:
        # Each result member has its own subprocess and exact success-precondition diagnostic.
        for origin in ('default', 'error'):
            # Do not let one rejected accessor conceal another unguarded payload.
            for member in REPORT_MEMBERS:
                result = command([binary, member, origin], 'report-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['reports'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' '+member+' guard', passed)
    # Decoder and inspection progress share the same result type but must reject each failing operation independently.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_assurance_results.nim', 'assurance-results')
    report['assurances_build'] = compiled
    if compiled['exit_code'] == 0:
        # Each default and actual typed failure runs separately, preserving assertions in optimized builds.
        for origin in ('default', 'error'):
            # Read-only success metadata must not silently return zeros from a failed variant.
            for member in ASSURANCE_MEMBERS:
                result = command([binary, member, origin], 'assurance-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['assurances'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' assurance '+member+' guard', passed)
    # Every public guarantee result instantiation must protect failed/default values, including inspection tuples.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_guarantee_results.nim', 'guarantee-results')
    report['guarantees_build'] = compiled
    if compiled['exit_code'] == 0:
        # Independent processes prove all metadata paths and the failure factory's non-success requirement.
        cases = [(member, origin) for origin in ('default', 'error') for member in GUARANTEE_MEMBERS]
        cases += [('factory', 'none')]
        for member, origin in cases:
            result = command([binary, member, origin], 'guarantee-'+origin+'-'+member)
            sentinel = 'not reason == None' if member == 'factory' else 'value.status == None'
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['guarantees'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' guarantee '+member+' guard', passed)
    # Ticket write, decode and inspection APIs reject progress reads on defaults and actual typed failures.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_ticket_results.nim', 'ticket-results')
    report['tickets_build'] = compiled
    if compiled['exit_code'] == 0:
        # Match each success contract separately so an unrelated crash cannot count as protection.
        for origin in ('default', 'error'):
            # Decode and inspection share a result type but both operation paths must be exercised.
            for member in TICKET_MEMBERS:
                result = command([binary, member, origin], 'ticket-'+origin+'-'+member)
                passed = (result['exit_code'] == 1 and 'value.status == None' in result['output']
                          and '[AssertionDefect]' in result['output'])
                report['tickets'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' ticket '+member+' guard', passed)
    # Every public dispute result type and explicit failure construction retain success contracts.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_dispute_results.nim', 'dispute-results')
    report['disputes_build'] = compiled
    if compiled['exit_code'] == 0:
        # Separate processes prevent one rejection from concealing a later unguarded owner/record/progress path.
        cases = [(member, origin) for origin in ('default', 'error') for member in DISPUTE_MEMBERS]
        cases += [('factory', 'none')]
        for member, origin in cases:
            result = command([binary, member, origin], 'dispute-'+origin+'-'+member)
            sentinel = 'not reason == None' if member == 'factory' else 'value.status == None'
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['disputes'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' dispute '+member+' guard', passed)
    # Every public package result instantiation and both import identity alternatives retain checked access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_package_results.nim', 'package-results')
    report['packages_build'] = compiled
    if compiled['exit_code'] == 0:
        # Default and actual failed result paths are isolated, along with both wrong-identity reads.
        cases = [(member, origin) for origin in ('default', 'error') for member in PACKAGE_MEMBERS]
        cases += [('wrong-root', 'package'), ('wrong-package', 'default'), ('wrong-package', 'root')]
        for member, origin in cases:
            result = command([binary, member, origin], 'package-'+origin+'-'+member)
            sentinel = ('value.referenceKind == Root' if member == 'wrong-root' else
                        'value.referenceKind == Package' if member == 'wrong-package' else 'value.status == None')
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['packages'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' package '+member+' guard', passed)
    # Guard all public header result instantiations and both source/metadata optional alternatives.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_header_results.nim', 'header-results')
    report['headers_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate each result access, absent-field read/edit and invalid failure construction in its own process.
        cases = [(member, origin) for origin in ('default', 'error') for member in HEADER_MEMBERS]
        cases += [(member, origin) for origin in ('default', 'absent') for member in HEADER_OPTIONAL]
        cases += [('factory', 'none')]
        for member, origin in cases:
            result = command([binary, member, origin], 'header-'+origin+'-'+member)
            sentinel = ('value.isPresent' if member in HEADER_OPTIONAL else
                        'not reason == None' if member == 'factory' else 'value.status == None')
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['headers'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' header '+member+' guard', passed)
    # Parent values and nested component reasons require independent checked alternatives.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_block_results.nim', 'block-results')
    report['blocks_build'] = compiled
    if compiled['exit_code'] == 0:
        # Default/actual failures, non-child outcomes and every wrong schema are isolated in separate processes.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in BLOCK_MEMBERS]
        cases += [(member, 'error', 'value.status == InvalidComponent')
                  for member in ('cause-default', 'cause-parent', 'cause-success')]
        cases += [(member, 'error', 'value.schema == '+kind) for member, kind in BLOCK_WRONG]
        for member, origin, sentinel in cases:
            result = command([binary, member, origin], 'block-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['blocks'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' block '+member+' guard', passed)
    # Raw storage, retagging, success forgery and writing the public reason must all fail compilation.
    for name, member in PRIVATE.items():
        source = ROOT/f'tests/native/compile_fail/{name}.nim'
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', source], name)
        if name == 'wrong_owner_pool':
            # The second argument must be an index, never a replacement source buffer.
            rejected = 'Type mismatch' in result['output'] and '[2] expected: int64 but got: array' in result['output']
        else:
            # Every raw-state bypass must fail for its private/read-only member.
            rejected = ('undeclared field' in result['output'] or 'cannot assign' in result['output']
                        or 'cannot be assigned' in result['output'])
        passed = result['exit_code'] != 0 and member in result['output'] and rejected
        report['privacy'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Report and assurance identity, index and configuration domains must remain statically distinct under Nimony.
    for name, member in NOMINAL.items():
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        if name == 'swapped_import_identity':
            # The typed factory rejection prints generic ReportHash without its static domain; require its exact call/position.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'rootImport(' in result['output'] and member in result['output'])
        elif name in ('unsigned_as_full_header', 'block_as_extrinsic'):
            # Sealed output accepts only the full owner type, never a signing-only retained view.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and ('extrinsicInfo(' if name == 'block_as_extrinsic' else 'encodeOwnedHeader(') in result['output']
                        and member in result['output'])
        else:
            # Other nominal fields provide precise got/wanted domain names.
            rejected = 'Error: type mismatch: '+member in result['output']
        passed = result['exit_code'] != 0 and rejected
        report['nominal'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    step_passed = (all(row['passed'] for row in report['suites']) and len(report['runtime']) == 3
                   and all(row['passed'] for row in report['runtime']) and len(report['bounded']) == 12
                   and all(row['passed'] for row in report['bounded'])
                   and len(report['primitive']) == 13 and all(row['passed'] for row in report['primitive'])
                   and len(report['composite']) == 29 and all(row['passed'] for row in report['composite'])
                   and len(report['owned']) == 27 and all(row['passed'] for row in report['owned'])
                   and report['report_corpus']['passed'] and report['assurance_corpus']['passed']
                   and report['guarantee_corpus']['passed'] and report['ticket_corpus']['passed']
                   and report['dispute_corpus']['passed'] and report['package_corpus']['passed']
                   and report['header_corpus']['passed'] and report['block_corpus']['passed']
                   and len(report['blocks']) == 2*len(BLOCK_MEMBERS)+3+len(BLOCK_WRONG)
                   and all(row['passed'] for row in report['blocks'])
                   and len(report['headers']) == 81 and all(row['passed'] for row in report['headers'])
                   and len(report['packages']) == 51 and all(row['passed'] for row in report['packages'])
                   and len(report['disputes']) == 25 and all(row['passed'] for row in report['disputes'])
                   and len(report['tickets']) == 10 and all(row['passed'] for row in report['tickets'])
                   and len(report['guarantees']) == 29 and all(row['passed'] for row in report['guarantees'])
                   and len(report['assurances']) == 10 and all(row['passed'] for row in report['assurances'])
                   and len(report['reports']) == 14 and all(row['passed'] for row in report['reports'])
                   and len(report['nominal']) == len(NOMINAL) and all(row['passed'] for row in report['nominal'])
                   and len(report['privacy']) == len(PRIVATE)
                   and all(row['passed'] for row in report['privacy']))
    report['protected_results_increment'] = 'passed' if step_passed else 'failed'
    report['status'] = 'partial-checks-passed' if step_passed else 'blocked'
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Protected results: {report["protected_results_increment"]}; migration trial: {report["status"]}')
    print(f'Evidence: {BUILD.relative_to(ROOT)}/results.json')
    raise SystemExit(0 if report['status'] == 'partial-checks-passed' else 1)


# Importing this runner never downloads dependencies or starts a compiler.
if __name__ == '__main__':
    main()
