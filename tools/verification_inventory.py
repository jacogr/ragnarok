"""Authoritative native suite, corpus and failure inventories; importing performs no I/O."""

# Execution and discovery use the same ordinary-suite identities.
UNIT_SUITES = ('telemetry', 'telemetry_chain', 'natural', 'fixed_unsigned', 'bounded', 'composite', 'work_digest', 'ownership', 'report_snapshots', 'tickets', 'assurances', 'guarantees', 'disputes', 'work_package', 'header', 'block', 'block_private', 'bits', 'bits_private', 'collections', 'collections_private', 'c2', 'c2_private', 'state_layout', 'state_trie', 'state_trie_private', 'state_store', 'state_store_failure', 'state_store_replay', 'authorization_transition', 'authorization_transition_failure', 'history_transition', 'history_transition_failure', 'entropy_transition', 'entropy_transition_failure', 'validator_rotation', 'validator_state', 'ticket_admission', 'ticket_state', 'sealer_schedule', 'sealer_state', 'state_safrole', 'state_authorization', 'state_authorization_private', 'state_consensus', 'state_consensus_private', 'state_disputes', 'state_disputes_private', 'state_history', 'state_history_private', 'state_availability', 'state_availability_private', 'state_workqueues', 'state_workqueues_private', 'state_privileges', 'state_privileges_private', 'state_statistics', 'state_statistics_private', 'state_outputs', 'state_outputs_private', 'state_accounts', 'state_accounts_private', 'state_service_values', 'service_values_private', 'state_requests', 'state_requests_private', 'state_composition_private', 'crypto_seeds', 'assurance_context', 'guarantee_message', 'signing_domains', 'bandersnatch_owners', 'quic_io', 'quic_transport', 'quic_protocol', 'quic_integration', 'quic_integration_disabled')
PRIVATE = dict(sealer_state_private='completed', sealer_state_retag='status', sealer_schedule_private='completed', sealer_schedule_retag='status', ticket_state_private='completed', ticket_state_retag='status', ticket_admission_private='completed', ticket_admission_retag='status', validator_state_private='completed', validator_state_retag='status', validator_rotation_private='completed', validator_rotation_retag='status', entropy_transition_private='completed', entropy_transition_retag='status', history_transition_private='completed', history_transition_retag='status', authorization_transition_private='completed', authorization_transition_retag='status', store_result_retag='status', store_head_private='head', store_snapshot_private='data',
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


# Fixed inventories retain every historical diagnostic family when jobs execute independently.
FAILURE_COUNTS = {
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


