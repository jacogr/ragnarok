# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Report ownership regressions supplement the full independent wire/semantic corpus.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "report_arc_release"}

import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/codec/[bounded, composite, work_digest, work_report, report_owned, owned]

# Construct a bounded report with ordered dependencies, authorization and successful/error digests.
proc capture(marker: byte): OwnedReport =
  var report = default(WorkReport)
  report.header.erasureShards = ErasureShards(6)
  report.core = CoreIndex(1)
  report.prerequisiteCount = 2
  report.prerequisites[0].bytes[0] = 1
  report.prerequisites[1].bytes[0] = 2
  report.lookupCount = 1
  report.lookup[0].packageHash.bytes[0] = 3
  report.lookup[0].segmentRoot.bytes[0] = 4
  report.authOutput = BlobSpan(offset: 0, length: 2)
  report.digestCount = 2
  report.digests[0].output = successfulWork(BlobSpan(offset: 2, length: 2))
  report.digests[1].output = failedWork(WorkKind.OutOfGas)
  var source = [marker, byte(20), marker, byte(40)]
  var wire = default(array[1024, byte])
  let written = encodeReportBorrowed(report, source, 2, wire)
  assert written.error == CompositeError.None
  let captured = decodeOwnedReport(wire, 2)
  assert captured.error == OwnershipError.None
  assert ownedReportInfo(captured.value).value.consumed == written.written
  # Neither the construction pool nor the original wire remains authoritative after capture.
  source[0] = 255
  wire[0] = 255
  wire[written.written-1] = 255
  captured.value

# Every API rejects default owners; destination bytes must survive all failed copies unchanged.
proc checkMissing() =
  let missing = default(OwnedReport)
  var destination = [byte(77), 88]
  assert ownedReportInfo(missing).error == OwnershipError.InvalidOwner
  assert ownedReportDigest(missing, 0).error == OwnershipError.InvalidOwner
  assert ownedReportPrerequisite(missing, 0).error == OwnershipError.InvalidOwner
  assert ownedReportLookup(missing, 0).error == OwnershipError.InvalidOwner
  assert ownedReportOverlapsOutput(missing, destination).error == OwnershipError.InvalidOwner
  assert copyReportBlob(missing, 0, destination).error == OwnershipError.InvalidOwner
  assert encodeOwnedReport(missing, destination).error == OwnershipError.InvalidOwner
  assert destination == [byte(77), 88]

# Check retained owners, copied metadata, error variants, exact prefix and atomic destination failure.
proc checkSnapshot(owner: OwnedReport, marker: byte) =
  var bytes = default(array[2, byte])
  assert copyReportBlob(owner, 0, bytes).value == 2 and bytes == [marker, byte(20)]
  assert copyReportBlob(owner, 1, bytes).value == 2 and bytes == [marker, byte(40)]
  let preserved = bytes
  assert copyReportBlob(owner, 2, bytes).error == OwnershipError.InvalidIndex
  assert copyReportBlob(owner, -1, bytes).error == OwnershipError.InvalidIndex
  assert copyReportBlob(owner, 3, bytes).error == OwnershipError.InvalidIndex
  assert bytes == preserved
  var short = [byte(77)]
  assert copyReportBlob(owner, 1, short).error == OwnershipError.OutputTooSmall
  assert encodeOwnedReport(owner, short).error == OwnershipError.OutputTooSmall
  assert short[0] == 77
  assert not ownedReportOverlapsOutput(owner, bytes).value
  var metadata = ownedReportInfo(owner).value
  assert metadata.prerequisiteCount == 2 and metadata.lookupCount == 1 and metadata.digestCount == 2
  metadata.header.packageHash.bytes[0] = 99
  assert ownedReportInfo(owner).value.header.packageHash.bytes[0] == 0
  var dependency = ownedReportPrerequisite(owner, 0).value
  dependency.bytes[0] = 99
  assert ownedReportPrerequisite(owner, 0).value.bytes[0] == 1
  var lookup = ownedReportLookup(owner, 0).value
  lookup.segmentRoot.bytes[0] = 99
  assert ownedReportLookup(owner, 0).value.segmentRoot.bytes[0] == 4
  assert ownedReportDigest(owner, 0).value.output.length == 2
  assert ownedReportDigest(owner, 1).value.output.kind == WorkKind.OutOfGas
  assert ownedReportDigest(owner, -1).error == OwnershipError.InvalidIndex
  assert ownedReportDigest(owner, 2).error == OwnershipError.InvalidIndex
  assert ownedReportPrerequisite(owner, 2).error == OwnershipError.InvalidIndex
  assert ownedReportLookup(owner, 1).error == OwnershipError.InvalidIndex
  var wire = default(array[1024, byte])
  let written = encodeOwnedReport(owner, wire).value
  assert written == ownedReportInfo(owner).value.consumed
  let decoded = decodeReportBorrowed(wire.toOpenArray(0, written-1), 2)
  assert decoded.error == CompositeError.None and decoded.consumed == written
  assert wire[decoded.value.authOutput.offset] == marker
  assert wire[decoded.value.digests[0].output.blob.offset] == marker

# A replacement must release only its own reference while an alias retains the old snapshot.
proc releaseCycle(marker: byte) =
  var original = capture(marker)
  let retained = original
  original = capture(marker xor 255)
  checkSnapshot(original, marker xor 255)
  checkSnapshot(retained, marker)

checkMissing()
# Warm allocator/runtime state before observing public live occupancy across isolated ARC scopes.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
# Vary bytes while all construction pools, snapshot aliases and copies die on every return.
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
let missingReport = default(ReportResult)
assert missingReport.error == CompositeError.Uninitialized
let missingHeader = default(ReportHeaderResult)
assert missingHeader.error == CompositeError.Uninitialized
let missingResult = default(OwnedResult[OwnedReport])
assert missingResult.error == OwnershipError.Uninitialized
# Numeric evidence stays outside the platform-independent success marker.
recordArcRelease("report_snapshots", 1000, beforeRelease, afterRelease)
echo "REPORT_ARC_RELEASE cycles=1000 unchanged"
echo "Report snapshots: retained replacements, escaped inputs, copied metadata and atomic errors passed"
