# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Re-execute genuine anchored work from a C8-bearing exact map before capturing configured parent context.

import std/assertions
import ../../src/state/[computed_lookup, computed_recent, computed_state, computed_links,
  computed_guarantee, computed_report, block_admission, store, availability_specifier,
  export_erasure,
  bundle_erasure, erasure_layout, erasure_words, auditable_bundle, input_refinement,
  report_identity,
  authorized_refinement, authorization_invocation, extrinsic_inputs, import_inputs, import_justification]
import ../../src/chain/[genesis, parameters]
import ../../src/codec/[bounded, header, block_codec, work_package, work_report, composite,
  state_layout, state_trie, state_safrole]
import ../../src/crypto/extrinsic_commitment
import ./[pvm_computed_lookup, pvm_computed_recent, pvm_computed_state, pvm_input_refinement,
  pvm_computed_report, pvm_export_erasure, pvm_extrinsic_inputs, pvm_import_inputs, validator_rotation_fixture]

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
