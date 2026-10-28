# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_links_arc_release"}

## Genuine importer/exporter correspondence, exact ordinal binding, all-or-nothing failure and immutable lifetime.

import std/assertions
import std/syncio
import ../../../src/state/computed_links as state_computed_links
import ../../../src/state/computed_guarantee as state_computed_guarantee
import ../../../src/state/computed_report as state_computed_report
import ../../../src/state/report_identity as state_report_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/crypto/guarantee as crypto_guarantee
import ../../support/pvm_computed_links
import ../../support/pvm_computed_report
import ../../support/pvm_computed_report_vectors
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all new hashes only after real source preparation to prove the relation check repeats no work.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual primitive attempts rather than manufacturing successful commitments.
proc expect[T](outcome: ComputedLinksResult[T], reason: ComputedLinksError) =
  ## Check the precise alternative without extracting a failed candidate or accepted prefix.
  assert outcome.error == reason, "computed links reason"
let original = prepareComputedReport(computedAvailability(1), ByteLimit(100000)).value
assert original.computedReportBytes.value == @SingleReport, "independent complete exporter report"
let transcript = linksConsumer([linksPair(original)], repeat = true)
let one = prepareComputedLinks(transcript, [original], ElementLimit(1)).value
assert one.computedLinkCount.value == 1, "repeated and direct imports reuse the unique package lookup"
assert one.computedLinkWitness(ReportLookupIndex(0)).value.computedReportBytes.value ==
    @SingleReport, "exact original exporter"
assert array[45, byte](one.computedLinkSource.value.computedGuaranteeMessage.value) ==
  array[45, byte](transcript.computedGuaranteeMessage.value), "original exact transcript retained"
# Genuine zero-key sources succeed only with an initialized transcript and an exact empty witness table.
let emptyReport = prepareComputedReport(computedAvailability(0), ByteLimit(100000)).value
let emptySource = prepareComputedGuarantee(emptyReport, ByteLimit(100000)).value
let empty = prepareComputedLinks(emptySource, [], ElementLimit(0)).value
assert empty.computedLinkCount.value == 0, "explicit successful empty relation"
expect(empty.computedLinkWitness(ReportLookupIndex(0)), ComputedLinksError.InvalidIndex)
expect(prepareComputedLinks(emptySource, [original], ElementLimit(0)),
    ComputedLinksError.InvalidShape)
expect(prepareComputedLinks(transcript, [], ElementLimit(0)), ComputedLinksError.InvalidShape)
expect(prepareComputedLinks(transcript, [original, original], ElementLimit(8)),
    ComputedLinksError.InvalidShape)
expect(prepareComputedLinks(transcript, [default(ComputedWorkReport)], ElementLimit(0)),
    ComputedLinksError.LimitExceeded)
expect(prepareComputedLinks(transcript, [default(ComputedWorkReport)], ElementLimit(1)),
    ComputedLinksError.InvalidWitness)
expect(prepareComputedLinks(default(ComputedGuaranteeTranscript), [], ElementLimit(0)),
    ComputedLinksError.InvalidSource)
expect(default(ComputedLinksResult[ComputedReportLinks]), ComputedLinksError.Uninitialized)
expect(default(ComputedReportLinks).computedLinkCount, ComputedLinksError.Uninitialized)
expect(default(ComputedReportLinks).computedLinkSource, ComputedLinksError.Uninitialized)
expect(default(ComputedReportLinks).computedLinkWitness(ReportLookupIndex(0)),
    ComputedLinksError.Uninitialized)
expect(one.computedLinkWitness(ReportLookupIndex(1)), ComputedLinksError.InvalidIndex)
expect(one.computedLinkWitness(ReportLookupIndex(high(uint64))), ComputedLinksError.InvalidIndex)
let exporters = linksExporters(8)
let pairs = linksPairs(exporters)
let source = linksConsumer(pairs)
let full = prepareComputedLinks(source, exporters, ElementLimit(8)).value
assert full.computedLinkCount.value == 8, "maximum eight canonical unique keys"
# Every retained ordinal must be the precise witness for its original canonical dictionary pair.
for index in 0..<8:
  let header = full.computedLinkWitness(ReportLookupIndex(uint64(
      index))).value.computedReportInfo.value.header
  assert header.packageHash.bytes == pairs[index].packageHash.bytes, "original canonical key"
  assert header.segmentRoot.bytes == pairs[index].segmentRoot.bytes, "original exact associated root"
  if index > 0: assert linksLess(exporters[index-1], exporters[index]), "strict canonical test inputs"
expect(prepareComputedLinks(source, exporters, ElementLimit(7)), ComputedLinksError.LimitExceeded)
expect(prepareComputedLinks(source, exporters, ElementLimit(high(uint64))), ComputedLinksError.None)
var replaced = exporters
replaced[7] = default(ComputedWorkReport)
expect(prepareComputedLinks(source, replaced, ElementLimit(8)), ComputedLinksError.InvalidWitness)
replaced[7] = exporters[0]
expect(prepareComputedLinks(source, replaced, ElementLimit(8)), ComputedLinksError.PackageMismatch)
replaced[0] = exporters[1]
expect(prepareComputedLinks(source, replaced, ElementLimit(8)), ComputedLinksError.PackageMismatch)
# A valid inclusion proof for another root does not establish that root as this package's computed exports.
var wrongPairs = pairs
wrongPairs[7] = linksPair(exporters[7], wrongRoot = true)
let wrongSource = linksConsumer(wrongPairs)
expect(prepareComputedLinks(wrongSource, exporters, ElementLimit(8)),
    ComputedLinksError.RootMismatch)
# Replacing the caller's last handle after success cannot replace the retained successful witness or transcript.
assert full.computedLinkWitness(ReportLookupIndex(
    7)).value.computedReportInfo.value.header.packageHash.bytes == pairs[7].packageHash.bytes, "caller list replacement isolation"
reset(1)
expect(prepareComputedLinks(source, exporters, ElementLimit(8)), ComputedLinksError.None)
expect(prepareComputedLinks(wrongSource, exporters, ElementLimit(8)),
    ComputedLinksError.RootMismatch)
expect(prepareComputedLinks(source, replaced, ElementLimit(8)), ComputedLinksError.PackageMismatch)
assert hashes() == 0, "relation validation performs no new hashing"
reset(0)
proc detached(): ComputedReportLinks =
  ## Retain original importer transcript and exporter after every fixture-preparation local retires.
  let exporter = linksExporter(42)
  let source = linksConsumer([linksPair(exporter)])
  prepareComputedLinks(source, [exporter], ElementLimit(1)).value
let retained = detached()
assert retained.computedLinkCount.value == 1, "detached owner count"
assert retained.computedLinkWitness(ReportLookupIndex(
    0)).value.computedReportInfo.value.header.segmentRoot.bytes == pairs[0].segmentRoot.bytes, "detached exporter lifetime"
let rejected = replaced # Freeze caller replacements before repeated scoped validation.
proc cycle() =
  ## Complete and retire fixed acyclic ownership, including candidates refused after a valid seven-entry prefix.
  let done = prepareComputedLinks(source, exporters, ElementLimit(8)).value
  assert done.computedLinkCount.value == 8
  discard done.computedLinkWitness(ReportLookupIndex(7)).value
  discard done.computedLinkSource.value
  expect(prepareComputedLinks(wrongSource, exporters, ElementLimit(8)),
      ComputedLinksError.RootMismatch)
  expect(prepareComputedLinks(source, rejected, ElementLimit(8)),
      ComputedLinksError.PackageMismatch)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "computed links ARC release"
recordArcRelease("pvm_computed_links", 1000, before, after)
echo "PVM computed links passed"
echo "ARC_RELEASE cycles=1000 unchanged"
