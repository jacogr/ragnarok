# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_continuation_arc_release"}

## Actual initial gas releases reserved capacity for a bounded original-queue report suffix.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../support/state_accumulation_execution_context
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# No continuation query or gas-prefix planning is permitted to hash or execute again.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

# Capture uniquely identified parent-ready reports with independent unsigned gas values.
proc queued(base: OwnedReport, ordinal: byte, gases: openArray[uint64]): ReadyItem =
  let source = reportBytes(reportFor(base, 0, gases))
  var report = decodeReportBorrowed(source, 2).value
  report.header.packageHash.bytes[0] = ordinal
  var wire = newSeq[byte](source.len+10000)
  let written = encodeReportBorrowed(report, source, 2, wire)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(wire.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

# Sign the complete ready ring, then execute two real checkpoint/panic services against the resulting round.
proc source(base: OwnedReport, reports: ReadyRow, allowance = 208'u64,
    extraBudget = 0'u64, skip = false): CompletedBlockAccumulation =
  let ending = (if skip: ExecutionEnding.Missing else: ExecutionEnding.Panic)
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = ending
  executionOptions0.second = ending
  executionOptions0.allowanceGas = allowance
  executionOptions0.signed.ready = reports
  var fixture = executionFixture(base, executionOptions0)
  var config = executionRoundConfig()
  config.blockGas = Gas(allowance*2+extraBudget) # Tiny authored values are fixed before capture, not untrusted arithmetic.
  fixture.round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value, config).value
  if skip:
    completeBlockAccumulation(fixture.round, [], [executionSkip(fixture, 0), executionSkip(fixture,
        1)], executionLimits()).value
  else:
    completeBlockAccumulation(fixture.round, [executionGuest(fixture, 0), executionGuest(fixture,
        1)], [], executionLimits()).value

# Inspection ceilings are distinct from affordable report count and digest count.
proc limits(executions = 2'u64, reports = 8'u64, digests = 8'u64): AccumulationContinuationLimits =
  AccumulationContinuationLimits(executions: ElementLimit(executions), reports: ElementLimit(
      reports), digests: ElementLimit(digests))

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let first = queued(base, 64, [10'u64])
  let second = queued(base, 65, [11'u64])
  let zero = queued(base, 66, [0'u64])
  let completed = source(base, @[first, second, zero])
  assert uint64(completed.executionInfo.value.round.prefix) == 0
  assert uint64(completed.executionInfo.value.round.allowanceGas) == 416
  assert uint64(completed.executionInfo.value.gasUsed) == 406
  failHash(3)
  let plan = planAccumulationContinuation(completed, limits(reports = 2, digests = 2)).value
  let info = plan.continuationInfo.value
  assert uint64(info.completedPrefix) == 0 and info.pendingReports == 3
  assert uint64(info.budget) == 10 and uint64(info.reportGas) == 10
  assert uint64(info.prefix) == 1 and info.dispatch # Reserved allowances would incorrectly leave zero budget.
  assert ownedReportInfo(plan.continuationReportAt(ContinuationReportIndex(
      0)).value).value.header.packageHash.bytes[0] == 64
  assert plan.continuationReportAt(ContinuationReportIndex(1)).error ==
      AccumulationContinuationError.InvalidIndex
  assert plan.continuationReportAt(ContinuationReportIndex(high(uint64))).error ==
      AccumulationContinuationError.InvalidIndex
  assert sameAccumulationInputs(plan.continuationSource.value.executionRound.value.roundProjection.value.roundInputs.value,
    completed.executionRound.value.roundProjection.value.roundInputs.value)
  var copied = info
  copied.budget = Gas(99)
  copied.prefix = AccumulationReportPrefix(3)
  assert uint64(plan.continuationInfo.value.budget) == 10 and uint64(
      plan.continuationInfo.value.prefix) == 1
  assert planAccumulationContinuation(completed, limits(executions = 1)).error ==
      AccumulationContinuationError.LimitExceeded
  assert planAccumulationContinuation(completed, limits(reports = 1)).error ==
      AccumulationContinuationError.LimitExceeded
  assert planAccumulationContinuation(completed, limits(digests = 1)).error ==
      AccumulationContinuationError.LimitExceeded
  # Default successes/owners cannot impersonate an initialized stopped plan or original admitted queue.
  let invalid = default(CompletedBlockAccumulation)
  assert planAccumulationContinuation(invalid, limits()).error ==
      AccumulationContinuationError.InvalidSource
  let defaultPlan = default(PreparedAccumulationContinuation)
  assert defaultPlan.continuationInfo.error == AccumulationContinuationError.Uninitialized
  assert defaultPlan.continuationSource.error == AccumulationContinuationError.Uninitialized
  assert defaultPlan.continuationReportAt(ContinuationReportIndex(0)).error ==
      AccumulationContinuationError.Uninitialized
  let defaultResult = default(AccumulationContinuationResult[PreparedAccumulationContinuation])
  assert defaultResult.error == AccumulationContinuationError.Uninitialized
  failHash(0)
  let offset = source(base, @[first, second, zero], extraBudget = 10)
  assert uint64(offset.executionInfo.value.round.prefix) == 1
  failHash(3)
  let offsetPlan = planAccumulationContinuation(offset, limits(reports = 2, digests = 2)).value
  let offsetInfo = offsetPlan.continuationInfo.value
  assert uint64(offsetInfo.completedPrefix) == 1 and offsetInfo.pendingReports == 2
  assert uint64(offsetInfo.budget) == 20 and uint64(offsetInfo.prefix) == 2
  assert uint64(offsetInfo.reportGas) == 11
  assert ownedReportInfo(offsetPlan.continuationReportAt(ContinuationReportIndex(
      0)).value).value.header.packageHash.bytes[0] == 65
  assert ownedReportInfo(offsetPlan.continuationReportAt(ContinuationReportIndex(
      1)).value).value.header.packageHash.bytes[0] == 66
  # A zero-cost suffix fits after the last affordable positive-cost report.
  failHash(0)
  let freeTail = source(base, @[first, zero])
  failHash(3)
  let freePlan = planAccumulationContinuation(freeTail, limits()).value
  assert uint64(freePlan.continuationInfo.value.prefix) == 2
  assert uint64(freePlan.continuationInfo.value.reportGas) == 10
  failHash(0)
  let blocked = source(base, @[first, zero], allowance = 207)
  failHash(3)
  let blockedInfo = planAccumulationContinuation(blocked, limits(reports = 1,
      digests = 1)).value.continuationInfo.value
  assert uint64(blockedInfo.budget) == 8 and uint64(blockedInfo.prefix) == 0
  assert uint64(blockedInfo.reportGas) == 0 and not blockedInfo.dispatch # Later zero-cost work cannot bypass the unaffordable head.
  failHash(0)
  let exhausted = source(base, @[first, zero], allowance = 203)
  failHash(3)
  let exhaustedInfo = planAccumulationContinuation(exhausted, limits()).value.continuationInfo.value
  assert uint64(exhaustedInfo.budget) == 0 and not exhaustedInfo.dispatch
  failHash(0)
  let huge = queued(base, 67, [5'u64, high(uint64)])
  let hugeSource = source(base, @[huge, zero])
  failHash(3)
  let hugePlan = planAccumulationContinuation(hugeSource, limits(reports = 1, digests = 2)).value
  assert uint64(hugePlan.continuationInfo.value.prefix) == 0
  assert uint64(hugePlan.continuationInfo.value.reportGas) ==
      0 # Earlier affordable digests of a rejected report are not reserved.
  assert planAccumulationContinuation(hugeSource, limits(digests = 1)).error ==
      AccumulationContinuationError.LimitExceeded
  failHash(0)
  let skipped = source(base, @[first, second, zero], skip = true)
  failHash(3)
  let skipInfo = planAccumulationContinuation(skipped, limits(
      executions = 0)).value.continuationInfo.value
  assert uint64(skipInfo.budget) == 416 and uint64(skipInfo.prefix) == 3
  assert uint64(skipInfo.reportGas) == 21 # Unused free allowances are absent from recursive reservations.
  failHash(0)
  let done = source(base, @[first], extraBudget = 10)
  failHash(3)
  let doneInfo = planAccumulationContinuation(done, limits(reports = 0,
      digests = 0)).value.continuationInfo.value
  assert doneInfo.pendingReports == 0 and not doneInfo.dispatch
  assert uint64(doneInfo.completedPrefix) == 1 and uint64(doneInfo.prefix) == 0
  failHash(0)
  var executionOptions1 = executionFixtureConfig()
  executionOptions1.empty = true
  let emptyFixture = executionFixture(base, executionOptions1)
  let empty = completeBlockAccumulation(emptyFixture.round, [], [], executionLimits(0)).value
  failHash(3)
  let emptyInfo = planAccumulationContinuation(empty, limits(executions = 0, reports = 0,
      digests = 0)).value.continuationInfo.value
  assert emptyInfo.pendingReports == 0 and not emptyInfo.dispatch
  failHash(0)
  var retained: PreparedAccumulationContinuation
  block:
    let local = source(base, @[first, zero])
    retained = planAccumulationContinuation(local, limits()).value
  assert uint64(retained.continuationInfo.value.prefix) == 2
  assert ownedReportInfo(retained.continuationReportAt(ContinuationReportIndex(
      0)).value).value.header.packageHash.bytes[0] == 64
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Complete and late-refused plans release their exact admitted source/queue without retaining report copies.
    let prepared = planAccumulationContinuation(completed, limits(reports = 2, digests = 2)).value
    assert uint64(prepared.continuationInfo.value.prefix) == 1
    assert planAccumulationContinuation(completed, limits(reports = 1)).error ==
        AccumulationContinuationError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_continuation", 1000, before, after)
  echo "Accumulation continuation prefix passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected exceptions remain unsuccessful native executions.
except:
  quit(2)
