#!/usr/bin/env python3
"""Verify checked native suites, independent corpora, runtime misuse contracts."""
import argparse
import os
import hashlib
import json
import platform
import re
from pathlib import Path
import subprocess
import sys
from native_checks import NativeChecks, announce
from native_tests import UNIT_SUITES, unit_batches, unit_jobs, unit_work_directory, unit_source, unit_command, unit_environment, unit_evidence, ARC_SUITES, unit_fixture_sources, unit_runtime_fixtures, unit_store_fixture, unit_authorization_fixture, unit_history_fixture, unit_signing_fixture, unit_entropy_fixture, unit_validator_fixture, unit_ticket_fixture, unit_sealer_fixture

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/tests/runtime'
SUITES = ('telemetry', 'telemetry_chain', 'natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'assurances', 'guarantees', 'tickets', 'disputes', 'work_package', 'header', 'block', 'block_private', 'bits', 'bits_private', 'collections', 'collections_private', 'c2', 'c2_private', 'crypto_seeds', 'state_layout', 'state_trie', 'state_trie_private', 'state_store', 'state_store_failure', 'state_store_replay', 'authorization_transition', 'authorization_transition_failure', 'history_transition', 'history_transition_failure', 'entropy_transition', 'entropy_transition_failure', 'validator_rotation', 'validator_state', 'ticket_admission', 'ticket_state', 'sealer_schedule', 'sealer_state', 'safrole_markers', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private', 'state_history', 'state_history_private', 'state_availability', 'state_availability_private', 'state_privileges', 'state_privileges_private', 'state_statistics', 'state_statistics_private', 'state_workqueues', 'state_workqueues_private', 'state_outputs', 'state_outputs_private', 'state_accounts', 'state_accounts_private', 'state_service_values', 'service_values_private', 'state_requests', 'state_requests_private', 'state_composition_private', 'assurance_context', 'guarantee_message', 'signing_domains', 'bandersnatch_owners', 'quic_io', 'quic_transport', 'quic_protocol', 'quic_integration', 'quic_integration_disabled')
PRIVATE = dict(safrole_marker_private='completed', safrole_marker_retag='status', safrole_epoch_private='epochValue', safrole_winners_private='winnersValue', sealer_state_private='completed', sealer_state_retag='status', sealer_schedule_private='completed', sealer_schedule_retag='status', ticket_state_private='completed', ticket_state_retag='status', ticket_admission_private='completed', ticket_admission_retag='status', validator_state_private='completed', validator_state_retag='status', validator_rotation_private='completed', validator_rotation_retag='status', entropy_transition_private='completed', entropy_transition_retag='status', history_transition_private='completed', history_transition_retag='status', authorization_transition_private='completed', authorization_transition_retag='status', store_result_retag='status', store_head_private='head', store_snapshot_private='data',
               store_value_private='owner', store_result_private='completed', bounded_blob_private='byteLength', bounded_write_private='byteWritten',
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
BITS_PRIVATE = {
    'private_bits_snapshot': 'data',
    'bits_result_private': 'completed',
    'bits_result_read_private': 'completed',
    'bits_result_boolean_private': 'completed',
    'bits_result_info_private': 'completed',
    'bits_result_bit_private': 'completed',
    'bits_result_retag': 'status',
    'bits_result_forge': 'status',
    'bits_result_error_write': 'error',
    'bits_result_value_write': 'value',
}
BITS_MEMBERS = (
    'boolean-value', 'boolean-consumed', 'variable-owner', 'variable-consumed', 'fixed-owner',
    'fixed-consumed', 'info-count', 'info-packed', 'bit', 'bit-index', 'boolean-write',
    'variable-write', 'fixed-write', 'owned-variable-write', 'owned-fixed-write',
)
COLLECTION_PRIVATE = {
    'private_set_snapshot': 'data',
    'private_dictionary_snapshot': 'data',
    'collection_result_integer_private': 'completed',
    'collection_result_count_private': 'completed',
    'collection_result_set_private': 'completed',
    'collection_result_dictionary_private': 'completed',
    'collection_result_scalar_private': 'completed',
    'collection_result_pair_private': 'completed',
    'collection_result_retag': 'status',
    'collection_result_forge': 'status',
    'collection_result_error_write': 'error',
    'collection_result_value_write': 'value',
    'private_collection_unit': 'unit',
    'private_collection_commit': 'put',
}
COLLECTION_MEMBERS = (
    'set-owner', 'set-consumed', 'dictionary-owner', 'dictionary-consumed', 'set-count',
    'dictionary-count', 'natural', 'unsigned', 'bytes', 'pair-key', 'pair-value', 'fixed-write',
    'variable-write', 'dictionary-write', 'owned-fixed-write', 'owned-variable-write',
    'owned-dictionary-write', 'scalar-natural', 'scalar-natural-consumed', 'scalar-unsigned',
    'scalar-bytes', 'scalar-size', 'scalar-natural-write', 'scalar-unsigned-write',
    'scalar-bytes-write',
)
C2_PRIVATE = {
    'private_operand_snapshot': 'data',
    'c2_result_integer_private': 'completed',
    'c2_result_availability_private': 'completed',
    'c2_result_transfer_private': 'completed',
    'c2_result_operand_private': 'completed',
    'c2_result_info_private': 'completed',
    'c2_result_union_private': 'completed',
    'c2_result_retag': 'status',
    'c2_result_forge': 'status',
    'c2_result_error_write': 'error',
    'c2_result_value_write': 'value',
    'c2_output_tag_private': 'outputKind',
    'c2_output_payloadValues_private': 'payloadValues',
    'c2_output_retag': 'outputKind',
    'c2_output_forge': 'outputKind',
    'c2_output_kind_write': 'kind',
    'c2_output_info_tag_private': 'outputKind',
    'c2_output_info_byteLength_private': 'byteLength',
    'c2_output_info_retag': 'outputKind',
    'c2_output_info_forge': 'outputKind',
    'c2_output_info_kind_write': 'kind',
    'c2_output_info_length_write': 'length',
    'c2_source_tag_private': 'inputKind',
    'c2_source_operandValue_private': 'operandValue',
    'c2_source_transferValue_private': 'transferValue',
    'c2_source_retag': 'inputKind',
    'c2_source_forge': 'inputKind',
    'c2_source_kind_write': 'kind',
    'c2_source_operand_write': 'operand',
    'c2_source_transfer_write': 'transfer',
    'c2_decoded_tag_private': 'inputKind',
    'c2_decoded_operandOwner_private': 'operandOwner',
    'c2_decoded_transferValue_private': 'transferValue',
    'c2_decoded_retag': 'inputKind',
    'c2_decoded_forge': 'inputKind',
    'c2_decoded_kind_write': 'kind',
    'c2_decoded_operand_write': 'operand',
    'c2_decoded_transfer_write': 'transfer',
}
C2_MEMBERS = (
    'av-value', 'av-consumed', 'transfer-value', 'transfer-consumed', 'operand-owner',
    'operand-consumed', 'info', 'union-value', 'union-consumed', 'av-write', 'transfer-write',
    'operand-write', 'union-write', 'owned-write', 'output-copy', 'trace-copy',
)
C2_VARIANTS = (
    ('outofgas-copy', 'error', 'value.outputKind == Success'),
    ('outofgas-edit', 'error', 'value.outputKind == Success'),
    ('outofgas-metadata', 'error', 'value.outputKind == Success'),
    ('panic-copy', 'error', 'value.outputKind == Success'),
    ('panic-edit', 'error', 'value.outputKind == Success'),
    ('panic-metadata', 'error', 'value.outputKind == Success'),
    ('badexports-copy', 'error', 'value.outputKind == Success'),
    ('badexports-edit', 'error', 'value.outputKind == Success'),
    ('badexports-metadata', 'error', 'value.outputKind == Success'),
    ('oversize-copy', 'error', 'value.outputKind == Success'),
    ('oversize-edit', 'error', 'value.outputKind == Success'),
    ('oversize-metadata', 'error', 'value.outputKind == Success'),
    ('bad-copy', 'error', 'value.outputKind == Success'),
    ('bad-edit', 'error', 'value.outputKind == Success'),
    ('bad-metadata', 'error', 'value.outputKind == Success'),
    ('big-copy', 'error', 'value.outputKind == Success'),
    ('big-edit', 'error', 'value.outputKind == Success'),
    ('big-metadata', 'error', 'value.outputKind == Success'),
    ('source-operand', 'error', 'value.inputKind == Operand'),
    ('source-transfer', 'error', 'value.inputKind == Transfer'),
    ('source-default-transfer', 'error', 'value.inputKind == Transfer'),
    ('decoded-operand', 'error', 'value.inputKind == Operand'),
    ('decoded-transfer', 'error', 'value.inputKind == Transfer'),
    ('factory', 'none', 'not kind == Success'),
)
PRIVATE.update(C2_PRIVATE)
NOMINAL.update(c2_balance_as_gas="got: TransferBalance but wanted: Gas",
               c2_swapped_root="got: ReportHash but wanted: ReportHash",
               c2_swapped_payload_hash="got: ReportHash but wanted: PayloadHash")
PRIVATE.update(COLLECTION_PRIVATE)
NOMINAL.update(raw_collection_count="[2] expected: CollectionCount but got: uint64",
               swapped_collection_schema="[1] expected: CollectionUInt but got: CollectionUInt",
               dictionary_as_set="[1] expected: OwnedSet[T] but got: OwnedDictionary")
PRIVATE.update(BITS_PRIVATE)
NOMINAL.update(raw_bit_count="[2] expected: BitCount but got: uint64",
               swapped_bit_limit="[2] expected: BitLimit but got: ByteLimit")
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
PRIVATE.update(crypto_blake_private='completed', crypto_keccak_private='completed',
               crypto_seed_private='completed', crypto_key_private='completed',
               crypto_signature_private='completed', crypto_result_retag='status',
               crypto_result_forge='status', crypto_result_error_write='error',
               crypto_result_value_write='value', crypto_seed_storage='storage',
               crypto_seed_forge='storage')
NOMINAL.update(crypto_swapped_hash='got: KeccakHash but wanted: Blake2bHash',
               crypto_swapped_key='got: EdSignature but wanted: EdPublicKey')
CRYPTO_MEMBERS = ('blake', 'keccak', 'seed-width', 'key-width', 'signature-width',
                  'key-missing', 'key-cleared', 'key-backend', 'sign-missing', 'sign-cleared', 'sign-backend')
LAYOUT_PRIVATE = dict(
    layout_result_key_private='completed',
    layout_result_node_private='completed',
    layout_result_read_private='completed',
    layout_result_hash_private='completed',
    layout_result_retag='status',
    layout_result_forge='status',
    layout_result_error_write='error',
    layout_result_value_write='value',
    layout_metadata_private='nodeKind',
    layout_metadata_retag='nodeKind',
    layout_metadata_forge='nodeKind',
    layout_metadata_kind_write='kind',
    layout_left_private='branchLeft',
    layout_left_write='left',
    layout_right_private='branchRight',
    layout_right_write='right',
    layout_embeddedKey_private='inlineKey',
    layout_embeddedKey_write='embeddedKey',
    layout_length_private='inlineLength',
    layout_length_write='length',
    layout_embedded_private='inlineBytes',
    layout_embedded_write='embedded',
    layout_hashedKey_private='regularKey',
    layout_hashedKey_write='hashedKey',
    layout_valueHash_private='regularHash',
    layout_valueHash_write='valueHash',
)
PRIVATE.update(LAYOUT_PRIVATE)
NOMINAL.update(state_key_as_hash='StateKey',
               state_partial_as_hash='LeftChildCommitment',
               state_value_as_node_hash='StateValueHash')
LAYOUT_MEMBERS = ('key-limit', 'leaf-limit', 'node-info', 'node-consumed', 'metadata-invalid', 'hash-invalid', 'key-backend', 'leaf-backend', 'hash-backend')
LAYOUT_VARIANTS = [('Branch-embeddedKey', 'Branch', 'node.nodeKind == EmbeddedLeaf'), ('Branch-length', 'Branch', 'node.nodeKind == EmbeddedLeaf'), ('Branch-embedded', 'Branch', 'node.nodeKind == EmbeddedLeaf'), ('Branch-hashedKey', 'Branch', 'node.nodeKind == HashedLeaf'), ('Branch-valueHash', 'Branch', 'node.nodeKind == HashedLeaf'), ('EmbeddedLeaf-left', 'EmbeddedLeaf', 'node.nodeKind == Branch'), ('EmbeddedLeaf-right', 'EmbeddedLeaf', 'node.nodeKind == Branch'), ('EmbeddedLeaf-hashedKey', 'EmbeddedLeaf', 'node.nodeKind == HashedLeaf'), ('EmbeddedLeaf-valueHash', 'EmbeddedLeaf', 'node.nodeKind == HashedLeaf'), ('HashedLeaf-left', 'HashedLeaf', 'node.nodeKind == Branch'), ('HashedLeaf-right', 'HashedLeaf', 'node.nodeKind == Branch'), ('HashedLeaf-embeddedKey', 'HashedLeaf', 'node.nodeKind == EmbeddedLeaf'), ('HashedLeaf-length', 'HashedLeaf', 'node.nodeKind == EmbeddedLeaf'), ('HashedLeaf-embedded', 'HashedLeaf', 'node.nodeKind == EmbeddedLeaf')]
TRIE_PRIVATE = dict(
    trie_result_commitment_private='completed',
    trie_result_hash_private='completed',
    trie_result_retag='status',
    trie_result_forge='status',
    trie_result_error_write='error',
    trie_result_value_write='value',
)
PRIVATE.update(TRIE_PRIVATE)
NOMINAL.update(state_root_as_node='StateRoot', state_bytes_as_nodes='got: ByteLimit but wanted: TrieNodeLimit')
TRIE_ORIGINS = ('default', 'item-limit', 'per-value-limit', 'total-value-limit',
                'node-limit', 'duplicate', 'backend-first', 'backend-late')
SAFROLE_PRIVATE = dict(
    safrole_result_entropy_private='completed',
    safrole_result_time_private='completed',
    safrole_result_snapshot_private='completed',
    safrole_result_entry_private='completed',
    safrole_result_integer_private='completed',
    safrole_result_validator_private='completed',
    safrole_result_direct_time_private='completed',
    safrole_result_retag='status',
    safrole_result_forge='status',
    safrole_result_error_write='error',
    safrole_result_value_write='value',
    safrole_owner_data='data',
    safrole_owner_rebind='data',
)
SAFROLE_PRIVATE['state_validator_private'] = 'data'
PRIVATE.update(SAFROLE_PRIVATE)
NOMINAL.update(state_ed_as_bs='got: StateEdKey but wanted: StateBsKey', state_entropy_as_time='StateEntropyWord')
SAFROLE_MEMBERS = (
    'entry-tag',
    'entropy-value',
    'entropy-consumed',
    'time-value',
    'time-consumed',
    'entry',
    'snapshot',
    'snapshot-consumed',
    'prefix',
    'size',
    'count',
    'item',
    'index',
    'size-overflow',
    'decode-overflow',
    'decode-config',
    'decode-count',
    'decode-policy',
    'decode-noncanonical',
)
AUTHORIZATION_PRIVATE = dict(
    authorization_result_entry_private='completed',
    authorization_result_read_private='completed',
    authorization_result_kind_private='completed',
    authorization_result_integer_private='completed',
    authorization_result_hash_private='completed',
    authorization_result_count_private='completed',
    authorization_result_retag='status',
    authorization_result_forge='status',
    authorization_result_error_write='error',
    authorization_result_value_write='value',
    authorization_owner_data='data',
    authorization_owner_rebind='data',
)
AUTHORIZATION_PRIVATE['auth_snapshot_private'] = 'data'
PRIVATE.update(AUTHORIZATION_PRIVATE)
NOMINAL.update(auth_core_as_position='AuthorizationCoreIndex', auth_bytes_as_hashes='got: ByteLimit but wanted: ElementLimit')
AUTHORIZATION_MEMBERS = (
    'entry-shape',
    'entry-kind',
    'entry-config',
    'entry-policy',
    'snapshot',
    'consumed',
    'decode-kind',
    'decode-config',
    'decode-count',
    'decode-noncanonical',
    'decode-policy',
    'decode-overflow',
    'kind',
    'cores',
    'count-owner',
    'count-index',
    'hash-owner',
    'hash-core',
    'hash-index',
    'hash-empty',
    'tuple-count',
    'tuple-prefix',
)
CONSENSUS_PRIVATE = dict(
    consensus_result_entry_private='completed',
    consensus_result_read_private='completed',
    consensus_result_info_private='completed',
    consensus_result_validator_private='completed',
    consensus_result_ticket_private='completed',
    consensus_result_key_private='completed',
    consensus_result_count_private='completed',
    consensus_result_retag='status',
    consensus_result_forge='status',
    consensus_result_error_write='error',
    consensus_result_value_write='value',
    consensus_schedule_tag='mode',
    consensus_schedule_tickets='ticketValues',
    consensus_schedule_keys='keyValues',
    consensus_schedule_retag='mode',
    consensus_schedule_forge='mode',
    consensus_schedule_kind_write='kind',
    consensus_schedule_tickets_write='tickets',
    consensus_schedule_keys_write='keys',
    consensus_owner_data='data',
    consensus_owner_rebind='data',
)
CONSENSUS_PRIVATE['state_consensus_private'] = 'data'
PRIVATE.update(CONSENSUS_PRIVATE)
NOMINAL.update(state_bls_as_ring='got: StateBlsKey but wanted: StateRingRoot', state_validator_as_slot='StateValidatorIndex')
CONSENSUS_MEMBERS = (
    'entry-count',
    'entry-config',
    'entry-policy',
    'entry-bytes',
    'owner',
    'consumed',
    'decode-config',
    'decode-roster',
    'decode-tag',
    'decode-framing',
    'decode-count',
    'decode-policy',
    'decode-bytes',
    'decode-overflow',
    'info',
    'pending-owner',
    'pending-index',
    'ticket-owner',
    'ticket-variant',
    'ticket-index',
    'key-owner',
    'key-variant',
    'key-index',
    'accumulator-owner',
    'accumulator-index',
    'count-value',
    'count-size',
    'layout-pending',
    'layout-consumed',
)
STATE_DISPUTES_PRIVATE = {'state_disputes_result_entry_private': 'completed', 'state_disputes_result_read_private': 'completed', 'state_disputes_result_info_private': 'completed', 'state_disputes_result_report_private': 'completed', 'state_disputes_result_offender_private': 'completed', 'state_disputes_result_retag': 'status', 'state_disputes_result_forge': 'status', 'state_disputes_result_error_write': 'error', 'state_disputes_result_value_write': 'value', 'state_disputes_owner_rebind': 'data', 'state_disputes_private': 'data'}
PRIVATE.update(STATE_DISPUTES_PRIVATE)
NOMINAL.update(state_report_as_offender="got: DisputeHash but wanted: OffenderKey", state_bytes_as_dispute_index="ByteLimit")
STATE_DISPUTES_MEMBERS = ('entry-order', 'entry-limit', 'owner', 'consumed', 'decode-order', 'decode-framing', 'decode-limit', 'decode-overflow', 'decode-bytes', 'info', 'report-owner', 'report-index', 'report-tag', 'offender-owner', 'offender-index', 'layout')
HISTORY_PRIVATE = {'history_result_entry_private': 'completed', 'history_result_read_private': 'completed', 'history_result_info_private': 'completed', 'history_result_block_private': 'completed', 'history_result_pair_private': 'completed', 'history_result_peak_private': 'completed', 'history_result_count_private': 'completed', 'history_result_retag': 'status', 'history_result_forge': 'status', 'history_result_error_write': 'error', 'history_result_value_write': 'value', 'history_owner_rebind': 'data', 'history_peak_tag_private': 'isPresent', 'history_peak_hash_private': 'peakHash', 'history_peak_retag': 'isPresent', 'history_peak_forge': 'isPresent', 'history_peak_present_write': 'present', 'history_peak_hash_write': 'hash', 'history_snapshot_private': 'data'}
PRIVATE.update(HISTORY_PRIVATE)
# The nightly abbreviates static ReportHash domains in constructor diagnostics; the hashed probe preserves the exact substitution.
NOMINAL.update(history_segment_as_package="got: ReportHash but wanted: ReportHash", history_block_as_peak="HistoryBlockIndex")
CONTRACTS = {"history_known_absent_hash": "peak.isPresent"}
HISTORY_MEMBERS = ('entry-config', 'entry-count', 'entry-policy', 'entry-pairs', 'entry-order', 'entry-peaks', 'entry-bytes', 'decode-config', 'decode-count', 'decode-framing', 'decode-pairs', 'decode-order', 'decode-tag', 'decode-peaks', 'decode-bytes', 'decode-overflow', 'owner', 'consumed', 'info', 'block-owner', 'block-index', 'package-owner', 'package-block', 'package-index', 'peak-owner', 'peak-index', 'count-value', 'count-size', 'layout-blocks', 'layout-consumed')
AVAILABILITY_PRIVATE = {'availability_result_entry_private': 'completed', 'availability_result_read_private': 'completed', 'availability_result_info_private': 'completed', 'availability_result_assignment_private': 'completed', 'availability_result_retag': 'status', 'availability_result_forge': 'status', 'availability_result_error_write': 'error', 'availability_result_value_write': 'value', 'availability_owner_rebind': 'data', 'assignment_tag_private': 'isPresent', 'assignment_child_private': 'child', 'assignment_registration_private': 'registration', 'assignment_retag': 'isPresent', 'assignment_forge': 'isPresent', 'assignment_present_write': 'present', 'assignment_guarantee_write': 'guarantee', 'assignment_registered_write': 'registered', 'assignment_snapshot_private': 'data'}
PRIVATE.update(AVAILABILITY_PRIVATE)
NOMINAL.update(assignment_guarantee_slot="GuaranteeSlot", assignment_validator_as_core="GuarantorIndex")
CONTRACTS.update(assignment_known_absent_guarantee="assignment.isPresent", assignment_known_absent_registered="assignment.isPresent")
AVAILABILITY_MEMBERS = ('entry-config', 'entry-count', 'entry-bytes', 'entry-present', 'entry-report', 'entry-credential', 'entry-validator', 'owner', 'consumed', 'decode-config', 'decode-tag', 'decode-late', 'decode-credential', 'decode-validator', 'decode-framing', 'decode-present', 'decode-bytes', 'decode-timestamp', 'info', 'at-owner', 'at-index', 'layout-consumed', 'layout-present')
PRIVILEGES_PRIVATE = {'privilege_result_entry_private': 'completed', 'privilege_result_read_private': 'completed', 'privilege_result_info_private': 'completed', 'privilege_result_service_private': 'completed', 'privilege_result_pair_private': 'completed', 'privilege_result_natural_private': 'completed', 'privilege_result_retag': 'status', 'privilege_result_forge': 'status', 'privilege_result_error_write': 'error', 'privilege_result_value_write': 'value', 'privilege_owner_rebind': 'data', 'privilege_snapshot_private': 'data'}
PRIVATE.update(PRIVILEGES_PRIVATE)
NOMINAL.update(privilege_gas_as_service="got: PrivilegeGas but wanted: ServiceIndex", privilege_entry_as_core="PrivilegeEntryIndex")
PRIVILEGES_MEMBERS = ('entry-config', 'entry-count', 'entry-policy', 'entry-order', 'entry-bytes', 'decode-config', 'decode-fixed', 'decode-framing', 'decode-count', 'decode-overflow', 'decode-order', 'decode-gas', 'decode-bytes', 'owner', 'consumed', 'info', 'assigner-owner', 'assigner-index', 'pair-owner', 'pair-index', 'natural-truncated', 'natural-framing', 'natural-bytes', 'layout-count', 'layout-consumed')
STATISTICS_PRIVATE = {'statistics_result_entry_private': 'completed', 'statistics_result_read_private': 'completed', 'statistics_result_info_private': 'completed', 'statistics_result_validator_private': 'completed', 'statistics_result_core_private': 'completed', 'statistics_result_service_private': 'completed', 'statistics_result_natural_private': 'completed', 'statistics_result_key_private': 'completed', 'statistics_result_core_fields_private': 'completed', 'statistics_result_service_fields_private': 'completed', 'statistics_result_retag': 'status', 'statistics_result_forge': 'status', 'statistics_result_error_write': 'error', 'statistics_result_value_write': 'value', 'statistics_owner_rebind': 'data', 'statistics_snapshot_private': 'data'}
PRIVATE.update(STATISTICS_PRIVATE)
NOMINAL.update(statistics_gas_as_counter="ActivityGas", statistics_service_as_core="StatisticsServiceIndex")
STATISTICS_MEMBERS = ('entry-config', 'entry-current', 'entry-previous', 'entry-cores', 'entry-policy', 'entry-order', 'entry-bytes', 'decode-config', 'decode-count', 'decode-framing', 'decode-limit', 'decode-overflow', 'decode-order', 'decode-tail', 'decode-bytes', 'owner', 'consumed', 'info', 'validator-owner', 'validator-index', 'validator-epoch', 'core-owner', 'core-index', 'service-owner', 'service-index', 'natural', 'key', 'core-fields', 'service-fields', 'layout-services', 'layout-consumed')
# Queue result payloads and owner storage remain private across both component domains.
WORKQUEUES_PRIVATE = {'workqueue_result_entry_private': 'completed', 'workqueue_result_ready_read_private': 'completed', 'workqueue_result_acc_read_private': 'completed', 'workqueue_result_info_private': 'completed', 'workqueue_result_integer_private': 'completed', 'workqueue_result_item_private': 'completed', 'workqueue_result_hash_private': 'completed', 'workqueue_result_count_private': 'completed', 'workqueue_result_retag': 'status', 'workqueue_result_forge': 'status', 'workqueue_result_error_write': 'error', 'workqueue_result_value_write': 'value', 'workqueue_ready_rebind': 'data', 'workqueue_accumulated_rebind': 'data', 'workqueue_ready_private': 'data', 'workqueue_accumulated_private': 'data'}
PRIVATE.update(WORKQUEUES_PRIVATE)
NOMINAL.update(workqueue_hash_as_item="[3] expected: ReadyItemIndex but got: WorkQueueHashIndex",
               workqueue_item_as_slot="[2] expected: WorkQueueSlot but got: ReadyItemIndex",
               workqueue_wrong_owner="[1] expected: ReadySnapshot but got: AccumulatedSnapshot")
WORKQUEUES_MEMBERS = ('ready-entry-config', 'ready-entry-count', 'ready-entry-policy', 'ready-entry-report', 'ready-entry-child', 'ready-entry-dependencies', 'ready-entry-order', 'ready-entry-bytes', 'acc-entry-count', 'acc-entry-order', 'acc-entry-policy', 'ready-owner', 'ready-consumed', 'ready-config', 'ready-overflow', 'ready-framing', 'ready-child', 'ready-dependencies', 'ready-bytes', 'acc-owner', 'acc-consumed', 'acc-order', 'acc-overflow', 'ready-info', 'acc-info', 'ready-slot-owner', 'ready-slot-index', 'acc-slot-owner', 'acc-slot-index', 'item-owner', 'item-slot', 'item-index', 'dep-owner', 'dep-slot', 'dep-item', 'dep-index', 'hash-owner', 'hash-slot', 'hash-index', 'count-truncated', 'count-noncanonical', 'ready-layout', 'acc-layout')
# All chapter-16 result shapes and retained storage remain private/read-only to application callers.
OUTPUTS_PRIVATE = {'output_result_entry_private': 'completed', 'output_result_read_private': 'completed', 'output_result_count_private': 'completed', 'output_result_pair_private': 'completed', 'output_result_retag': 'status', 'output_result_forge': 'status', 'output_result_error_write': 'error', 'output_result_value_write': 'value', 'output_owner_rebind': 'data', 'output_snapshot_private': 'data'}
PRIVATE.update(OUTPUTS_PRIVATE)
NOMINAL.update(output_root_as_commitment="got: StateNodeHash but wanted: OutputCommitment", output_service_as_index="OutputLogIndex")
OUTPUTS_MEMBERS = ('entry-items', 'entry-bytes', 'owner', 'consumed', 'decode-framing', 'decode-items', 'decode-bytes', 'decode-overflow', 'decode-tail', 'count-owner', 'at-owner', 'at-index', 'at-empty', 'extent-items', 'extent-overflow', 'extent-bytes')
# Fixed record fields are public copies; result status and successful payloads remain private/read-only.
ACCOUNTS_PRIVATE = {'account_result_entry_private': 'completed', 'account_result_read_private': 'completed', 'account_result_retag': 'status', 'account_result_forge': 'status', 'account_result_error_write': 'error', 'account_result_value_write': 'value'}
PRIVATE.update(ACCOUNTS_PRIVATE)
NOMINAL.update(account_gas_as_balance="got: Gas but wanted: AccountBalance",
               account_bytes_as_items="got: AccountStorageBytes but wanted: AccountStorageItems",
               account_slot_as_parent="got: AccountSlot but wanted: ServiceIndex")
ACCOUNTS_MEMBERS = ('entry-bytes', 'metadata', 'consumed', 'decode-policy', 'decode-framing', 'decode-version', 'decode-version-truncated', 'decode-tail')
# Retained service-value storage and every result shape remain private/read-only to application callers.
SERVICE_VALUES_PRIVATE = {'service_value_result_key_private': 'completed', 'service_value_result_entry_private': 'completed', 'service_value_result_owner_private': 'completed', 'service_value_result_info_private': 'completed', 'service_value_result_copy_private': 'completed', 'service_value_retag': 'status', 'service_value_forge': 'status', 'service_value_error_write': 'error', 'service_value_value_write': 'value', 'service_value_owner_rebind': 'data', 'service_value_private': 'data'}
PRIVATE.update(SERVICE_VALUES_PRIVATE)
NOMINAL.update(service_value_code_as_preimage="ServicePreimageHash", service_value_hash_as_key="StateKey")
SERVICE_VALUES_MEMBERS = ('storage-key-policy', 'storage-key-backend', 'preimage-key-policy', 'preimage-key-backend', 'storage-entry-value', 'storage-entry-key', 'storage-entry-backend', 'preimage-entry-value', 'preimage-entry-key', 'preimage-entry-backend', 'capture-policy', 'capture-key', 'info-owner', 'copy-owner', 'copy-short', 'copy-alias', 'entry-owner', 'entry-policy', 'scratch-extent')
# Request result state and all inactive history payloads remain private/read-only to callers.
REQUESTS_PRIVATE = {'request_result_key_private': 'completed', 'request_result_entry_private': 'completed', 'request_result_read_private': 'completed', 'request_result_extent_private': 'completed', 'request_result_retag': 'status', 'request_result_forge': 'status', 'request_result_error_write': 'error', 'request_result_value_write': 'value', 'request_history_mode_private': 'mode', 'request_history_sinceSlot_private': 'sinceSlot', 'request_history_availableSlot_private': 'availableSlot', 'request_history_unavailableSlot_private': 'unavailableSlot', 'request_history_originalSlot_private': 'originalSlot', 'request_history_removedSlot_private': 'removedSlot', 'request_history_restoredSlot_private': 'restoredSlot', 'request_history_retag': 'mode', 'request_history_forge': 'mode', 'request_history_state_write': 'state', 'request_history_since_write': 'since', 'request_history_availableFrom_write': 'availableFrom', 'request_history_unavailableFrom_write': 'unavailableFrom', 'request_history_originalFrom_write': 'originalFrom', 'request_history_removedAt_write': 'removedAt', 'request_history_restoredAt_write': 'restoredAt'}
PRIVATE.update(REQUESTS_PRIVATE)
NOMINAL.update(request_length_as_slot="RequestSlot", request_slot_as_length="RequestLength")
CONTRACTS.update(request_known_requested_since="history.mode == Available")
REQUESTS_MEMBERS = ('owner', 'consumed', 'decode-framing', 'decode-count', 'decode-items', 'decode-bytes', 'decode-tail', 'key-policy', 'key-backend', 'entry-items', 'entry-bytes', 'entry-key', 'entry-backend', 'extent-count', 'extent-items', 'extent-bytes')
REQUESTS_FIELDS = (('since', 0, 'Available'), ('since', 2, 'Available'), ('since', 3, 'Available'), ('availableFrom', 0, 'Unavailable'), ('availableFrom', 1, 'Unavailable'), ('availableFrom', 3, 'Unavailable'), ('unavailableFrom', 0, 'Unavailable'), ('unavailableFrom', 1, 'Unavailable'), ('unavailableFrom', 3, 'Unavailable'), ('originalFrom', 0, 'Reavailable'), ('originalFrom', 1, 'Reavailable'), ('originalFrom', 2, 'Reavailable'), ('removedAt', 0, 'Reavailable'), ('removedAt', 1, 'Reavailable'), ('removedAt', 2, 'Reavailable'), ('restoredAt', 0, 'Reavailable'), ('restoredAt', 1, 'Reavailable'), ('restoredAt', 2, 'Reavailable'))
# Chapter/mapping payloads and fixed slot storage remain private behind nominal accessors.
COMPOSITION_PRIVATE = {'composition_result_chapter_private': 'completed', 'composition_result_state_private': 'completed', 'composition_result_commitment_private': 'completed', 'composition_result_entry_private': 'completed', 'composition_result_retag': 'status', 'composition_result_forge': 'status', 'composition_result_error_write': 'error', 'composition_result_value_write': 'value', 'composition_chapter_private': 'data', 'composition_chapter_rebind': 'data', 'composition_snapshot_private': 'data', 'composition_snapshot_rebind': 'data', 'composition_slots_private': 'slots', 'composition_slots_forge': 'slots'}
PRIVATE.update(COMPOSITION_PRIVATE)
NOMINAL.update(composition_service_as_entry="[2] expected: StateEntryIndex but got: ServiceIndex",
               composition_entry_as_chapter="got: StateEntry but wanted: StateChapterSnapshot",
               composition_service_as_chapter_index="[2] expected: StateChapterId but got: ServiceIndex")
COMPOSITION_MEMBERS = ('capture-config', 'capture-policy', 'capture-short', 'capture-tail', 'capture-framing', 'capture-chapter', 'compose-owner', 'compose-chapter', 'compose-profile', 'compose-policy', 'compose-captured-owner', 'compose-captured-context', 'compose-duplicate', 'compose-backend', 'compose-nodes', 'commitment-owner', 'entry-owner', 'entry-index')
# Preserve original early-codec nominal rejection fixtures, including exact argument/field diagnostics.
EARLY_NOMINAL = {
    'raw_integer': ('encode(', '[1] expected: JamNatural but got: uint64'),
    'fixed_raw_value': ('encodeFixed(', '[1] expected: FixedUnsigned but got: uint64'),
    'fixed_raw_width': ('encodeFixed(', '[2] expected: ByteWidth but got: int64'),
    'natural_as_fixed': ('encodeFixed(', '[1] expected: FixedUnsigned but got: JamNatural'),
    'raw_byte_limit': ('decodeBytesBorrowed(', '[2] expected: ByteLimit but got: uint64'),
    'wrong_limit_domain': ('decodeBytesBorrowed(', '[2] expected: ByteLimit but got: ElementLimit'),
    'raw_sequence_values': ('encodeSequence(', '[1] expected: openArray but got: array[0..0, uint64]'),
    'raw_work_variant': ('encodeWorkBorrowed(', '[1] expected: WorkOutput but got: uint8'),
}
NOMINAL.update({name: diagnostic for name, (_, diagnostic) in EARLY_NOMINAL.items()})
NOMINAL.update(raw_service_index='got: uint32 but wanted: ServiceIndex',
               wrong_preimage_limit='got: ByteLimit but wanted: ElementLimit',
               swapped_digest_hash='got: PayloadHash but wanted: CodeHash',
               raw_digest_gas='got: uint64 but wanted: Gas',
               wrong_digest_metric='got: ImportCount but wanted: ExportCount')
PRIVATE.update(mutable_owner='data', failed_digest_payload='value')
# Assurance transcripts/counts remain private, read-only and nominal despite being fixed values.
ASSURANCE_CONTEXT_PRIVATE = dict(assurance_context_message_private='completed',
    assurance_context_count_private='completed', assurance_context_status_private='status',
    assurance_context_retag='status', assurance_context_forge='status',
    assurance_context_error_write='error', assurance_context_value_write='value')
PRIVATE.update(ASSURANCE_CONTEXT_PRIVATE)
NOMINAL.update(assurance_context_parent='got: AssuranceAnchor but wanted: AssuranceParent',
               assurance_context_message='got: AssuranceSigningMessage but wanted: EdSignature')
ASSURANCE_CONTEXT_MEMBERS = ('message-config', 'message-padding', 'message-backend',
    'verify-config', 'verify-keys', 'verify-count', 'verify-index', 'verify-order', 'verify-padding',
    'verify-parent', 'verify-backend', 'verify-signature')
# Guarantee signing results own their fixed payload; raw hash/signature domains remain distinct.
GUARANTEE_MESSAGE_PRIVATE = dict(guarantee_message_private='completed',
    guarantee_message_status_private='status', guarantee_message_retag='status',
    guarantee_message_forge='status', guarantee_message_error_write='error', guarantee_message_value_write='value')
PRIVATE.update(GUARANTEE_MESSAGE_PRIVATE)
NOMINAL.update(guarantee_message_as_signature='got: GuaranteeMessage but wanted: EdSignature',
               guarantee_hash_as_message='got: Blake2bHash but wanted: GuaranteeMessage')
GUARANTEE_MESSAGE_MEMBERS = ('empty', 'bytes')
# Bandersnatch guards cover every result instantiation plus private mutable native-owner storage.
BS_PRIVATE = {f'bs_result_{name}_private': 'completed' for name in
              ('key', 'setup', 'public', 'signature', 'proof', 'root', 'output', 'members')}
BS_PRIVATE.update(bs_result_status_private='status', bs_result_retag='status', bs_result_forge='status',
                  bs_result_error_write='error', bs_result_value_write='value',
                  bs_key_state_private='state', bs_setup_state_private='state', bs_key_forge='state', bs_setup_forge='state')
PRIVATE.update(BS_PRIVATE)
PRIVATE.update(quic_io_endpoint_forge='opened', quic_io_dispatcher_private='descriptors')
PRIVATE.update(quic_length_payload='completed', quic_length_tag='status', quic_frame_payload='payloadSize', quic_frame_extent='completedExtent', quic_frame_tag='status', quic_frame_error_write='error', quic_frame_size_write='size', quic_length_value_write='value', quic_frame_forge='status')
NOMINAL.update(bs_key_as_setup='[1] expected: BsSetup but got: BsKey',
               bs_signature_as_ring_proof='got: BsSignature but wanted: BsRingProof',
               bs_output_as_public='got: BsOutput but wanted: BsPublicKey')
PRIVATE.update(integration_key_payload='completed', integration_capture_payload='completed', integration_child_payload='completed', integration_count_payload='completed', integration_bytes_payload='completed', integration_status='status', integration_retag='status', integration_error_write='error', integration_value_write='value', integration_forge='status', integration_verified_private='data', integration_verified_rebind='data', integration_verified_forge='data', integration_bank_private='data', integration_bank_rebind='data', integration_bank_forge='data', integration_verified_wire='wire', integration_bank_wires='wires')
PRIVATE.update(offload_poll_tag_private='hasCompletion', offload_poll_payload_private='completed',
               offload_poll_retag='ready', offload_poll_forge='hasCompletion', offload_poll_write='completion')
PRIVATE.update(session_peer_private='Peer', session_stream_private='StreamState',
               session_frame_private='frameExtent', session_callback_private='verifyPeer')
INTEGRATION_MEMBERS = ('key', 'capture', 'child', 'length', 'copy', 'fixture-key', 'fixture-bytes')
BS_MEMBERS = ('key-short', 'key-zero', 'key-backend', 'setup-bounds', 'setup-backend',
              'public-owner', 'public-short', 'signature-short', 'signature-owner', 'root-short',
              'root-owner', 'proof-short', 'proof-owner', 'output-invalid', 'ring-output-owner', 'normalize-short')
PRIMITIVE_MEMBERS = ('natural-value', 'natural-consumed', 'fixed-value', 'fixed-consumed', 'fixed-encoded')
NOMINAL.update(entropy_word_as_input='StateEntropyWord')
EARLY_NOMINAL.update(entropy_word_as_input=('advanceEntropyTime(', '[4] expected: EntropyInput but got: StateEntropyWord'))
NOMINAL.update(authorization_core_as_slot='AuthorizationCoreIndex', history_accumulation_as_parent='AccumulationRoot')
EARLY_NOMINAL.update(history_accumulation_as_parent=('correctHistoryParent(', '[2] expected: HistoryStateRoot but got: AccumulationRoot'))
EARLY_NOMINAL.update(authorization_core_as_slot=('advanceAuthorization(', '[4] expected: AuthorizationSlot but got: AuthorizationCoreIndex'))
PRIMITIVE_ERRORS = ('natural-error', 'fixed-decode-error', 'fixed-encode-error')
OWNED_MEMBERS = ('frame', 'info', 'optional', 'work', 'digest', 'service', 'integer', 'boolean')
COMPOSITE_MEMBERS = ('optional-value', 'optional-consumed', 'work-value', 'work-consumed',
                     'preimages-count', 'preimages-consumed', 'written', 'digest-value', 'digest-consumed')
MEMBERS = ('offset', 'length', 'blob-consumed', 'written', 'count', 'sequence-consumed')


# Each selected workload owns its workspace; other jobs use independent native-check instances.
checks = NativeChecks(BUILD)
command, build = checks.command, checks.build


# Fixed inventories retain every historical diagnostic family when jobs execute independently.
FAILURE_COUNTS = {
    'safrole_markers': 2,
    'sealer_schedule': 2,
    'sealer_state': 2,
    'ticket_state': 2,
    'ticket_admission': 2,
    'validator_state': 2,
    'validator_rotation': 2,
    'entropy_transition': 4,
    'history_transition': 6,
    'authorization_transition': 4,
    'store': 9,
    'runtime': 3,
    'bounded': 12,
    'primitive': 13,
    'composite': 29,
    'owned': 27,
    'bandersnatch': 2 * len(BS_MEMBERS),
    'offload': 4,
    'integration': 2 * len(INTEGRATION_MEMBERS),
    'quic_protocol': 8,
    'guarantee_message': 2 * len(GUARANTEE_MESSAGE_MEMBERS),
    'assurance_context': 2 * len(ASSURANCE_CONTEXT_MEMBERS),
    'composition': 2 * len(COMPOSITION_MEMBERS),
    'requests': 2 * len(REQUESTS_MEMBERS) + 2 * len(REQUESTS_FIELDS) + 6,
    'service_values': 2 * len(SERVICE_VALUES_MEMBERS),
    'accounts': 2 * len(ACCOUNTS_MEMBERS),
    'outputs': 2 * len(OUTPUTS_MEMBERS),
    'workqueues': 2 * len(WORKQUEUES_MEMBERS),
    'statistics': 2 * len(STATISTICS_MEMBERS),
    'privileges': 2 * len(PRIVILEGES_MEMBERS),
    'availability': 2 * len(AVAILABILITY_MEMBERS) + 6,
    'history': 2 * len(HISTORY_MEMBERS) + 3,
    'state_disputes': 2 * len(STATE_DISPUTES_MEMBERS),
    'consensus': 2 * len(CONSENSUS_MEMBERS) + 2,
    'authorization': 2 * len(AUTHORIZATION_MEMBERS),
    'safrole': 2 * len(SAFROLE_MEMBERS) + 1,
    'trie': 3 * len(TRIE_ORIGINS) + 2,
    'layout': 2 * len(LAYOUT_MEMBERS) + len(LAYOUT_VARIANTS),
    'crypto': 2 * len(CRYPTO_MEMBERS),
    'c2': 2 * len(C2_MEMBERS) + len(C2_VARIANTS),
    'collections': 2 * len(COLLECTION_MEMBERS),
    'bits': 2 * len(BITS_MEMBERS),
    'blocks': 2 * len(BLOCK_MEMBERS) + 3 + len(BLOCK_WRONG),
    'headers': 81,
    'packages': 51,
    'disputes': 25,
    'tickets': 10,
    'guarantees': 29,
    'assurances': 10,
    'reports': 14,
}
CORPUS_NAMES = ('accounts_corpus', 'assurance_context_corpus', 'assurance_corpus', 'authorization_corpus', 'availability_corpus', 'bandersnatch_corpus', 'bits_corpus', 'block_corpus', 'bounded_corpus', 'c2_corpus', 'collection_corpus', 'composite_corpus', 'composition_corpus', 'consensus_corpus', 'crypto_corpus', 'digest_corpus', 'dispute_corpus', 'fixed_corpus', 'guarantee_corpus', 'header_corpus', 'history_corpus', 'integration_corpus', 'layout_corpus', 'natural_corpus', 'outputs_corpus', 'package_corpus', 'privileges_corpus', 'quic_protocol_corpus', 'report_corpus', 'report_signature_corpus', 'request_namespace_corpus', 'requests_corpus', 'safrole_corpus', 'service_values_corpus', 'state_disputes_corpus', 'state_roots_corpus', 'state_widths_corpus', 'statistics_corpus', 'ticket_corpus', 'trie_corpus', 'workqueues_corpus')


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
        source.write_text('\n'.join(lines)+'\n')
        compiled, binary = build(compiler, ROOT/f'tests/native/{adapter}.nim', 'early-'+family)
        corpus = dict(build=compiled, requests=len(lines), passed=False,
                      published_checks=anchors[0],
                      requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                      expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
        if compiled['exit_code'] == 0:
            # Compare complete byte/field/error observations; adapters retain atomicity and owned-copy assertions.
            result = command([binary, source], 'early-'+family+'-corpus')
            output = result.pop('output')
            actual = output.splitlines()
            corpus['run'] = result
            corpus['passed'] = result['exit_code'] == 0 and actual == expected
            corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
            if not corpus['passed']:
                # Include missing/extra responses as mismatches; never accept a matching partial prefix.
                corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
        report[family+'_corpus'] = corpus
        announce('unchanged independent '+family+' corpus', corpus['passed'])
    # The full report driver retains the unchanged codec batch and exposes credential composition separately.
    sys.path.insert(0, str(ROOT/'tests'))
    from report_oracle import requests
    lines, expected = requests()
    source = BUILD/'report-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/report_driver.nim', 'report-codec', crypto_library)
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
    # Preserve the complete independently signed assurance-context corpus and frozen source/expected identities.
    from assurance_crypto_oracle import requests as assurance_context_requests
    provider, lines, expected = assurance_context_requests()
    source = BUILD/'assurance-context-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/assurance_crypto_driver.nim', 'assurance-context-codec', crypto_library)
    corpus = dict(build=compiled, provider=provider, requests=len(lines), passed=False,
                  scope='fixed transcript and stateless validator-key/parent checks; no state eligibility or point-policy change',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    if compiled['exit_code'] == 0:
        # Ordinary OpenSSL signatures and hashlib transcripts precede native execution; compare every complete result.
        result = command([binary, source], 'assurance-context-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected and len(lines) == 2087
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        if not corpus['passed']:
            # Include missing/extra observations and retain the full output for exact replay.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['assurance_context_corpus'] = corpus
    announce('independent assurance transcript/context/signature corpus', corpus['passed'])
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
    lines, expected = block_requests()
    source = BUILD/'block-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {operation+'-'+kind: sum(line.startswith(operation+' '+kind+' ') for line in lines)
              for operation in ('D', 'E') for kind in ('E', 'B')}
    compiled, binary = build(compiler, ROOT/'tests/native/block_driver.nim', 'block-codec')
    corpus = dict(build=compiled, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare all six exact child wires/counts after source erasure and on-demand materialization.
        result = command([binary, source], 'block-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first mismatch plus complete native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['block_corpus'] = corpus
    announce('independent complete extrinsic/block corpus', corpus['passed'])
    # Preserve all exhaustive Boolean/padding cases and pinned profile-field checks from the independent oracle.
    from bits_oracle import requests as bits_requests
    lines, expected = bits_requests()
    source = BUILD/'bits-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {operation: sum(line.startswith(operation+' ') for line in lines)
              for operation in ('BD', 'BE', 'D', 'E')}
    compiled, binary = build(compiler, ROOT/'tests/native/bits_driver.nim', 'bits-codec')
    corpus = dict(build=compiled, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every logical bit/count/extent after input erasure and compare both owner framing forms.
        result = command([binary, source], 'bits-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first differing row and all native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['bits_corpus'] = corpus
    announce('independent Boolean/fixed/variable bitstring corpus', corpus['passed'])
    # Preserve the unchanged collection oracle: numeric/byte ordering, pairing and zero-width singleton domains.
    from collections_oracle import requests as collection_requests
    lines, expected = collection_requests()
    source = BUILD/'collection-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {kind: sum(line.split()[1] == kind for line in lines) for kind in ('F', 'S', 'M')}
    assert sum(groups.values()) == len(lines), groups
    compiled, binary = build(compiler, ROOT/'tests/native/collections_driver.nim', 'collection-codec')
    corpus = dict(build=compiled, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare copied logical fields, canonical wire, consumed progress and typed reasons after input erasure.
        result = command([binary, source], 'collection-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first mismatch and complete native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['collection_corpus'] = corpus
    announce('independent canonical fixed/variable set/dictionary corpus', corpus['passed'])
    # Independent C.2 references retain exact availability/transfer/operand framing and tagged-union agreement.
    from c2_oracle import requests as c2_requests
    lines, expected = c2_requests()
    source = BUILD/'c2-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {}
    # Classify actual request names rather than guessing adapter tags; every request must be included.
    for line in lines:
        parts = line.split()
        key = parts[0]+'-'+parts[1]
        groups[key] = groups.get(key, 0)+1
    assert sum(groups.values()) == len(lines), groups
    compiled, binary = build(compiler, ROOT/'tests/native/c2_driver.nim', 'c2-codec')
    corpus = dict(build=compiled, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every fixed field, payload/trace copy and exact owned wire after destructive caller mutation.
        result = command([binary, source], 'c2-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first mismatch and all adapter output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['c2_corpus'] = corpus
    announce('independent availability/transfer/operand/accumulation corpus', corpus['passed'])
    # Preserve the independent C/B/L equations, every hostile header/padding request and labelled historical projections.
    from state_layout_oracle import requests as layout_requests, legacy_singletons
    lines, expected = layout_requests()
    source = BUILD/'layout-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_layout_driver.nim', 'layout-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  historical_projected_singletons=len(legacy_singletons()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # The reference computes keys/fields/padding/hash bytes independently before native execution.
        result = command([binary, source], 'layout-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first differing row and complete adapter output for diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['layout_corpus'] = corpus
    announce('independent state-key/node layout and hash corpus', corpus['passed'])
    # Compare independent unsorted-list partitions, every key divergence bit and labelled historical projections.
    from state_trie_oracle import requests as trie_requests, legacy_maps
    lines, expected = trie_requests()
    source = BUILD/'trie-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_trie_driver.nim', 'trie-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  historical_projected_maps=len(legacy_maps()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Every result compares exact root/counts or a typed reason; caller preservation is checked by the adapter.
        result = command([binary, source], 'trie-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain complete native output and the first mismatch for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['trie_corpus'] = corpus
    announce('independent bounded state trie root corpus', corpus['passed'])
    # Preserve independent entropy/time/roster bytes, malformed inputs, published derived fixtures and partial roots.
    from state_safrole_oracle import requests as safrole_requests, published as safrole_published
    lines, expected = safrole_requests()
    source = BUILD/'safrole-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_safrole_driver.nim', 'safrole-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(safrole_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Native fields/consumed counts and roots are compared only with independently authored expectations.
        result = command([binary, source], 'safrole-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first mismatch and complete native output for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['safrole_corpus'] = corpus
    announce('independent entropy/validator-roster/timeslot state corpus', corpus['passed'])
    # Preserve independent ordered core/row equations, malformed inputs, derived fixtures and partial commitments.
    from state_authorization_oracle import requests as authorization_requests, published as authorization_published
    lines, expected = authorization_requests()
    source = BUILD/'authorization-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_authorization_driver.nim', 'authorization-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(authorization_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe fixed hashes and owner-bound boundaries after destructive caller mutation, comparing independent bytes.
        result = command([binary, source], 'authorization-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain complete output and the first mismatch for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['authorization_corpus'] = corpus
    announce('independent authorization pool/queue state corpus', corpus['passed'])
    # Preserve independent chapter-4 byte/field equations, derived fixtures and partial single-entry roots.
    from state_consensus_oracle import requests as consensus_requests, published as consensus_published
    lines, expected = consensus_requests()
    source = BUILD/'consensus-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_consensus_driver.nim', 'consensus-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(consensus_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'consensus-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['consensus_corpus'] = corpus
    announce('independent chapter-4 Safrole basic state corpus', corpus['passed'])
    # Preserve independent chapter-5 byte/field equations, derived fixtures and partial single-entry roots.
    from state_disputes_oracle import requests as state_disputes_requests, published as state_disputes_published
    lines, expected = state_disputes_requests()
    source = BUILD/'state_disputes-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_disputes_driver.nim', 'state_disputes-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(state_disputes_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_disputes-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['state_disputes_corpus'] = corpus
    announce('independent chapter-5 dispute judgment/offender state corpus', corpus['passed'])
    # Preserve independent chapter-3 byte/field equations, derived fixtures and partial single-entry roots.
    from state_history_oracle import requests as state_history_requests, published as state_history_published
    lines, expected = state_history_requests()
    source = BUILD/'state_history-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_history_driver.nim', 'state_history-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(state_history_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_history-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['history_corpus'] = corpus
    announce('independent chapter-3 recent history state corpus', corpus['passed'])
    # Preserve independent chapter-10 byte/field equations, derived fixtures and partial single-entry roots.
    from state_availability_oracle import requests as state_availability_requests, published as state_availability_published, published_verdicts as availability_verdicts
    lines, expected = state_availability_requests()
    source = BUILD/'state_availability-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_availability_driver.nim', 'state_availability-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(state_availability_published()), published_decode_verdicts=availability_verdicts(),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_availability-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['availability_corpus'] = corpus
    announce('independent chapter-10 availability assignment state corpus', corpus['passed'])
    # Preserve independent chapter-12 byte/field equations, derived fixtures and partial single-entry roots.
    from state_privileges_oracle import requests as state_privileges_requests, published as state_privileges_published
    lines, expected = state_privileges_requests()
    source = BUILD/'state_privileges-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_privileges_driver.nim', 'state_privileges-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_derived_state_sources=len(state_privileges_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_privileges-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['privileges_corpus'] = corpus
    announce('independent chapter-12 privileged service state corpus', corpus['passed'])
    # Preserve independent chapter-13 byte/field equations, derived fixtures and partial single-entry roots.
    from state_statistics_oracle import requests as state_statistics_requests, published_validators as state_statistics_published, trace_evidence as statistics_traces
    lines, expected = state_statistics_requests()
    source = BUILD/'state_statistics-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_statistics_driver.nim', 'state_statistics-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_partial_validator_sources=len(state_statistics_published()), published_trace_components=statistics_traces(),
                  gas_encoding_policy="accepted canonical compact naturals; no fallback",
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_statistics-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(corpus['published_trace_components']) == 6 and all(row['complete_component_match'] for row in corpus['published_trace_components'])
    report['statistics_corpus'] = corpus
    announce('independent chapter-13 activity statistics state corpus', corpus['passed'])
    # Chapters 14/15 retain independent literal, derived JSON and exact raw trace evidence.
    from state_workqueues_oracle import requests as workqueue_requests, published as workqueue_published, published_traces as workqueue_traces, parse as workqueue_parse, wire as workqueue_wire
    lines, expected = workqueue_requests()
    source = BUILD/'workqueues-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    traces = []
    # Whole-component trace replay is separate from sorted JSON-derived mathematical sets.
    for kind, data, config in workqueue_traces():
        rows, consumed, items, dependencies = workqueue_parse(kind, data, config)
        traces.append(dict(kind=kind, bytes=len(data), consumed=consumed, items=items,
                           dependencies=dependencies, sha256=hashlib.sha256(data).hexdigest(),
                           complete_component_match=consumed == len(data) and workqueue_wire(kind, rows) == data))
    compiled, binary = build(compiler, ROOT/'tests/native/state_workqueues_driver.nim', 'state_workqueues-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_json_components=len(workqueue_published()), published_trace_components=traces,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Expected observations come from the independent reference, never a native round trip.
        result = command([binary, source], 'state_workqueues-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first disagreement and complete log for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(traces) == 12 and all(row['complete_component_match'] for row in traces)
    report['workqueues_corpus'] = corpus
    announce('independent chapters 14/15 ready/accumulated queue corpus', corpus['passed'])
    # Chapter 16 preserves the independent ordered fixed-pair corpus and exact empty published traces.
    from state_outputs_oracle import requests as outputs_requests, published as outputs_published, parse as outputs_parse, wire as outputs_wire, DEFAULT as outputs_default
    lines, expected = outputs_requests()
    source = BUILD/'outputs-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    traces = []
    # Selected trace entries are empty logs; authored cases supply nonempty field/order coverage.
    for entry in outputs_published():
        values, consumed = outputs_parse(entry['wire'], outputs_default)
        traces.append(dict(path=entry['path'], phase=entry['phase'], bytes=len(entry['wire']),
                           items=len(values), consumed=consumed, sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=consumed == len(entry['wire']) and outputs_wire(values) == entry['wire']))
    compiled, binary = build(compiler, ROOT/'tests/native/state_outputs_driver.nim', 'state_outputs-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_trace_components=traces,
                  scope='ordered fixed pairs; published traces empty, nonempty coverage authored; no accumulation execution',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # All expected fields/bytes/reasons come from independent equations computed before native execution.
        result = command([binary, source], 'state_outputs-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first disagreement and full observation log for reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(traces) == 8 and all(row['complete_component_match'] for row in traces)
    report['outputs_corpus'] = corpus
    announce('independent chapter-16 last accumulation outputs corpus', corpus['passed'])
    # Fixed account metadata retains independent field equations, JSON records and exact nonempty raw traces.
    from state_accounts_oracle import requests as accounts_requests, published_json as accounts_json, published_traces as accounts_traces, parse as accounts_parse, wire as accounts_wire, key as accounts_key, MAX as accounts_max, SIZE as accounts_size
    lines, expected = accounts_requests()
    source = BUILD/'accounts-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    traces = []
    # Select exact reconstructable C(255, service) keys, never arbitrary hashed keys sharing the first byte.
    for entry in accounts_traces():
        fields = accounts_parse(entry['wire'], accounts_max)
        traces.append(dict(path=entry['path'], phase=entry['phase'], service=entry['service'],
                           key=accounts_key(entry['service']).hex(), bytes=len(entry['wire']), consumed=accounts_size,
                           sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=len(entry['wire']) == accounts_size and accounts_wire(fields) == entry['wire']))
    compiled, binary = build(compiler, ROOT/'tests/native/state_accounts_driver.nim', 'state_accounts-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_json_metadata=len(accounts_json()), published_trace_metadata=traces,
                  scope='C(255,service) fixed version-zero metadata; no nested maps, account validation or transitions',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Independent expected fields/bytes/reasons precede execution; native round trips supply no expected answers.
        result = command([binary, source], 'state_accounts-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first mismatch and full observation log for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(traces) == 20 and all(row['complete_component_match'] for row in traces)
    report['accounts_corpus'] = corpus
    announce('independent C(255,service) account metadata corpus', corpus['passed'])
    # Storage/preimage constructors use independent hash equations; raw trace capture remains explicitly unclassified.
    from state_service_values_oracle import requests as service_values_requests, published as service_values_published, published_traces as service_values_traces
    lines, expected = service_values_requests()
    source = BUILD/'service-values-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    sources = service_values_published()
    traces = [dict(path=entry['path'], phase=entry['phase'], service=entry['service'], key=entry['key'].hex(),
                   bytes=len(entry['value']), sha256=hashlib.sha256(entry['value']).hexdigest(),
                   namespace='opaque; not recoverable from key') for entry in service_values_traces()]
    compiled, binary = build(compiler, ROOT/'tests/native/state_service_values_driver.nim', 'state_service_values-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_json_storage=sum(row[0] == 'S' for row in sources),
                  published_json_preimages=sum(row[0] == 'P' for row in sources),
                  published_opaque_trace_values=traces,
                  scope='keyed storage/preimage serialization and opaque capture; no namespace recovery, hash/content invariant or transitions',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Native observations expose retained fields after caller mutation; expected answers precede execution.
        result = command([binary, source], 'state_service_values-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first disagreement and full observation log for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(traces) == 16 and corpus['published_json_storage'] == 12 and corpus['published_json_preimages'] == 16
    report['service_values_corpus'] = corpus
    announce('independent service storage/preimage keys and opaque raw-value corpus', corpus['passed'])
    # Request histories preserve the full E4 domain and the maintainer-parked namespace question.
    from state_requests_oracle import requests as requests_requests, published as requests_published, published_traces as requests_traces, parse as requests_parse, wire as requests_wire
    lines, expected = requests_requests()
    source = BUILD/'requests-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    published = requests_published()
    traces = []
    # Identities come from exact content/preimage/request relationships in one state, never guessed hashed namespaces.
    for entry in requests_traces():
        slots, consumed = requests_parse(entry['wire'], (3, 13))
        traces.append(dict(path=entry['path'], phase=entry['phase'], service=entry['service'], length=entry['length'],
                           key=entry['key'].hex(), bytes=len(entry['wire']), count=len(slots), consumed=consumed,
                           sha256=hashlib.sha256(entry['wire']).hexdigest(),
                           complete_component_match=consumed == len(entry['wire']) and requests_wire(slots) == entry['wire']))
    compiled, binary = build(compiler, ROOT/'tests/native/state_requests_driver.nim', 'state_requests-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_json_histories=len(published),
                  published_json_shapes={str(n): sum(len(row[3]) == n for row in published) for n in range(4)},
                  published_trace_histories=traces,
                  namespace_overlap=dict(status='parked_by_maintainer_until_graypaper_0.8.1_or_0.8.2', lengths=[2**32-2, 2**32-1],
                    observation='full stated domain preserved; overlapping keys reject at trie composition; no restriction inferred'),
                  scope='request key/history framing only; no chronology, availability or lifecycle transitions',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Independent expected fields/bytes/reasons precede execution; source and input mutation cannot change observations.
        result = command([binary, source], 'state_requests-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first mismatch and complete native observation log for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    corpus['passed'] = corpus['passed'] and len(traces) == 20 and all(row['complete_component_match'] for row in traces)
    report['requests_corpus'] = corpus
    announce('independent service request-history key/shape corpus', corpus['passed'])
    # Exact chapter/service composition compares every mapping byte as well as root and topology counts.
    from state_composition_oracle import requests as composition_requests
    lines, expected, components, whole = composition_requests()
    source = BUILD/'composition-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_composition_driver.nim', 'state_composition-codec', crypto_library)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  published_component_observations=components, published_composed_states=whole,
                  published_exact_captures=sum(row['verdict'] == 'ok' for row in components),
                  scope='exact typed chapter capture and complete mappings; opaque service values explicit; no transitions',
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Expected complete mappings and roots precede execution; embedded ownership/association selftests also run.
        result = command([binary, source], 'state_composition-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first disagreement and complete native observations for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
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
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/quic_protocol_driver.nim', 'quic-protocol-driver', quic_library=quic_library)
    corpus = dict(build=compiled, requests=len(lines), groups=groups, passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest(),
                  scope='pinned SAN/DER identity and structural CE framing; no TLS handshake or fixture eligibility claim')
    if compiled['exit_code'] == 0:
        # Keep exact status/identity/length/extent observations; incomplete results expose no payload metadata.
        result = command([binary, source], 'quic-protocol-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        if not corpus['passed']:
            # Missing, extra or differing rows remain reproducible against the retained public request file.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['quic_protocol_corpus'] = corpus
    announce('independent SAN/DER/frame boundary corpus', corpus['passed'])
    # Compose independently parsed full C.2 wires and hashlib keys through the enabled production ABI.
    from integration_oracle import requests as integration_requests
    lines, expected = integration_requests(integration_wires)
    source = BUILD/'integration-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/integration_driver.nim', 'integration-driver', crypto_library, defines=('integration',))
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest(),
                  scope='CE fixture codec/crypto composition; no authenticated transport or normative digest/preimage relationship')
    if compiled['exit_code'] == 0:
        # Compare complete serialized bytes and failure ordering, not only a self-generated round trip.
        result = command([binary, source], 'integration-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['passed'] = result['exit_code'] == 0 and actual == expected
        if not corpus['passed']:
            # Retain the exact first mismatching observation and adjacent public request log for diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
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
            result = command([binary, member, origin], 'store-'+member+'-'+origin)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['store'].append(dict(member=member, origin=origin, passed=passed, run=result))
            announce('store '+member+' '+origin+' runtime guard', passed)
        controls = {member: command([binary, member, 'valid'], 'store-'+member+'-valid')
                    for member in ('metadata', 'length', 'bytes')}
        report['store_controls'] = dict(checks=controls,
            passed=all(row['exit_code'] == 0 and row['output'].strip() == ('1' if member == 'metadata' else '0')
                       for member, row in controls.items()))
    # Proposed entry and committed-snapshot payloads are independently guarded on default and real failures.
    compiled, binary = build(compiler, ROOT/'tests/native/authorization_transition_results.nim', 'authorization-transition-results', crypto_library)
    report['authorization_transition_build'] = compiled
    if compiled['exit_code'] == 0:
        for member in ('entry', 'state'):
            for origin in ('default', 'error'):
                # Require the intended payload precondition, not a bad selector or unrelated native crash.
                result = command([binary, member, origin], 'authorization-transition-'+member+'-'+origin)
                passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['authorization_transition'].append(dict(member=member, origin=origin, passed=passed, run=result))
                announce('authorization transition '+member+' '+origin+' runtime guard', passed)
    # Root, proposed entry and committed snapshot payload families require independent checked guards.
    compiled, binary = build(compiler, ROOT/'tests/native/history_transition_results.nim', 'history-transition-results', crypto_library)
    report['history_transition_build'] = compiled
    if compiled['exit_code'] == 0:
        for member in ('root', 'entry', 'state'):
            for origin in ('default', 'error'):
                # Require the intended precondition and status, not an unrelated crash or selector error.
                result = command([binary, member, origin], 'history-transition-'+member+'-'+origin)
                passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['history_transition'].append(dict(member=member, origin=origin, passed=passed, run=result))
                announce('history transition '+member+' '+origin+' runtime guard', passed)
    # Updated fixed words/time and committed snapshots each require default and actual failure guards.
    compiled, binary = build(compiler, ROOT/'tests/native/entropy_transition_results.nim', 'entropy-transition-results', crypto_library)
    report['entropy_transition_build'] = compiled
    if compiled['exit_code'] == 0:
        for member in ('update', 'state'):
            for origin in ('default', 'error'):
                # Require the exact result-access precondition, not an unrelated crash or harness selector failure.
                result = command([binary, member, origin], 'entropy-transition-'+member+'-'+origin)
                passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['entropy_transition'].append(dict(member=member, origin=origin, passed=passed, run=result))
                announce('entropy transition '+member+' '+origin+' runtime guard', passed)
    # Both default and actual failed plans reject payload extraction through the intended checked contract.
    compiled, binary = build(compiler, ROOT/'tests/native/validator_rotation_results.nim', 'validator-rotation-results', crypto_library)
    report['validator_rotation_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # A selector failure, unrelated assertion or native crash cannot stand in for payload protection.
            result = command([binary, origin], 'validator-rotation-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['validator_rotation'].append(dict(origin=origin, passed=passed, run=result))
            announce('validator rotation '+origin+' runtime guard', passed)
    # Isolate default and actual failed publication results; require the intended access contract.
    compiled, binary = build(compiler, ROOT/'tests/native/validator_state_results.nim', 'validator-state-results',
                             crypto_library, native_libraries=(bs_library,))
    report['validator_state_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # No unrelated crash or selector error can satisfy snapshot payload protection.
            result = command([binary, origin], 'validator-state-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['validator_state'].append(dict(origin=origin, passed=passed, run=result))
            announce('validator state '+origin+' runtime guard', passed)
    # Default and real failed admission candidates reject owner extraction through the intended contract.
    compiled, binary = build(compiler, ROOT/'tests/native/ticket_admission_results.nim', 'ticket-admission-results',
                             crypto_library, native_libraries=(bs_library,))
    report['ticket_admission_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # Selector failures and unrelated assertions cannot stand in for guarded candidate access.
            result = command([binary, origin], 'ticket-admission-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['ticket_admission'].append(dict(origin=origin, passed=passed, run=result))
            announce('ticket admission '+origin+' runtime guard', passed)
    # Publication snapshots require successful selection for both default and actually refused results.
    compiled, binary = build(compiler, ROOT/'tests/native/ticket_state_results.nim', 'ticket-state-results',
                             crypto_library, native_libraries=(bs_library,))
    report['ticket_state_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # Require the intended snapshot extraction precondition rather than an unrelated failure.
            result = command([binary, origin], 'ticket-state-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['ticket_state'].append(dict(origin=origin, passed=passed, run=result))
            announce('ticket state '+origin+' runtime guard', passed)
    # Default and actually refused schedule results must not expose candidate payloads.
    compiled, binary = build(compiler, ROOT/'tests/native/sealer_schedule_results.nim', 'sealer-schedule-results', crypto_library)
    report['sealer_schedule_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # Require the supported extraction contract, not a selector failure or unrelated crash.
            result = command([binary, origin], 'sealer-schedule-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['sealer_schedule'].append(dict(origin=origin, passed=passed, run=result))
            announce('sealer schedule '+origin+' runtime guard', passed)
    # Default and actually refused schedule results must not expose candidate payloads.
    compiled, binary = build(compiler, ROOT/'tests/native/sealer_state_results.nim', 'sealer-state-results', crypto_library)
    report['sealer_state_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # Require the supported extraction contract, not a selector failure or unrelated crash.
            result = command([binary, origin], 'sealer-state-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['sealer_state'].append(dict(origin=origin, passed=passed, run=result))
            announce('sealer state '+origin+' runtime guard', passed)
    # Default and actually refused schedule results must not expose candidate payloads.
    compiled, binary = build(compiler, ROOT/'tests/native/safrole_markers_results.nim', 'safrole-markers-results', crypto_library)
    report['safrole_markers_build'] = compiled
    if compiled['exit_code'] == 0:
        for origin in ('default', 'error'):
            # Require the supported extraction contract, not a selector failure or unrelated crash.
            result = command([binary, origin], 'safrole-markers-'+origin)
            passed = result['exit_code'] == 1 and 'outcome.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['safrole_markers'].append(dict(origin=origin, passed=passed, run=result))
            announce('Safrole markers '+origin+' runtime guard', passed)
    # Transcript and count access on every actual/default context failure must terminate at the success contract.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_assurance_context_results.nim', 'assurance-context-results', crypto_observer)
    report['assurance_context_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate every read so an earlier contract failure cannot conceal a later unguarded payload.
        for origin in ('default', 'error'):
            for member in ASSURANCE_CONTEXT_MEMBERS:
                result = command([binary, member, origin], 'assurance-context-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['assurance_context'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' assurance context '+member+' runtime guard', passed)
    # Failed/default guarantee signing messages cannot expose an all-zero or partial domain/hash payload.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_guarantee_message_results.nim', 'guarantee-message-results', crypto_observer)
    report['guarantee_message_build'] = compiled
    if compiled['exit_code'] == 0:
        # Empty/nonempty raw inputs are isolated, and each default is separate from the actual provider refusal.
        for origin in ('default', 'error'):
            for member in GUARANTEE_MESSAGE_MEMBERS:
                result = command([binary, member, origin], 'guarantee-message-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['guarantee_message'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' guarantee message '+member+' runtime guard', passed)
    # Actual/default result access must reject for every fixed proof/output, sequence and opaque native owner.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_bandersnatch_results.nim', 'bandersnatch-results',
                             native_libraries=bs_libraries, cflags=OWNER_DEFINES)
    report['bandersnatch_build'] = compiled
    if compiled['exit_code'] == 0:
        # Separate processes prevent prior contract failures or test-observer flags from concealing later checks.
        for origin in ('default', 'error'):
            for member in BS_MEMBERS:
                result = command([binary, member, origin], 'bs-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['bandersnatch'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' Bandersnatch '+member+' runtime guard', passed)
    # Default/failed/pending frame metadata and default/failed E4 lengths cannot bypass result access contracts.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_quic_protocol_results.nim', 'quic-protocol-results', quic_library=quic_library)
    report['quic_protocol_build'] = compiled
    if compiled['exit_code'] == 0:
        # One rejected read per child process prevents a preceding contract trap from hiding another accessor.
        for member in ('length', 'size', 'extent'):
            for origin in (('default', 'error') if member == 'length' else ('default', 'error', 'pending')):
                result = command([binary, member, origin], 'quic-protocol-'+member+'-'+origin)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['quic_protocol'].append(dict(member=member, origin=origin, passed=passed, run=result))
                announce('QUIC '+origin+' '+member+' runtime guard', passed)
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
                result = command([binary, origin], 'offload-result-'+str(enabled)+'-'+origin, environment)
                passed = result['exit_code'] == 1 and 'value.hasCompletion' in result['output'] and '[AssertionDefect]' in result['output']
                report['offload'].append(dict(enabled=enabled, origin=origin, passed=passed, run=result))
                announce('offload '+str(enabled)+' '+origin+' completion runtime guard', passed)
    # Every default/actual integration result family must reject value access before use.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_integration_results.nim', 'integration-results', crypto_observer, defines=('integration',))
    report['integration_build'] = compiled
    if compiled['exit_code'] == 0:
        for member in INTEGRATION_MEMBERS:
            # Child processes isolate failure reads across keys, snapshots, codec owners, counts and copied bytes.
            for origin in ('default', 'error'):
                result = command([binary, member, origin], 'integration-'+member+'-'+origin)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['integration'].append(dict(member=member, origin=origin, passed=passed, run=result))
                announce('integration '+origin+' '+member+' runtime guard', passed)
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
                announce(origin+' '+member+' runtime guard', passed)
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
            announce(origin+' '+member+' runtime guard', passed)
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
            announce(origin+' '+member+' runtime guard', passed)
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
            announce(origin+' '+member+' runtime guard', passed)
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
                announce(origin+' '+member+' runtime guard', passed)
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
                announce(origin+' assurance '+member+' runtime guard', passed)
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
            announce(origin+' guarantee '+member+' runtime guard', passed)
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
                announce(origin+' ticket '+member+' runtime guard', passed)
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
            announce(origin+' dispute '+member+' runtime guard', passed)
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
            announce(origin+' package '+member+' runtime guard', passed)
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
            announce(origin+' header '+member+' runtime guard', passed)
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
            announce(origin+' block '+member+' runtime guard', passed)
    # All Boolean/bitstring result types and public operations retain success-only value access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_bits_results.nim', 'bits-results')
    report['bits_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual rejection and default construction must independently stop at the success contract.
        for origin in ('default', 'error'):
            # Isolate each field/operation so one failed access cannot conceal another unchecked result.
            for member in BITS_MEMBERS:
                result = command([binary, member, origin], 'bits-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['bits'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' bits '+member+' runtime guard', passed)
    # Every collection/scalar result shape keeps failure/default application access guarded.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_collection_results.nim', 'collection-results')
    report['collections_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate all application reads and both unsupported direct scalar width contracts.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in COLLECTION_MEMBERS]
        for member, origin, sentinel in cases:
            result = command([binary, member, origin], 'collection-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['collections'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' collection '+member+' runtime guard', passed)
    # Guard every C.2 result and selected work/source/metadata/decoded union alternative independently.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_c2_results.nim', 'c2-results')
    report['c2_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and every work-error alternative run in separate optimized processes.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in C2_MEMBERS]
        cases += list(C2_VARIANTS)
        for member, origin, sentinel in cases:
            result = command([binary, member, origin], 'c2-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['c2'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' c2 '+member+' runtime guard', passed)
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_crypto_results.nim', 'crypto-results', crypto_observer)
    report['crypto_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every default and real operation failure runs in a separate checked process.
        for origin in ('default', 'error'):
            for member in CRYPTO_MEMBERS:
                # Distinguish the success contract from a crash, missing library or unrelated assertion.
                result = command([binary, member, origin], 'crypto-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['crypto'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' crypto '+member+' runtime guard', passed)
    # Guard every default/failed layout result and both wrong alternatives for every metadata field.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_layout_results.nim', 'layout-results', crypto_observer)
    report['layout_build'] = compiled
    if compiled['exit_code'] == 0:
        # Backend refusals use the separate test-only observer while normal corpus requests use production hashing.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in LAYOUT_MEMBERS]
        cases += LAYOUT_VARIANTS
        for member, origin, sentinel in cases:
            # Require the exact result/field contract, never a crash or missing library.
            result = command([binary, member, origin], 'layout-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['layout'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' layout '+member+' runtime guard', passed)
    # Public commitment and private recursive child-hash results must reject failed/default payload reads.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_trie_results.nim', 'trie-results', crypto_observer)
    report['trie_build'] = compiled
    if compiled['exit_code'] == 0:
        # Independent processes expose no fabricated root, entry count, node count or child hash.
        cases = [(member, origin) for origin in TRIE_ORIGINS for member in ('root', 'entries', 'nodes')]
        cases += [('child-hash', origin) for origin in ('default', 'error')]
        for member, origin in cases:
            # Require the exact success contract rather than an unrelated process failure.
            result = command([binary, member, origin], 'trie-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['trie'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' trie '+member+' runtime guard', passed)
    # Every default/failed component result must reject values, owners, copied records and consumed progress.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_safrole_results.nim', 'safrole-results', crypto_library)
    report['safrole_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate every failure cause; preserve the historical direct-time default probe too.
        cases = [(member, origin) for origin in ('default', 'error') for member in SAFROLE_MEMBERS]
        cases += [('direct-time', 'default')]
        for member, origin in cases:
            # Require the intended success contract rather than a crash or unrelated assertion.
            result = command([binary, member, origin], 'safrole-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
            report['safrole'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' safrole '+member+' runtime guard', passed)
    # Public authorization fields and internal framing tuples must reject every default/failed payload read.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_authorization_results.nim', 'authorization-results', crypto_library)
    report['authorization_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every exact failure cause is checked before attempting its forbidden field observation.
        for origin in ('default', 'error'):
            for member in AUTHORIZATION_MEMBERS:
                # A crash, transport problem or unrelated assertion cannot count as success protection.
                result = command([binary, member, origin], 'authorization-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['authorization'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' authorization '+member+' runtime guard', passed)
    # Chapter-local results and closed source alternatives guard every inactive/default observation.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_consensus_results.nim', 'consensus-results', crypto_library)
    report['consensus_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate public/private failures and both inactive source sequence branches.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in CONSENSUS_MEMBERS]
        cases += [('source-tickets', 'Keys', 'source.mode == Tickets'), ('source-keys', 'Tickets', 'source.mode == Keys')]
        for member, origin, sentinel in cases:
            # Require the exact success or branch contract rather than a crash or unrelated assertion.
            result = command([binary, member, origin], 'consensus-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['consensus'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' consensus '+member+' runtime guard', passed)
    # All public result shapes and private scan layouts require success before payload access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_state_disputes_results.nim', 'state-disputes-results', crypto_library)
    report['state_disputes_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate default and actual failed operations so one failed precondition cannot conceal another.
        for origin in ('default', 'error'):
            for member in STATE_DISPUTES_MEMBERS:
                result = command([binary, member, origin], 'state-disputes-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['state_disputes'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' chapter-5 '+member+' runtime guard', passed)
    # Public/private results and runtime-selected absent peak copies require exact supported contracts.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_history_results.nim', 'history-results', crypto_library)
    report['history_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and three kinds of absence execute independently.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in HISTORY_MEMBERS]
        cases += [('absent-hash', origin, 'peak.isPresent') for origin in ('default', 'source', 'decoded')]
        for member, origin, sentinel in cases:
            result = command([binary, member, origin], 'history-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['history'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' history '+member+' runtime guard', passed)
    # Every public/private result and each inactive assignment field must retain its exact contract.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_availability_results.nim', 'availability-results', crypto_library)
    report['availability_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and dynamic absence origins execute independently, retaining their own diagnostics.
        cases = [(member, origin, 'value.status == None') for origin in ('default', 'error') for member in AVAILABILITY_MEMBERS]
        cases += [('absent-'+field, origin, 'assignment.isPresent') for origin in ('default', 'source', 'decoded') for field in ('guarantee', 'registered')]
        for member, origin, sentinel in cases:
            result = command([binary, member, origin, availability_fixture], 'availability-'+origin+'-'+member)
            passed = result['exit_code'] == 1 and sentinel in result['output'] and '[AssertionDefect]' in result['output']
            report['availability'].append(dict(origin=origin, member=member, passed=passed, run=result))
            announce(origin+' availability '+member+' runtime guard', passed)
    # Every public result shape and private natural/layout proof requires success before payload access.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_privileges_results.nim', 'privileges-results', crypto_library)
    report['privileges_build'] = compiled
    if compiled['exit_code'] == 0:
        # Isolate actual failures and defaults so one rejected access never conceals another.
        for origin in ('default', 'error'):
            for member in PRIVILEGES_MEMBERS:
                result = command([binary, member, origin], 'privileges-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['privileges'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' privileges '+member+' runtime guard', passed)
    # All public and internal tuple/natural/layout payloads require exact successful selection.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_statistics_results.nim', 'statistics-results', crypto_library)
    report['statistics_build'] = compiled
    if compiled['exit_code'] == 0:
        # Keep each actual/default failure independent so one rejected read cannot hide another.
        for origin in ('default', 'error'):
            for member in STATISTICS_MEMBERS:
                result = command([binary, member, origin], 'statistics-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['statistics'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' statistics '+member+' runtime guard', passed)
    # Both queue domains and internal count/layout proofs require successful payload selection.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_workqueues_results.nim', 'workqueues-results', crypto_library)
    report['workqueues_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures execute separately so one rejected access cannot conceal another.
        for origin in ('default', 'error'):
            for member in WORKQUEUES_MEMBERS:
                result = command([binary, member, origin, availability_fixture], 'workqueues-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['workqueues'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' workqueues '+member+' runtime guard', passed)
    # Public entry/read/count/pair payloads and internal extent proofs retain exact success contracts.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_outputs_results.nim', 'outputs-results', crypto_library)
    report['outputs_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual and default failures execute independently so no rejected access conceals another.
        for origin in ('default', 'error'):
            for member in OUTPUTS_MEMBERS:
                result = command([binary, member, origin], 'outputs-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['outputs'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' outputs '+member+' runtime guard', passed)
    # Fixed metadata and encoded entries require exact success, even though records need no retained heap owner.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_accounts_results.nim', 'accounts-results', crypto_library)
    report['accounts_build'] = compiled
    if compiled['exit_code'] == 0:
        # Default and actual failures execute independently so no payload/progress bypass is concealed.
        for origin in ('default', 'error'):
            for member in ACCOUNTS_MEMBERS:
                result = command([binary, member, origin], 'accounts-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'parsed.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['accounts'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' accounts '+member+' runtime guard', passed)
    # Backend refusals and private alias misuse execute through a test-only observer, never production binaries.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_service_values_results.nim', 'service-values-results', crypto_observer)
    report['service_values_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures require their exact payload contract, including internal extent proofs.
        for origin in ('default', 'error'):
            for member in SERVICE_VALUES_MEMBERS:
                result = command([binary, member, origin], 'service-values-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['service_values'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' service values '+member+' runtime guard', passed)
    # Result payloads and every inactive timestamp require supported success/shape contracts.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_requests_results.nim', 'requests-results', crypto_observer)
    report['requests_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures cannot fabricate valid Requested histories, keys or completed progress.
        for origin in ('default', 'error'):
            for member in REQUESTS_MEMBERS:
                result = command([binary, member, origin], 'requests-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['requests'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' requests '+member+' runtime guard', passed)
        cases = [(field, origin, mode, tag) for origin in ('source', 'decoded') for field, mode, tag in REQUESTS_FIELDS]
        cases += [(field, 'default', 0, tag) for field, mode, tag in REQUESTS_FIELDS if mode == 0]
        # All six fields reject every inactive source/decoded mode and the empty default shape independently.
        for field, origin, mode, tag in cases:
            result = command([binary, 'field-'+field, origin, mode], f'requests-{origin}-{mode}-{field}')
            passed = result['exit_code'] == 1 and 'history.mode == '+tag in result['output'] and '[AssertionDefect]' in result['output']
            report['requests'].append(dict(origin=origin, member=field, inactive_mode=mode, passed=passed, run=result))
            announce(f'{origin} requests {mode}/{field} shape runtime guard', passed)
    # Complete composition payloads require exact success, including backend and association failures.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_composition_results.nim', 'composition-results', crypto_observer)
    report['composition_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual and default failures execute separately so one protected read never conceals another.
        for origin in ('default', 'error'):
            for member in COMPOSITION_MEMBERS:
                result = command([binary, member, origin, composition_fixture], 'composition-'+origin+'-'+member)
                passed = result['exit_code'] == 1 and 'value.status == None' in result['output'] and '[AssertionDefect]' in result['output']
                report['composition'].append(dict(origin=origin, member=member, passed=passed, run=result))
                announce(origin+' composition '+member+' runtime guard', passed)


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
    sources = (list((ROOT/'src/codec').glob('*.nim'))
               + [unit_source(name) if name in UNIT_SUITES else ROOT/f'tests/native/test_{name}.nim' for name in SUITES]
               + [unit_source(name).with_suffix('.output') for name in UNIT_SUITES]
               + unit_fixture_sources()
               + [ROOT/'tools/native_tests.py', ROOT/'Makefile', ROOT/'tests/test_native_units_harness.py']
               + [ROOT/'tests/support/ownership_checks.nim', ROOT/'tests/support/arc_evidence.nim', ROOT/'tests/native/report_codec_driver.nim']
               + list((ROOT/'tests').glob('report_*.py'))
               + list((ROOT/'tests').glob('guarantees_*.py'))
               + [ROOT/'tests/native/guarantees_driver.nim', ROOT/'tests/native/tickets_driver.nim',
                  ROOT/'tests/tickets_oracle.py', ROOT/'tests/test_tickets_harness.py',
                  ROOT/'tests/disputes_oracle.py', ROOT/'tests/native/disputes_driver.nim',
                  ROOT/'tests/test_disputes_harness.py', ROOT/'tests/package_oracle.py',
                  ROOT/'tests/native/package_driver.nim', ROOT/'tests/test_package_harness.py',
                  ROOT/'tests/header_oracle.py', ROOT/'tests/native/header_driver.nim',
                  ROOT/'tests/test_header_harness.py', ROOT/'tests/block_oracle.py',
                  ROOT/'tests/native/block_driver.nim', ROOT/'tests/test_block_harness.py',
                  ROOT/'tests/native/bits_driver.nim', ROOT/'tests/bits_oracle.py',
                  ROOT/'tests/test_bits_harness.py', ROOT/'tests/native/collections_driver.nim',
                  ROOT/'tests/collections_oracle.py', ROOT/'tests/test_collections_harness.py',
                  ROOT/'tests/native/c2_driver.nim', ROOT/'tests/c2_oracle.py', ROOT/'tests/test_c2_harness.py']
               + [ROOT/'tests/native/assurances_driver.nim', ROOT/'tests/assurances_oracle.py',
                  ROOT/'tests/test_codec.py', ROOT/'tests/digest_checks.py', ROOT/'spec/pins.json',
                  ROOT/'tests/test_report_harness.py', ROOT/'tests/test_assurances_harness.py']
               + list((ROOT/'tests/native').glob('nimony_*.nim'))
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in (*PRIVATE, *NOMINAL, *CONTRACTS)]
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in
                  ('unsupported_collection_scalar', 'negative_collection_width', 'wide_collection_width',
                   'scalar_collection_negative_width', 'scalar_collection_wide_width')]
               + [Path(__file__).resolve()])
    sources += [ROOT/path for path in ('src/bandersnatch/bandersnatch.nim', 'tests/bandersnatch_native.py',
                'Makefile', 'tools/native_checks.py', 'tools/test_python.py', 'tools/test_e2e.py',
                'tools/e2e_checks.py', 'tools/test_modules.py', 'tools/setup_nimony.py', 'tools/toolchain_archives.py', 'tools/format.py',
                'spec/toolchain.json', 'src/quic/session.nim', 'src/quic/offload.nim', 'tests/test_quic_offload.py',
                'tests/test_quic_offload_harness.py',
                'tests/native/compile_fail/offload_pool_copy.nim', 'tests/nimony_peer.py', 'tests/test_quic_harness.py',
                'tests/test_quic_service.py', 'tests/test_quic_soak.py', 'tests/test_quic_soak_harness.py',
                'tests/test_quic_mesh.py', 'tests/test_quic_resilience.py', 'tests/test_quic_mesh_harness.py',
                'src/quic/integration.nim', 'tests/test_integration.py', 'tests/integration_oracle.py', 'tests/native/integration_driver.nim',
                'src/quic/io.nim', 'src/quic/transport.nim', 'src/quic/peer.nim', 'src/quic/protocol.nim',
                'tests/native/quic_protocol_driver.nim', 'tests/quic_protocol_oracle.py', 'tests/test_quic_protocol_harness.py', 'vendor/jam-np/simple.md', 'tests/test_nimony_ci.py', 'tools/summarize_tests.py', 'tests/nimony_quic.py', 'spec/quic-proof-pins.json',
                'native/quic/transport_bridge.c', 'native/quic/transport_bridge.h', 'native/quic/cert_fields.c', 'native/quic/cert_fields.h',
                'tests/native/compile_fail/quic_io_endpoint_copy.nim',
                'tests/test_bandersnatch.py', 'tests/native/bandersnatch_driver.nim', 'tests/native/bandersnatch_observer.c', 'native/bandersnatch/bridge.h',
                'native/bandersnatch/src/lib.rs', 'native/bandersnatch/Cargo.toml', 'native/bandersnatch/Cargo.lock',
                'spec/bandersnatch-pins.json', '.github/workflows/linux.yml','src/crypto/guarantee.nim', 'tests/native/report_driver.nim',
                'tests/native/report_check.nim', 'tests/test_report_signature_harness.py','src/crypto/assurance_context.nim', 'tests/native/assurance_crypto_driver.nim',
                'tests/assurance_crypto_oracle.py', 'tests/test_assurance_crypto_harness.py', 'vectors/assurance-context.json','tests/native/driver.nim', 'tests/native/fixed_driver.nim',
                'tests/native/bounded_driver.nim', 'tests/native/composite_driver.nim', 'tests/native/digest_driver.nim',
                'tests/native/batch_support.nim', 'tests/test_early_codec_harness.py', 'tests/bounded_checks.py', 'tests/composite_checks.py',
                'vectors/natural-boundaries.json', 'vectors/fixed-unsigned-boundaries.json',
                'vectors/bounded-containers.json','tests/native/state_composition_driver.nim', 'tests/state_composition_oracle.py',
                'tests/test_state_composition_harness.py', 'tests/state_roots_oracle.py',
                'tests/test_state_roots_harness.py', 'tests/test_state_widths_harness.py',
                'tests/request_namespace_oracle.py', 'tests/test_request_namespace_harness.py',
                'tests/test_spec.py', 'tests/dependencies.py', 'tests/native/composition_fixture.nim',
                'tests/native/state_requests_driver.nim', 'tests/state_requests_oracle.py',
                'tests/test_state_requests_harness.py', 'tests/native/state_service_values_driver.nim', 'tests/state_service_values_oracle.py',
                'tests/test_state_service_values_harness.py', 'tests/native/state_accounts_driver.nim', 'tests/state_accounts_oracle.py',
                'tests/test_state_accounts_harness.py', 'tests/native/state_outputs_driver.nim', 'tests/state_outputs_oracle.py',
                'tests/test_state_outputs_harness.py', 'src/crypto/primitives.nim', 'tests/native/crypto_driver.nim',
                'tests/native/crypto_observer.c', 'tests/nimony_crypto.py', 'tests/test_nimony_crypto.py',
                'tests/test_crypto.py', 'tests/test_quic.py', 'native/crypto/primitive_bridge.c',
                'native/crypto/primitive_bridge.h', 'spec/crypto-pins.json',
                'tests/native/state_workqueues_driver.nim', 'tests/state_workqueues_oracle.py',
                'tests/test_state_workqueues_harness.py', 'tests/native/state_statistics_driver.nim', 'tests/state_statistics_oracle.py',
                'tests/test_state_statistics_harness.py', 'tests/state_widths_oracle.py', 'tests/native/state_privileges_driver.nim', 'tests/state_privileges_oracle.py',
                'tests/test_state_privileges_harness.py', 'tests/native/state_availability_driver.nim', 'tests/state_availability_oracle.py',
                'tests/test_state_availability_harness.py', 'tests/native/state_history_driver.nim', 'tests/state_history_oracle.py',
                'tests/test_state_history_harness.py', 'tests/native/state_disputes_driver.nim', 'tests/state_disputes_oracle.py',
                'tests/test_state_disputes_harness.py', 'tests/native/state_consensus_driver.nim', 'tests/state_consensus_oracle.py',
                'tests/test_state_consensus_harness.py', 'tests/native/state_authorization_driver.nim', 'tests/state_authorization_oracle.py',
                'tests/test_state_authorization_harness.py', 'tests/native/state_safrole_driver.nim', 'tests/state_safrole_oracle.py',
                'tests/test_state_safrole_harness.py', 'tests/native/state_trie_driver.nim', 'tests/state_trie_oracle.py',
                'tests/test_state_trie_harness.py', 'tests/native/state_layout_driver.nim', 'tests/state_layout_oracle.py',
                'tests/test_state_layout_harness.py', 'vectors/official/crypto/rfc8032.json', 'vendor/wycheproof/LICENSE',
                'vendor/wycheproof/testvectors_v1/ed25519_test.json')]
    sources += list((ROOT/'src/state').glob('*.nim')) + [ROOT/'tests/state_store_fixtures.py', ROOT/'tests/validator_rotation_fixtures.py', ROOT/'tests/support/validator_rotation_fixture.nim', ROOT/'tests/native/validator_rotation_results.nim', ROOT/'tests/native/validator_state_results.nim', ROOT/'tests/ticket_admission_fixtures.py', ROOT/'tests/sealer_schedule_fixtures.py', ROOT/'tests/safrole_marker_fixtures.py', ROOT/'tests/native/safrole_markers_results.nim', ROOT/'tests/native/sealer_schedule_results.nim', ROOT/'tests/native/sealer_state_results.nim', ROOT/'tests/native/ticket_admission_results.nim', ROOT/'tests/native/ticket_state_results.nim', ROOT/'tests/entropy_transition_fixtures.py', ROOT/'tests/support/entropy_transition_fixture.nim', ROOT/'tests/native/entropy_transition_results.nim', ROOT/'tests/signing_domain_fixtures.py', ROOT/'tests/history_transition_fixtures.py', ROOT/'tests/support/history_transition_fixture.nim', ROOT/'tests/native/history_transition_results.nim', ROOT/'tests/authorization_transition_fixtures.py', ROOT/'tests/support/authorization_transition_fixture.nim', ROOT/'tests/native/authorization_transition_results.nim', ROOT/'tests/native/state_store_results.nim']
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
        assert set(SUITES) == set(UNIT_SUITES) and len(SUITES) == len(UNIT_SUITES)
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
