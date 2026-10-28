# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Re-execute genuine anchored work from a C8-bearing exact map before capturing configured parent context.

import std/assertions
import ../../src/state/computed_lookup as state_computed_lookup
import ../../src/state/computed_recent as state_computed_recent
import ../../src/state/computed_state as state_computed_state
import ../../src/state/computed_links as state_computed_links
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/computed_report as state_computed_report
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/report_identity as state_report_identity
import ../../src/state/authorized_refinement as state_authorized_refinement
import ../../src/state/authorization_invocation as state_authorization_invocation
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/crypto/extrinsic_commitment as crypto_extrinsic_commitment
import ./pvm_computed_lookup
import ./pvm_computed_recent
import ./pvm_computed_state
import ./pvm_input_refinement
import ./pvm_computed_report
import ./pvm_export_erasure
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs
import ./codec_validator_rotation_fixture

type
  ComputedProfileFixture* = object ## Mutable test handles preserve exact source/version provenance for context replacement witnesses.
    source*: LookupAnchoredComputedReport
    configured*: BlockSnapshotResult
    state*: StateStore
    parameters*: Parameters
    parent*: OwnedHeader
proc changedParameter*(parameters: Parameters, field: Parameter): Parameters =
  ## Mutate one independent fetch-field low bit using the pinned tuple's explicit widths, preserving valid fixture invariants.
  const widths = [8, 8, 8, 2, 4, 4, 8, 8, 8, 8, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4]
  var wire = parameters.encodeParameters
  var offset = 0
  for index in 0..<ord(field): offset += widths[index] # Fixed width sum is at most122 before indexing.
  wire[offset] = wire[offset] xor 1
  let decoded = decodeParameters(wire)
  assert decoded.ok and decoded.value.valid, "valid independently changed configured parameter"
  decoded.value
proc profileReport(execution: InputRefinement): ComputedReportLinks =
  ## Complete original bundle/availability/report/transcript provenance before any chain configuration binding.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
      products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc profileFixture*(): ComputedProfileFixture =
  ## Add real encoded parent C8 before final package context capture, then execute and admit the exact new version.
  let base = lookupFixture()
  let prior = base.source.computedRecentSource.value
  let binding = prior.computedStateAdmission.value
  let oldReport = prior.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
  let identity = oldReport.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let authorization = identity.identitySource.value.authorizedSource.value
  let package = authorization.authorizationPackage.value
  let parameters = authorization.authorizationParameters.value
  var state = forkStateStore(prior.computedStateSnapshot.value).value
  let roster = validatorEntry(ValidatorChapter.Active, rotationRecords(6, 42), rotationRosterConfig(2)).value
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: roster.key,
      value: roster.value)]).error == StateStoreError.None
  let snapshot = state.snapshot.value
  let info = package.workPackageInfo.value
  assert info.items == 1, "single fixture item"
  let selected = package.workItemAt(0).value
  let item = selected.workItemInfo.value
  assert item.imports == 0 and item.extrinsics == 0, "explicit empty original manifests"
  var context = info.context
  context.stateRoot.bytes = array[32, byte](snapshot.commitment.root)
  var payload = newSeq[byte](item.payloadBytes)
  var configuration = newSeq[byte](info.configurationBytes)
  var authorizationBytes = newSeq[byte](info.authorizationBytes)
  assert selected.copyItemPayload(payload).error == PackageError.None
  assert package.copyPackageBlob(PackageBlob.Configuration, configuration).error ==
      PackageError.None
  assert package.copyPackageBlob(PackageBlob.Authorization, authorizationBytes).error ==
      PackageError.None
  let updated = WorkPackage(host: info.host, codeHash: info.codeHash, context: context,
    authorization: authorizationBytes, configuration: configuration, items: @[WorkItem(
      service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: item.accumulateGas,
      exports: item.exports, payload: payload)])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(updated, config, wire).value
  let captured = decodeWorkPackage(wire.toOpenArray(0, written-1), config).value.owner
  let external = verifyExtrinsicInputs(captured, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  let inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
  let execution = runInputRefinement(snapshot, inputs, identity.identityInfo.value.core, parameters,
      executionLimits()).value
  let links = profileReport(execution)
  let empty = decodeExtrinsic([0'u8, 0, 0, 0, 0, 0, 0], stateFrame().frame).value.owner
  let ext = extrinsicCommitment(empty, ByteLimit(100000)).value
  let childFields = headerInfo(binding.admittedHeader).value.unsigned
  let child = Header(unsigned: UnsignedHeader(parent: childFields.parent, slot: childFields.slot,
    priorState: PriorStateRoot(array[32, byte](snapshot.commitment.root)), extrinsics: ext))
  var blockWire = newSeq[byte](4096)
  let headerConfig = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
      epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096))
  let childSize = encodeHeader(child, headerConfig, blockWire).value
  blockWire.setLen(childSize)
  for index in 0..<7: blockWire.add(0) # Complete empty extrinsic follows the sealed child.
  let candidate = decodeBlock(blockWire, stateFrame().frame).value.owner
  let admitted = validateBlockCommitments(candidate, binding.admittedParent, snapshot, stateFrame())
  assert admitted.error == BlockAdmissionError.None, "real C8-bearing block/state admission"
  let bound = bindComputedState(links, admitted).value
  let recent = checkComputedRecentAnchor(bound, recentConfig()).value
  let source = checkComputedLookupAnchor(recent, base.older, lookupLimits()).value
  let configured = captureBlockSnapshot(lookupWire(binding.admittedParent), snapshot, parameters)
  assert configured.error == GenesisError.None, "genuine configured parent snapshot capture"
  ComputedProfileFixture(source: source, configured: configured, state: state,
    parameters: parameters, parent: binding.admittedParent)
