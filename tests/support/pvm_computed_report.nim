# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine original execution/availability fixtures for complete report bytes and inherited parameter bounds.

import std/assertions
import ../../src/state/availability/specifier as availability_specifier
import "../../src/state/export/erasure" as export_erasure
import ../../src/state/bundle_erasure
import ../../src/state/erasure/[layout as erasure_layout, words as erasure_words]
import ../../src/state/[auditable_bundle, input_refinement, extrinsic_inputs]
import "../../src/state/import/inputs" as import_inputs
import "../../src/state/import/justification" as import_justification
import ../../src/codec/bounded
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/pvm/host/fetch as host_fetch
import ../../src/chain/parameters
import ./[pvm_export_erasure, pvm_input_refinement, pvm_report_results, pvm_refinement_outcome,
  pvm_extrinsic_inputs, pvm_import_inputs]

proc reportAvailabilityLimits*(): AvailabilityCommitmentLimits =
  ## Finite assembly policies cover the existing independently authored source cases.
  AvailabilityCommitmentLimits(bytes: ByteLimit(1000000), hashBytes: ByteLimit(10000000),
      hashes: ElementLimit(100000))
proc availabilityFromExecution(execution: InputRefinement, shards: uint16): AvailabilityCommitment =
  ## Complete all original bundle/export transformations before report assembly can consume the owner.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(shards), ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
      products: FieldProductLimit(10000000))).value
  let exports = prepareExportErasure(encoded, exportErasureLimits()).value
  prepareAvailabilityCommitment(exports, reportAvailabilityLimits()).value
proc contextExecution(): InputRefinement =
  ## Commit nonzero context/prerequisites before verifying original manifests and running genuine authorization/refinement.
  let halt = @[50'u8, 0]
  let auth = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), halt]
  var fixture = executionFixture(auth, [fetchedGuest(4), fetchedGuest(6)])
  let original = fixture.package.workPackageInfo.value
  var context = original.context
  context.anchor.bytes[0] = 1
  context.anchorSlot = AnchorSlot(10)
  context.stateRoot.bytes[0] = 2
  context.accumulationRoot.bytes[0] = 3
  context.lookupAnchor.bytes[0] = 4
  context.lookupStateRoot.bytes[0] = 5
  context.prerequisiteCount = 2
  context.prerequisites[0].bytes[0] = 6
  context.prerequisites[1].bytes[0] = 7
  var source = WorkPackage(host: original.host, codeHash: original.codeHash, context: context,
    authorization: @[91'u8], configuration: @[81'u8, 82])
  var extrinsics: seq[seq[seq[byte]]] = @[]
  var imports: seq[seq[VerifiedImport]] = @[]
  let oldExtrinsics = fixture.inputs.importInputsExtrinsics.value
  for index in 0..<original.items:
    let item = fixture.package.workItemAt(index).value
    let info = item.workItemInfo.value
    var payload = newSeq[byte](info.payloadBytes)
    assert item.copyItemPayload(payload).error == PackageError.None, "original context fixture payload"
    var copied = WorkItem(service: info.service, codeHash: info.codeHash, refineGas: info.refineGas,
      accumulateGas: info.accumulateGas, exports: info.exports, payload: payload)
    var blobs: seq[seq[byte]] = @[]
    var proofs: seq[VerifiedImport] = @[]
    # Copy the original manifest and its already authenticated bytes before binding to the new final package.
    for ordinal in 0..<info.extrinsics:
      copied.extrinsics.add(item.extrinsicAt(ordinal).value)
      blobs.add(oldExtrinsics.extrinsicInput(FetchItemIndex(uint64(index)), ExtrinsicInputIndex(
          uint64(ordinal))).value)
    for ordinal in 0..<info.imports:
      copied.imports.add(item.importAt(ordinal).value)
      proofs.add(fixture.inputs.importInput(FetchItemIndex(uint64(index)), ImportInputIndex(uint64(
          ordinal))).value)
    source.items.add(copied)
    extrinsics.add(blobs)
    imports.add(proofs)
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(source, config, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, written-1), config).value.owner
  let verified = verifyExtrinsicInputs(fixture.package, extrinsics, extrinsicLimits()).value
  fixture.inputs = bindImportInputs(verified, imports, fixture.inputs.importInputsLookup.value,
      inputLimits()).value
  executionRun(fixture).value
proc computedAvailability*(kind: int): AvailabilityCommitment =
  ## Select either independently frozen export-only sources or the nonzero-context/trace/output/import source.
  if kind == 4: return availabilityFromExecution(contextExecution(), 6)
  let shards = if kind == 0 or kind == 65: 6'u16 else: 1023'u16
  let exports = prepareExportErasure(exportBundle(kind, shards), exportErasureLimits()).value
  prepareAvailabilityCommitment(exports, reportAvailabilityLimits()).value
proc narrowReportSource*(): AvailabilityCommitment =
  ## Preserve an actual two-core parameter snapshot while selecting nine structurally allowed erasure shards upstream.
  let halt = @[50'u8, 0]
  let guest = reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture([halt], [guest], external = false)
  var bytes = fixture.parameters.encodeParameters
  bytes[24] = 2 # Three E8 deposit parameters precede the E2 core-count field.
  bytes[25] = 0
  fixture.parameters = decodeParameters(bytes).value
  availabilityFromExecution(executionRun(fixture, core = 0).value, 9)
