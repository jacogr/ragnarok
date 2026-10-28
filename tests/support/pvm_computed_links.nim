# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine singleton exporters and importing packages for computational lookup correspondence.

import std/assertions
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/state/computed_report as state_computed_report
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ./pvm_input_refinement
import ./pvm_report_results
import ./pvm_refinement_outcome
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs
import ./pvm_import_justification
import ./pvm_export_erasure
import ./pvm_computed_report
import ./pvm_export_erasure_vectors
import ./pvm_export_vectors

proc linksReport(execution: InputRefinement): ComputedWorkReport =
  ## Run the full original bundle/export/availability pipeline with a small valid six-validator geometry.
  let bundle = prepareAuditableBundle(execution, ByteLimit(100000)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(100000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
    products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  prepareComputedReport(available, ByteLimit(100000)).value
proc linksSegment*(zero = false): FetchSegment =
  ## Independent literal successful export bytes are 11/12/13 followed by 4101 zero bytes.
  var bytes = default(array[4104, byte])
  if not zero:
    bytes[0] = 11
    bytes[1] = 12
    bytes[2] = 13
  FetchSegment(bytes)
proc linksPackage(exporter: bool, pairs: openArray[SegmentLookup], salt: byte,
    repeat: bool): ComputedWorkReport =
  ## Commit the complete final manifest before proving singleton imports or running original guests.
  let halt = @[50'u8, 0]
  let guest = if exporter:
    reportGuest([refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8],
      refinementImmediate(8, 0), halt], declared = 1)
  else:
    reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture([halt], [guest], external = false)
  let original = fixture.package.workPackageInfo.value
  let info = fixture.package.workItemAt(0).value.workItemInfo.value
  var item = WorkItem(service: info.service, codeHash: info.codeHash, refineGas: info.refineGas,
    accumulateGas: info.accumulateGas, exports: info.exports, payload: @[salt])
  var proofs: seq[VerifiedImport] = @[]
  # Each supplied pair receives a real singleton proof under its declared root before package binding.
  for pair in pairs:
    item.imports.add(packageImport(pair.packageHash, ImportIndex(0)))
    proofs.add(verifyImportSegment(pair.segmentRoot, ImportIndex(0), linksSegment(
        pair.segmentRoot.bytes == ZeroRoots[1]), [], importLimits()).value)
  if repeat and pairs.len > 0:
    # Repeated package imports reuse one dictionary entry; a direct-root import adds no dictionary key.
    item.imports.add(packageImport(pairs[0].packageHash, ImportIndex(0)))
    item.imports.add(rootImport(pairs[0].segmentRoot, ImportIndex(0)))
    let repeated = proofs[0]
    proofs.add(repeated)
    proofs.add(repeated)
  let source = WorkPackage(host: original.host, codeHash: original.codeHash,
    context: original.context,
    authorization: @[91'u8], configuration: @[81'u8, 82], items: @[item])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(source, config, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  let verified = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  fixture.inputs = bindImportInputs(verified, @[proofs], pairs, inputLimits()).value
  linksReport(executionRun(fixture).value)
proc linksExporter*(salt: byte): ComputedWorkReport =
  ## Distinct committed payloads produce distinct package hashes with the same independently frozen singleton root.
  result = linksPackage(true, [], salt, false)
  assert result.computedReportInfo.value.header.segmentRoot.bytes == SingleRoot, "independent singleton export root"
proc linksPair*(report: ComputedWorkReport, wrongRoot = false): SegmentLookup =
  ## A wrong-root case deliberately claims another valid singleton root for the exact computed package key.
  let header = report.computedReportInfo.value.header
  SegmentLookup(packageHash: header.packageHash, segmentRoot: if wrongRoot: SegmentRoot(
      bytes: ZeroRoots[1]) else: header.segmentRoot)
proc linksConsumer*(pairs: openArray[SegmentLookup], repeat = false): ComputedGuaranteeTranscript =
  ## Capture a complete source-bound transcript after valid inclusion, execution and report construction.
  let report = linksPackage(false, pairs, 99, repeat)
  prepareComputedGuarantee(report, ByteLimit(100000)).value
proc linksLess*(left, right: ComputedWorkReport): bool =
  ## Sort test handles by original canonical hash bytes without changing production relation order.
  let a = left.computedReportInfo.value.header.packageHash.bytes
  let b = right.computedReportInfo.value.header.packageHash.bytes
  for index in 0..<32:
    if a[index] != b[index]: return a[index] < b[index] # First differing octet decides.
  false
proc linksExporters*(count: int): seq[ComputedWorkReport] =
  ## Prepare and insertion-sort up to eight genuine exporters before constructing their canonical consumer dictionary.
  result = @[]
  for index in 0..<count:
    result.add(linksExporter(byte(index+1)))
    var cursor = result.len-1
    while cursor > 0 and linksLess(result[cursor], result[cursor-1]):
      let prior = result[cursor-1]
      let current = result[cursor]
      result[cursor-1] = current
      result[cursor] = prior
      dec cursor
proc linksPairs*(reports: openArray[ComputedWorkReport]): seq[SegmentLookup] =
  ## Copy exact computed identities into the manifest before the consumer execution, never into the checked owner.
  result = @[]
  for report in reports: result.add(linksPair(report))
