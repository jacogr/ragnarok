# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_guarantee_arc_release"}

## Source-bound full-report signing bytes, bounded work, backend refusals and ARC lifetime.

import std/[assertions, syncio]
import ../../../src/state/[computed_report, computed_guarantee]
import ../../../src/codec/bounded
import ../../../src/crypto/guarantee
import ../../support/[pvm_computed_report, pvm_computed_report_vectors, pvm_computed_guarantee, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive observations or refuse only after full original source preparation.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe real Blake attempts through the maintained test bridge.
proc expect[T](outcome: ComputedGuaranteeResult[T], reason: ComputedGuaranteeError) =
  ## Compare exact alternatives before any guarded payload access.
  assert outcome.error == reason, "computed guarantee reason"
proc verify(kind: int, expected: openArray[byte], hash: array[32,
    byte]): ComputedGuaranteeTranscript =
  ## Independent complete wire witnesses bind the expected transcript to the actual original computed report.
  let report = prepareComputedReport(computedAvailability(kind), ByteLimit(100000)).value
  assert report.computedReportBytes.value == @expected, "independent complete report wire"
  let length = report.computedReportInfo.value.length
  reset(0)
  let done = prepareComputedGuarantee(report, ByteLimit(length+45))
  expect(done, ComputedGuaranteeError.None)
  assert hashes() == 1, "one hash of complete canonical report"
  let transcript = done.value
  assert array[45, byte](transcript.computedGuaranteeMessage.value) == expectedGuarantee(hash), "independent domain/full-report hash"
  assert transcript.computedGuaranteeReport.value.computedReportBytes.value == @expected, "retained original report"
  reset(0)
  expect(prepareComputedGuarantee(report, ByteLimit(length+44)),
      ComputedGuaranteeError.LimitExceeded)
  expect(prepareComputedGuarantee(report, ByteLimit(44)), ComputedGuaranteeError.LimitExceeded)
  expect(prepareComputedGuarantee(report, ByteLimit(0)), ComputedGuaranteeError.LimitExceeded)
  assert hashes() == 0, "policy preflight precedes hashing"
  expect(prepareComputedGuarantee(report, ByteLimit(high(uint64))), ComputedGuaranteeError.None)
  assert hashes() == 1, "maximum policy needs no wrapping sum"
  transcript
let empty = verify(0, EmptyReport, EmptyHash)
discard verify(1, SingleReport, SingleHash)
discard verify(3, MixedReport, MixedHash)
discard verify(65, PagedReport, PagedHash)
let context = verify(4, ContextReport, ContextHash)
let report = context.computedGuaranteeReport.value
let exact = report.computedReportInfo.value.length+45
# Both extracted fixed bytes and a separate report-wire copy are isolated from the retained transcript.
var copied = array[45, byte](context.computedGuaranteeMessage.value)
copied[0] = 0
var wire = context.computedGuaranteeReport.value.computedReportBytes.value
wire[0] = wire[0] xor 1
assert array[45, byte](context.computedGuaranteeMessage.value) == expectedGuarantee(ContextHash), "fixed copy isolation"
assert context.computedGuaranteeReport.value.computedReportBytes.value == @ContextReport, "original wire isolation"
expect(default(ComputedGuaranteeResult[ComputedGuaranteeTranscript]),
    ComputedGuaranteeError.Uninitialized)
expect(default(ComputedGuaranteeTranscript).computedGuaranteeMessage,
    ComputedGuaranteeError.Uninitialized)
expect(default(ComputedGuaranteeTranscript).computedGuaranteeReport,
    ComputedGuaranteeError.Uninitialized)
reset(1)
expect(prepareComputedGuarantee(default(ComputedWorkReport), ByteLimit(0)),
    ComputedGuaranteeError.InvalidSource)
expect(prepareComputedGuarantee(default(ComputedWorkReport), ByteLimit(high(uint64))),
    ComputedGuaranteeError.InvalidSource)
expect(prepareComputedGuarantee(report, ByteLimit(exact-1)), ComputedGuaranteeError.LimitExceeded)
assert hashes() == 0, "invalid source and short budget never reach backend"
expect(prepareComputedGuarantee(report, ByteLimit(exact)), ComputedGuaranteeError.BackendFailure)
assert hashes() == 1, "one refused backend attempt"
assert array[45, byte](empty.computedGuaranteeMessage.value) == expectedGuarantee(EmptyHash), "existing transcript survives backend failure"
assert array[45, byte](context.computedGuaranteeMessage.value) == expectedGuarantee(ContextHash), "existing context survives backend failure"
reset(0)
assert array[45, byte](prepareComputedGuarantee(report, ByteLimit(
    exact)).value.computedGuaranteeMessage.value) == expectedGuarantee(ContextHash), "backend recovery"
assert hashes() == 1, "one fresh recovered attempt"
proc detached(): ComputedGuaranteeTranscript =
  ## The transcript owns the original report after every source-preparation temporary retires.
  let original = prepareComputedReport(computedAvailability(0), ByteLimit(100000)).value
  prepareComputedGuarantee(original, ByteLimit(100000)).value
let retained = detached()
assert retained.computedGuaranteeReport.value.computedReportBytes.value == @EmptyReport, "detached original lifetime"
assert array[45, byte](retained.computedGuaranteeMessage.value) == expectedGuarantee(EmptyHash), "detached message lifetime"
proc cycle() =
  ## Release successful owners, temporary wire copies and failed candidates within each warmed iteration.
  reset(0)
  let done = prepareComputedGuarantee(report, ByteLimit(exact)).value
  assert array[45, byte](done.computedGuaranteeMessage.value) == expectedGuarantee(ContextHash)
  expect(prepareComputedGuarantee(report, ByteLimit(exact-1)), ComputedGuaranteeError.LimitExceeded)
  reset(1)
  expect(prepareComputedGuarantee(report, ByteLimit(exact)), ComputedGuaranteeError.BackendFailure)
  reset(0)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "computed guarantee ARC release"
recordArcRelease("pvm_computed_guarantee", 1000, before, after)
echo "PVM computed guarantee passed"
echo "ARC_RELEASE cycles=1000 unchanged"
