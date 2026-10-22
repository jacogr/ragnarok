# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_report_results_arc_release"}

## Original multi-item guests verify ordered report I, protocol precedence, source ownership and atomic local refusal.

import std/[assertions, syncio]
import ../../../src/state/[refinement_report, refinement_bootstrap, refinement_outcome, refinement_dispatch]
import ../../../src/pvm/[host_fetch, refinement_exports, output, step, initialize, machine]
import ../../../src/codec/[bounded, composite, work_package, work_digest, work_report]
import ../../support/[pvm_report_results, pvm_refinement_outcome, arc_evidence]

let halt = @[50'u8, 0]
let returning = @[refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
let exporting = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8],
  refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
proc check(report: RefinedPackage, index: uint64, kind: WorkKind, offset,
    declared: uint64): RefinedWorkItem =
  ## Assert independently expected selection/source identity and every replacement segment's full content.
  let selected = report.reportItem(FetchItemIndex(index)).value
  let info = selected.refinedInfo.value
  assert info.kind == kind and uint64(info.offset) == offset and uint64(info.exports) == declared,
      "item " & $index & " kind " & $info.kind & " expected " & $kind
  assert uint64(info.item) == index and uint32(info.service) == uint32(42+index)
  assert uint32(selected.refinedSource.value.workItemInfo.value.service) == uint32(42+index)
  if kind == WorkKind.Success:
    assert selected.refinedOutput.value == @[21'u8, 22, 23]
    assert info.outputBytes == 3
  else:
    assert selected.refinedOutput.error == RefinementReportError.NotSuccess and info.outputBytes == 0
    for position in 0..<int(declared):
      let segment = array[4104, byte](selected.refinedSegment(ExportCount(uint64(position))).value)
      for octet in segment: assert octet == 0 # Check all zero bytes, not only an empty prefix.
  assert selected.refinedSegment(ExportCount(declared)).error == RefinementReportError.InvalidIndex
  assert selected.refinedSegment(ExportCount(high(uint64))).error ==
      RefinementReportError.InvalidIndex
  selected
let pair = reportFixture([reportGuest(returning), reportGuest(exporting, 1)])
let complete = reportRun(pair, []).value
let first = check(complete, 0, WorkKind.Success, 0, 0)
let second = check(complete, 1, WorkKind.Success, 0, 1)
let segment = array[4104, byte](second.refinedSegment(ExportCount(0)).value)
assert segment[0] == 11 and segment[1] == 12 and segment[2] == 13
for index in 3..<4104: assert segment[index] == 0
assert complete.reportInfo.value.items == 2 and uint64(complete.reportInfo.value.exports) == 1
assert complete.reportInfo.value.blobBytes == 6 and uint64(complete.reportInfo.value.core) == 5
assert uint64(second.refinedInfo.value.gasUsed) > 3521, "export gas " & $uint64(
    second.refinedInfo.value.gasUsed)
# Exact protocol budget is accepted; one byte over rejects only the later successful blob.
for traceBytes in [49145, 49146, 49147]:
  let trace = newSeq[byte](traceBytes)
  let report = reportRun(pair, trace).value
  discard check(report, 0, WorkKind.Success, 0, 0)
  let kind = if traceBytes == 49147: WorkKind.Oversize else: WorkKind.Success
  discard check(report, 1, kind, 0, 1)
  assert report.reportInfo.value.blobBytes == uint64(traceBytes+3+(if kind ==
      WorkKind.Success: 3 else: 0))
# A single real readable output can reach or exceed the entire report budget without a trace.
for size in [49152, 49153]:
  var guest = reportGuest([refinementImmediate(7, 196608), refinementImmediate(8, uint64(size)), halt])
  guest.writable = newSeq[byte](size)
  guest.writable[0] = 91
  var cap = reportLimits()
  cap.bootstrap.initialization.envelope = InitializationByteLimit(65536)
  cap.bootstrap.initialization.pages = PageLimit(16)
  cap.invocation.output = OutputByteLimit(65536)
  let result = reportRun(reportFixture([guest]), [], cap).value
  let item = result.reportItem(FetchItemIndex(0)).value
  assert item.refinedInfo.value.kind == (if size ==
      49152: WorkKind.Success else: WorkKind.Oversize), "output boundary " & $size & " kind " &
      $item.refinedInfo.value.kind
  if size == 49152:
    assert item.refinedOutput.value.len == size and item.refinedOutput.value[0] == 91
    assert result.reportInfo.value.blobBytes == 49152
  else:
    assert item.refinedOutput.error == RefinementReportError.NotSuccess
    assert result.reportInfo.value.blobBytes == 0 # No rejected raw payload survives in the report owner.
# Oversize wins over mismatched exports; discarded output consumes no shared budget for later guests.
let mismatch = reportFixture([reportGuest(returning, 2), reportGuest(returning)])
let oversized = reportRun(mismatch, newSeq[byte](49150)).value
let badSize = check(oversized, 0, WorkKind.Oversize, 0, 2)
discard check(oversized, 1, WorkKind.Oversize, 2, 0)
let rejected = reportRun(mismatch, newSeq[byte](49149)).value
let badCount = check(rejected, 0, WorkKind.BadExports, 0, 2)
discard check(rejected, 1, WorkKind.Success, 2, 0)
assert rejected.reportInfo.value.blobBytes == 49152
assert uint64(badSize.refinedInfo.value.gasUsed) == uint64(badCount.refinedInfo.value.gasUsed)
# Both under- and over-declaration replace exports; prior actual segments never escape the rejected item.
for declared in [0'u64, 2]:
  discard check(reportRun(reportFixture([reportGuest(exporting, declared)]), []).value,
    0, WorkKind.BadExports, 0, declared)
# BAD/BIG/panic/OOG retain gas semantics; export mismatch takes precedence over those work errors.
for variant in 0..<4:
  let guest = if variant == 0: reportGuest(returning, missing = true)
    elif variant == 1: reportGuest(returning, oversized = true)
    elif variant == 2: reportGuest([@[0'u8]]) else: reportGuest(returning, credit = 0)
  let expected = if variant == 0: WorkKind.Bad elif variant == 1: WorkKind.Big
    elif variant == 2: WorkKind.Panic else: WorkKind.OutOfGas
  let report = reportRun(reportFixture([guest]), []).value
  let item = check(report, 0, expected, 0, 0)
  if variant != 2: assert uint64(item.refinedInfo.value.gasUsed) == 0
  var mismatched = guest
  mismatched.declared = 1
  discard check(reportRun(reportFixture([mismatched]), []).value, 0, WorkKind.BadExports, 0, 1)
# An error after exporting discards actual segments, then report I substitutes the declaration's zeros.
let panic = @[exporting[0], exporting[1], exporting[2], @[0'u8]]
discard check(reportRun(reportFixture([reportGuest(panic, 1)]), []).value, 0, WorkKind.BadExports, 0, 1)
# Return the actual host export index through guest memory: skipped declarations still advance the offset.
let indexGuest = @[exporting[0], exporting[1], exporting[2], @[62'u8, 7, 0, 0, 3, 0],
  refinementImmediate(7, 196608), refinementImmediate(8, 8), halt]
let boundary = reportRun(reportFixture([reportGuest(returning, 3071, missing = true),
  reportGuest(indexGuest, 1)]), []).value
let indexed = boundary.reportItem(FetchItemIndex(1)).value
assert indexed.refinedInfo.value.kind == WorkKind.Success
assert uint64(indexed.refinedInfo.value.offset) == 3071
assert indexed.refinedOutput.value == @[255'u8, 11, 0, 0, 0, 0, 0,
    0] # E8(3071), not the number actually exported earlier.
assert uint64(boundary.reportInfo.value.exports) == 3072
let full = reportRun(reportFixture([reportGuest(returning, 3072, missing = true), reportGuest(
    indexGuest)]), []).value
assert full.reportItem(FetchItemIndex(1)).value.refinedOutput.value == @[251'u8, 255, 255, 255, 255,
    255, 255, 255]
# Zero-length output at an exactly exhausted report budget remains a genuine Success.
let empty = reportRun(reportFixture([reportGuest([refinementImmediate(8, 0), halt])]), newSeq[byte](49152)).value
assert empty.reportItem(FetchItemIndex(0)).value.refinedInfo.value.kind == WorkKind.Success
assert empty.reportInfo.value.blobBytes == 49152
# Independent local limits refuse atomically; protocol selection never disguises local policy exhaustion.
assert reportRun(pair, newSeq[byte](49153)).error == RefinementReportError.InvalidTrace
for policy in 0..<6:
  var cap = reportLimits()
  case policy
  of 0: cap.items = ElementLimit(1)
  of 1: cap.exports = ElementLimit(0)
  of 2: cap.blobs = ByteLimit(5)
  of 3: cap.bootstrap.preimage = ByteLimit(0)
  of 4: cap.invocation.output = OutputByteLimit(2)
  else: cap.invocation.steps = ExecutionStepLimit(0)
  let refused = reportRun(pair, [], cap)
  if policy < 3:
    assert refused.error == RefinementReportError.LimitExceeded
  elif policy == 3:
    assert refused.error == RefinementReportError.BootstrapFailure
    assert refused.bootstrapError == RefinementBootstrapError.LimitExceeded
  else:
    assert refused.error == RefinementReportError.InvocationFailure
    assert refused.invocationError.error == (if policy == 4: RefinementInvocationError.LimitExceeded
      else: RefinementInvocationError.ExecutionFailure)
# Select current memory compilation explicitly so the nonempty zero-byte-policy witness reaches its intended local refusal.
let late = reportFixture([reportGuest(returning), reportGuest([refinementImmediate(7, 0),
    refinementImmediate(8, 65536), refinementImmediate(9, 1), @[10'u8, 9], halt])])
let lateFailure = reportRun(late, [])
assert lateFailure.error == RefinementReportError.InvocationFailure,
    "nonempty compile exceeds the zero program-byte policy: " & $lateFailure.error
assert lateFailure.invocationError.error == RefinementInvocationError.HostFailure
assert lateFailure.invocationError.hostError == RefinementDispatchError.LimitExceeded
assert reportRun(default(ReportFixture), []).error == RefinementReportError.InvalidPackage
assert complete.reportItem(FetchItemIndex(high(uint64))).error == RefinementReportError.InvalidIndex
assert default(RefinedPackage).reportInfo.error == RefinementReportError.Uninitialized
assert default(RefinedPackage).reportTrace.error == RefinementReportError.Uninitialized
assert default(RefinedPackage).reportPackage.error == RefinementReportError.Uninitialized
assert default(RefinedPackage).reportItem(FetchItemIndex(0)).error ==
    RefinementReportError.Uninitialized
assert default(RefinedWorkItem).refinedInfo.error == RefinementReportError.Uninitialized
assert default(RefinedWorkItem).refinedSource.error == RefinementReportError.Uninitialized
assert default(RefinedWorkItem).refinedOutput.error == RefinementReportError.Uninitialized
assert default(RefinedWorkItem).refinedSegment(ExportCount(0)).error ==
    RefinementReportError.Uninitialized
# Copied bytes/metadata/segments and dropped caller handles cannot alter replay or retained source identity.
var changed = second.refinedOutput.value
changed[0] = 255
var copiedInfo = second.refinedInfo.value
copiedInfo.kind = WorkKind.Bad
var changedSegment = array[4104, byte](second.refinedSegment(ExportCount(0)).value)
changedSegment[0] = 255
assert second.refinedOutput.value[0] == 21
assert array[4104, byte](second.refinedSegment(ExportCount(0)).value)[0] == 11
var traced = @[1'u8, 2, 3]
let saved = reportRun(pair, traced).value
traced[0] = 255
var extracted = saved.reportTrace.value
extracted[1] = 255
assert saved.reportTrace.value == @[1'u8, 2, 3]
assert uint64(saved.reportPackage.value.workItemAt(1).value.workItemInfo.value.exports) == 1
proc detachedItem(): RefinedWorkItem =
  ## Drop all original caller/map/report handles while retaining an extracted source-bound item.
  let fixture = reportFixture([reportGuest(exporting, 1)])
  reportRun(fixture, []).value.reportItem(FetchItemIndex(0)).value
let detached = detachedItem()
assert detached.refinedOutput.value == @[21'u8, 22, 23]
assert uint32(detached.refinedSource.value.workItemInfo.value.service) == 42
discard check(reportRun(pair, []).value, 1, WorkKind.Success, 0,
    1) # Replaying original sources remains deterministic.
proc cycle() =
  ## Release new source maps, package/code CPUs, successful/exported and rejected private-prefix results each time.
  let fresh = reportFixture([reportGuest(returning, 1), reportGuest(exporting, 1)])
  let result = reportRun(fresh, []).value
  discard check(result, 0, WorkKind.BadExports, 0, 1)
  discard check(result, 1, WorkKind.Success, 1, 1)
  var cap = reportLimits()
  cap.blobs = ByteLimit(2)
  assert reportRun(fresh, [], cap).error == RefinementReportError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_report_results", 1000, before, after)
echo "PVM report results passed"
echo "ARC_RELEASE cycles=1000 unchanged"
