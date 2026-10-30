# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical source-package fixtures vary payloads/manifests before refinement, preserving actual code commitments.

import std/assertions
import ../../src/state/refinement/[digest as refinement_digest, report as refinement_report]
import ../../src/codec/[bounded, composite]
import ../../src/codec/work/[package as work_package, digest as work_digest, report as work_report]
import ../../src/pvm/host/fetch as host_fetch
import ./pvm_report_results

proc digestLimits*(): RefinementDigestLimits =
  ## Finite independent hashing and encoded-storage policies admit all authored boundary witnesses.
  RefinementDigestLimits(items: ElementLimit(16), payload: ByteLimit(4096),
    totalPayload: ByteLimit(65536), encoding: ByteLimit(65536), totalEncoding: ByteLimit(1048576))
proc digestFixture*(guests: openArray[ReportGuest], payloads: openArray[seq[byte]],
    manifests = false, wide = false): ReportFixture =
  ## Replace only test input sources before executing them; the production constructor accepts no detached replacements.
  assert guests.len == payloads.len
  result = reportFixture(guests)
  var source = WorkPackage(context: result.package.workPackageInfo.value.context)
  for index, payload in payloads:
    let original = result.package.workItemAt(index).value.workItemInfo.value
    var item = WorkItem(service: original.service, codeHash: original.codeHash,
      refineGas: original.refineGas, accumulateGas: Gas(uint64(65536+index)),
      exports: original.exports, payload: payload)
    if manifests and index == 0:
      item.imports = @[rootImport(SegmentRoot(), ImportIndex(0)), rootImport(SegmentRoot(),
          ImportIndex(1))]
      let lengths = if wide: @[65536'u32, 65537] else: @[0'u32, 128, 129]
      for size in lengths:
        item.extrinsics.add(ExtrinsicCommitment(length: ExtrinsicLength(size)))
        if not wide:
          result.inputs.extrinsics[index].add(newSeq[byte](int(
              size))) # Wide BAD inputs deliberately have no preimages.
      result.inputs.imports[index] = @[default(FetchSegment), default(FetchSegment)]
    source.items.add(item)
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let encoded = encodeWorkPackage(source, config, wire)
  assert encoded.error == PackageError.None
  result.package = decodeWorkPackage(wire.toOpenArray(0, encoded.value-1), config).value.owner
proc digestReportFixture*(fixture: ReportFixture, trace: openArray[byte]): RefinedPackage =
  ## Manifest bytes are locally bounded; payload/code selection remains the original canonical captured package.
  var cap = reportLimits()
  cap.invocation.capture.inputs = FetchInputLimit(32768)
  reportRun(fixture, trace, cap).value
