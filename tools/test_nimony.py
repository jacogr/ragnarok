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
SUITES = ('natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'assurances', 'guarantees', 'tickets', 'disputes', 'work_package', 'header', 'block', 'block_private', 'bits', 'bits_private', 'collections', 'collections_private', 'c2', 'c2_private', 'crypto_seeds', 'state_layout', 'state_trie', 'state_trie_private', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private')
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
def build(compiler, source, name, crypto_library=None):
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
             '--boundchecks:on', '--passC:-flto', '--passL:-flto']
    if platform.system() == 'Linux':
        # Preserve the established Linux LTO linker choice when the trial reaches that host.
        flags += ['--passL:-fuse-ld=lld']
    if crypto_library is not None:
        # Crypto clients use the maintained public C header and one explicit native library.
        flags += [f'--passC:-I{ROOT/"native/crypto"}', f'--passL:{crypto_library}']
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
                  python=platform.python_version()), suites=[], runtime=[], bounded=[], primitive=[], composite=[], owned=[], reports=[], assurances=[], guarantees=[], tickets=[], disputes=[], packages=[], headers=[], blocks=[], bits=[], collections=[], c2=[], crypto=[], layout=[], trie=[], safrole=[], authorization=[], consensus=[], state_disputes=[], schemas=[], privacy=[], nominal=[])
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
                  ROOT/'tests/native/block_driver.nim', ROOT/'tests/test_block_harness.py',
                  ROOT/'tests/native/bits_driver.nim', ROOT/'tests/bits_oracle.py',
                  ROOT/'tests/test_bits_harness.py', ROOT/'tests/native/collections_driver.nim',
                  ROOT/'tests/collections_oracle.py', ROOT/'tests/test_collections_harness.py',
                  ROOT/'tests/native/c2_driver.nim', ROOT/'tests/c2_oracle.py', ROOT/'tests/test_c2_harness.py']
               + [ROOT/'tests/native/assurances_driver.nim', ROOT/'tests/assurances_oracle.py',
                  ROOT/'tests/test_codec.py', ROOT/'tests/digest_checks.py', ROOT/'spec/pins.json']
               + list((ROOT/'tests/native').glob('nimony_*.nim'))
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in (*PRIVATE, *NOMINAL)]
               + [ROOT/f'tests/native/compile_fail/{name}.nim' for name in
                  ('unsupported_collection_scalar', 'negative_collection_width', 'wide_collection_width',
                   'scalar_collection_negative_width', 'scalar_collection_wide_width')]
               + [Path(__file__).resolve()])
    sources += [ROOT/path for path in ('src/crypto/primitives.nim', 'tests/native/crypto_driver.nim',
                'tests/native/crypto_observer.c', 'tests/nimony_crypto.py', 'tests/test_nimony_crypto.py',
                'tests/test_crypto.py', 'tests/test_quic.py', 'native/crypto/primitive_bridge.c',
                'native/crypto/primitive_bridge.h', 'spec/crypto-pins.json',
                'tests/native/state_disputes_driver.nim', 'tests/state_disputes_oracle.py',
                'tests/test_state_disputes_harness.py', 'tests/native/state_consensus_driver.nim', 'tests/state_consensus_oracle.py',
                'tests/test_state_consensus_harness.py', 'tests/native/state_authorization_driver.nim', 'tests/state_authorization_oracle.py',
                'tests/test_state_authorization_harness.py', 'tests/native/state_safrole_driver.nim', 'tests/state_safrole_oracle.py',
                'tests/test_state_safrole_harness.py', 'tests/native/state_trie_driver.nim', 'tests/state_trie_oracle.py',
                'tests/test_state_trie_harness.py', 'tests/native/state_layout_driver.nim', 'tests/state_layout_oracle.py',
                'tests/test_state_layout_harness.py', 'vectors/official/crypto/rfc8032.json', 'vendor/wycheproof/LICENSE',
                'vendor/wycheproof/testvectors_v1/ed25519_test.json')]
    report['source_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted(sources)}
    # The existing native guarantee suite consumes an independently authored minimal report fixture.
    sys.path.insert(0, str(ROOT/'tests'))
    from nimony_crypto import prepare as prepare_crypto
    crypto_library, crypto_observer, report['crypto_native'] = prepare_crypto(BUILD)
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
        compiled, binary = build(compiler, ROOT/f'tests/native/test_{name}.nim', name,
                                 crypto_observer if name in ('crypto_seeds', 'state_layout', 'state_trie_private')
                                 else crypto_library if name in ('state_trie', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private') else None)
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
            if name == 'bits' and row['passed']:
                # Replaced handles, escaped sources and empty/nonempty captures release their final ARC references.
                release = re.search(r'BITS_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy measures this warmed workload, not RSS or general leak freedom.
                    report['bits_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'collections' and row['passed']:
                # Replaced typed sets/dictionaries and zero-width domains release their final ARC references.
                release = re.search(r'COLLECTION_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy measures this warmed workload, not RSS or general leak freedom.
                    report['collection_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
            if name == 'c2' and row['passed']:
                # Operand owners survive union/source retirement and release every retained/error snapshot at scope exit.
                release = re.search(r'C2_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
                row['passed'] = release is not None and release[1] == release[2]
                if release is not None:
                    # Public live occupancy observes this warmed workload, not RSS or general leak freedom.
                    report['c2_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'state_disputes_private' and row['passed']:
            # Retained/replaced chapter-5 parents and copied set identities retire at their final ARC owner.
            release = re.search(r'STATE_DISPUTES_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # Public live occupancy measures this warmed workload, never RSS or general leak freedom.
                report['state_disputes_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'state_consensus_private' and row['passed']:
            # Both parent modes, escaped children and copied source arrays must retire at final ARC release.
            release = re.search(r'CONSENSUS_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # Public live allocator occupancy is workload-specific, not RSS or general leak freedom.
                report['consensus_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'state_authorization_private' and row['passed']:
            # Nested pool/queue storage must release after callee return, replacement, alias retention and failure.
            release = re.search(r'AUTHORIZATION_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # Public live allocator counts cover this warmed workload, not RSS or general leak freedom.
                report['authorization_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'state_safrole' and row['passed']:
            # Escaped/replaced immutable roster owners and fixed-entry temporaries must retire at final ARC release.
            release = re.search(r'STATE_SAFROLE_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # Live allocator occupancy covers this warmed workload, not RSS or general leak freedom.
                report['safrole_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'state_trie_private' and row['passed']:
            # Temporary sorted-key scratch must retire after success, preflight rejection and early/late backend failure.
            release = re.search(r'TRIE_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # Public allocator occupancy is workload-specific and excludes RSS/retained page interpretations.
                report['trie_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
        if name == 'crypto_seeds' and row['passed']:
            # Exact-storage wipe checks run while memory is live; occupancy must return after final-owner release.
            release = re.search(r'CRYPTO_ARC_RELEASE cycles=1000 occupied_before=(\d+) occupied_after=(\d+)', row['run']['output'])
            row['passed'] = release is not None and release[1] == release[2]
            if release is not None:
                # These public allocator counts apply only to the warmed isolated workload.
                report['crypto_arc_release'] = dict(cycles=1000, occupied_before=int(release[1]), occupied_after=int(release[2]))
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
    # Preserve all exhaustive Boolean/padding cases and pinned profile-field checks from the independent oracle.
    from bits_oracle import requests as bits_requests
    harness = command([sys.executable, ROOT/'tests/test_bits_harness.py'], 'bits-harness')
    lines, expected = bits_requests()
    source = BUILD/'bits-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {operation: sum(line.startswith(operation+' ') for line in lines)
              for operation in ('BD', 'BE', 'D', 'E')}
    compiled, binary = build(compiler, ROOT/'tests/native/bits_driver.nim', 'bits-codec')
    corpus = dict(build=compiled, harness=harness, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every logical bit/count/extent after input erasure and compare both owner framing forms.
        result = command([binary, source], 'bits-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first differing row and all native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['bits_corpus'] = corpus
    announce('independent Boolean/fixed/variable bitstring corpus', corpus['passed'])
    # Preserve the unchanged collection oracle: numeric/byte ordering, pairing and zero-width singleton domains.
    from collections_oracle import requests as collection_requests
    harness = command([sys.executable, ROOT/'tests/test_collections_harness.py'], 'collection-harness')
    lines, expected = collection_requests()
    source = BUILD/'collection-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    groups = {kind: sum(line.split()[1] == kind for line in lines) for kind in ('F', 'S', 'M')}
    assert sum(groups.values()) == len(lines), groups
    compiled, binary = build(compiler, ROOT/'tests/native/collections_driver.nim', 'collection-codec')
    corpus = dict(build=compiled, harness=harness, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Compare copied logical fields, canonical wire, consumed progress and typed reasons after input erasure.
        result = command([binary, source], 'collection-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain the first mismatch and complete native output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['collection_corpus'] = corpus
    announce('independent canonical fixed/variable set/dictionary corpus', corpus['passed'])
    # Independent C.2 references retain exact availability/transfer/operand framing and tagged-union agreement.
    from c2_oracle import requests as c2_requests
    harness = command([sys.executable, ROOT/'tests/test_c2_harness.py'], 'c2-harness')
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
    corpus = dict(build=compiled, harness=harness, requests=len(lines), request_groups=groups,
                  passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every fixed field, payload/trace copy and exact owned wire after destructive caller mutation.
        result = command([binary, source], 'c2-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Preserve the first mismatch and all adapter output for reproducible diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['c2_corpus'] = corpus
    announce('independent availability/transfer/operand/accumulation corpus', corpus['passed'])
    # Preserve the independent C/B/L equations, every hostile header/padding request and labelled historical projections.
    from state_layout_oracle import requests as layout_requests, legacy_singletons
    harness = command([sys.executable, ROOT/'tests/test_state_layout_harness.py'], 'layout-harness')
    lines, expected = layout_requests()
    source = BUILD/'layout-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_layout_driver.nim', 'layout-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  historical_projected_singletons=len(legacy_singletons()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # The reference computes keys/fields/padding/hash bytes independently before native execution.
        result = command([binary, source], 'layout-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first differing row and complete adapter output for diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['layout_corpus'] = corpus
    announce('independent state-key/node layout and hash corpus', corpus['passed'])
    # Compare independent unsorted-list partitions, every key divergence bit and labelled historical projections.
    from state_trie_oracle import requests as trie_requests, legacy_maps
    harness = command([sys.executable, ROOT/'tests/test_state_trie_harness.py'], 'trie-harness')
    lines, expected = trie_requests()
    source = BUILD/'trie-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_trie_driver.nim', 'trie-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  historical_projected_maps=len(legacy_maps()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Every result compares exact root/counts or a typed reason; caller preservation is checked by the adapter.
        result = command([binary, source], 'trie-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain complete native output and the first mismatch for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['trie_corpus'] = corpus
    announce('independent bounded state trie root corpus', corpus['passed'])
    # Preserve independent entropy/time/roster bytes, malformed inputs, published derived fixtures and partial roots.
    from state_safrole_oracle import requests as safrole_requests, published as safrole_published
    harness = command([sys.executable, ROOT/'tests/test_state_safrole_harness.py'], 'safrole-harness')
    lines, expected = safrole_requests()
    source = BUILD/'safrole-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_safrole_driver.nim', 'safrole-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  published_derived_state_sources=len(safrole_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Native fields/consumed counts and roots are compared only with independently authored expectations.
        result = command([binary, source], 'safrole-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep the first mismatch and complete native output for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['safrole_corpus'] = corpus
    announce('independent entropy/validator-roster/timeslot state corpus', corpus['passed'])
    # Preserve independent ordered core/row equations, malformed inputs, derived fixtures and partial commitments.
    from state_authorization_oracle import requests as authorization_requests, published as authorization_published
    harness = command([sys.executable, ROOT/'tests/test_state_authorization_harness.py'], 'authorization-harness')
    lines, expected = authorization_requests()
    source = BUILD/'authorization-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_authorization_driver.nim', 'authorization-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  published_derived_state_sources=len(authorization_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe fixed hashes and owner-bound boundaries after destructive caller mutation, comparing independent bytes.
        result = command([binary, source], 'authorization-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Retain complete output and the first mismatch for independent diagnosis.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['authorization_corpus'] = corpus
    announce('independent authorization pool/queue state corpus', corpus['passed'])
    # Preserve independent chapter-4 byte/field equations, derived fixtures and partial single-entry roots.
    from state_consensus_oracle import requests as consensus_requests, published as consensus_published
    harness = command([sys.executable, ROOT/'tests/test_state_consensus_harness.py'], 'consensus-harness')
    lines, expected = consensus_requests()
    source = BUILD/'consensus-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_consensus_driver.nim', 'consensus-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  published_derived_state_sources=len(consensus_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'consensus-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['consensus_corpus'] = corpus
    announce('independent chapter-4 Safrole basic state corpus', corpus['passed'])
    # Preserve independent chapter-5 byte/field equations, derived fixtures and partial single-entry roots.
    from state_disputes_oracle import requests as state_disputes_requests, published as state_disputes_published
    harness = command([sys.executable, ROOT/'tests/test_state_disputes_harness.py'], 'state_disputes-harness')
    lines, expected = state_disputes_requests()
    source = BUILD/'state_disputes-requests.txt'
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, ROOT/'tests/native/state_disputes_driver.nim', 'state_disputes-codec', crypto_library)
    corpus = dict(build=compiled, harness=harness, requests=len(lines), passed=False,
                  published_derived_state_sources=len(state_disputes_published()),
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    if compiled['exit_code'] == 0:
        # Observe every child field after caller mutation; no native round trip supplies an expected answer.
        result = command([binary, source], 'state_disputes-corpus')
        output = result.pop('output')
        actual = output.splitlines()
        corpus['run'] = result
        corpus['passed'] = harness['exit_code'] == 0 and result['exit_code'] == 0 and actual == expected
        corpus['actual_sha256'] = hashlib.sha256(output.encode()).hexdigest()
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
        if not corpus['passed']:
            # Keep complete output and the first mismatch for independent reproduction.
            corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e), min(len(actual), len(expected)))
    report['state_disputes_corpus'] = corpus
    announce('independent chapter-5 dispute judgment/offender state corpus', corpus['passed'])
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
                announce(origin+' bits '+member+' guard', passed)
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
            announce(origin+' collection '+member+' guard', passed)
    # Closed family checks and direct static scalar contracts reject unsupported schemas before execution.
    for name, domain in (('unsupported_collection_scalar', 'string'),
                         ('negative_collection_width', 'CollectionUInt'), ('wide_collection_width', 'CollectionUInt'),
                         ('scalar_collection_negative_width', '-1'), ('scalar_collection_wide_width', '9')):
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        if name.startswith('scalar_collection_'):
            # Constant-invalid direct helper calls fail at the supported precondition during compilation.
            rejected = ('Error: contract violated:' in result['output']
                        and '0 <= '+domain+' and '+domain+' <= 8' in result['output'])
        else:
            # No unsupported mutable schema or E width can instantiate a collection decoder.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'does not match constraint' in result['output'] and domain in result['output']
                        and 'decodeVariableSet(' in result['output'])
        passed = result['exit_code'] != 0 and rejected
        report['schemas'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
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
            announce(origin+' c2 '+member+' guard', passed)
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
                announce(origin+' crypto '+member+' guard', passed)
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
            announce(origin+' layout '+member+' guard', passed)
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
            announce(origin+' trie '+member+' guard', passed)
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
            announce(origin+' safrole '+member+' guard', passed)
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
                announce(origin+' authorization '+member+' guard', passed)
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
            announce(origin+' consensus '+member+' guard', passed)
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
                announce(origin+' chapter-5 '+member+' guard', passed)
    # Raw storage, retagging, success forgery and writing the public reason must all fail compilation.
    for name, member in PRIVATE.items():
        source = ROOT/f'tests/native/compile_fail/{name}.nim'
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{BUILD/(name+"-cache")}', source], name)
        if name == 'private_collection_commit':
            # Generic concept support must never export the unchecked writer.
            rejected = "undeclared identifier: 'put'" in result['output']
        elif name == 'wrong_owner_pool':
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
        if name in ('state_key_as_hash', 'state_partial_as_hash', 'state_value_as_node_hash', 'state_root_as_node'):
            # A key, truncated left commitment or value hash cannot fill a complete child-hash argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'encodeStateBranch(' in result['output']
                        and '[1] expected: StateNodeHash but got: '+member in result['output'])
        elif name == 'state_bytes_as_dispute_index':
            # Byte budgets cannot substitute for ordinals in the offender set.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'stateOffenderAt(' in result['output']
                        and '[2] expected: DisputeStateIndex but got: '+member in result['output'])
        elif name == 'state_validator_as_slot':
            # Pending validator ordinals cannot fill the distinct schedule-slot argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'sealerTicketAt(' in result['output']
                        and '[2] expected: SafroleStateIndex but got: '+member in result['output'])
        elif name == 'auth_core_as_position':
            # Core ordinals cannot fill the distinct per-row hash-position argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'authorizerAt(' in result['output']
                        and '[3] expected: AuthorizationIndex but got: '+member in result['output'])
        elif name == 'state_entropy_as_time':
            # Fixed entropy words cannot fill the E4 timeslot argument despite both being copied values.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'timeEntry(' in result['output']
                        and '[1] expected: StateTime but got: '+member in result['output'])
        elif name == 'swapped_import_identity':
            # The typed factory rejection prints generic ReportHash without its static domain; require its exact call/position.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'rootImport(' in result['output'] and member in result['output'])
        elif name in ('raw_bit_count', 'swapped_bit_limit', 'raw_collection_count',
                      'swapped_collection_schema', 'dictionary_as_set'):

            # The second parameter must retain its logical-bit domain, independently of array-view diagnostics.
            call = dict(raw_bit_count='decodeFixedBits(', swapped_bit_limit='decodeBits(',
                        raw_collection_count='decodeSet(', swapped_collection_schema='encodeOwnedVariableSet(',
                        dictionary_as_set='setCount(')[name]
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and call in result['output'] and member in result['output'])
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
                   and report['bits_corpus']['passed'] and report['collection_corpus']['passed']
                   and report['c2_corpus']['passed'] and report['crypto_corpus']['passed']
                   and report['layout_corpus']['passed'] and report['trie_corpus']['passed']
                   and report['safrole_corpus']['passed'] and report['authorization_corpus']['passed'] and report['consensus_corpus']['passed']
                   and report['state_disputes_corpus']['passed']
                   and len(report['state_disputes']) == 2*len(STATE_DISPUTES_MEMBERS)
                   and all(row['passed'] for row in report['state_disputes'])
                   and len(report['consensus']) == 2*len(CONSENSUS_MEMBERS)+2
                   and all(row['passed'] for row in report['consensus'])
                   and len(report['authorization']) == 2*len(AUTHORIZATION_MEMBERS)
                   and all(row['passed'] for row in report['authorization'])
                   and len(report['safrole']) == 2*len(SAFROLE_MEMBERS)+1
                   and all(row['passed'] for row in report['safrole'])
                   and len(report['trie']) == 3*len(TRIE_ORIGINS)+2
                   and all(row['passed'] for row in report['trie'])
                   and len(report['layout']) == 2*len(LAYOUT_MEMBERS)+len(LAYOUT_VARIANTS)
                   and all(row['passed'] for row in report['layout'])
                   and len(report['crypto']) == 2*len(CRYPTO_MEMBERS)
                   and all(row['passed'] for row in report['crypto'])
                   and len(report['c2']) == 2*len(C2_MEMBERS)+len(C2_VARIANTS)
                   and all(row['passed'] for row in report['c2'])
                   and len(report['collections']) == 2*len(COLLECTION_MEMBERS)
                   and all(row['passed'] for row in report['collections'])
                   and len(report['schemas']) == 5 and all(row['passed'] for row in report['schemas'])
                   and len(report['bits']) == 2*len(BITS_MEMBERS) and all(row['passed'] for row in report['bits'])
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
