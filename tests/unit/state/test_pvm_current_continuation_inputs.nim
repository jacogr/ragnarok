# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_continuation_inputs_arc_release"}

## Genuine current completion selects next reports, holds supervised incoming credit and never repeats free allowances.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, composite, report_owned, work_digest]
import ../../../src/state/[accumulation_current_sequence, accumulation_current_round,
  accumulation_block_guests, accumulation_round, accumulation_queue, accumulation_coverage,
  accumulation_inputs, accumulation_operands, accumulation_transfer_partition, store]
import ../../support/[accumulation_execution_context, accumulation_current_round_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(): CurrentContinuationLimits =
  ## Small finite ceilings include the affordable report, its digest and one held transfer classification.
  let base = executionRoundConfig()
  CurrentContinuationLimits(reports: ElementLimit(2), digests: ElementLimit(4),
      operands: base.operands,
    inputs: base.inputs, partition: TransferPartitionLimits(transfers: ElementLimit(2),
        services: ElementLimit(2), checks: ElementLimit(64)))
proc initial(base: OwnedReport, empty = false): PreparedCurrentAccumulationRound =
  ## Initial free allowances exhaust declared200000 gas; actual guests leave room for the previously available report.
  var options = executionFixtureConfig()
  options.signed.withAvailable = true
  options.empty = empty
  if not empty:
    options.firstProgram = currentTransferProgram(99)
    options.secondSupervisor = 42 # The next active report42 prevents concurrent incoming junior credit.
  let fixture = executionFixture(base, options)
  var config = executionRoundConfig()
  config.blockGas = Gas(if empty: 0 else: 200000)
  let round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value, config).value
  assert uint64(round.roundProjection.value.roundInfo.value.prefix) == 0, "initial report excluded by declared allowance reservation"
  let completed = runCurrentBlockAccumulationRound(round, currentRoundParameters(),
      currentRoundLimits())
  assert completed.error == CurrentAccumulationRoundError.None, $completed.error
  completed.value
proc main() {.raises.} =
  ## Maintained cryptographic fixture admission supplies the original queue; no caller-supplied report/source map grants authority.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve the exact binary report fixture.
  let base = decodeOwnedReport(wire, 2).value
  let completed = initial(base)
  let started = startCurrentAccumulationSequence(completed)
  assert started.error == CurrentSequenceError.None, $started.error
  let source = started.value
  let summary = source.currentSequenceInfo.value
  assert summary.entries == 1 and summary.pending == 1 and uint64(summary.processedReports) == 0
  let prior = source.currentSequenceLatestState.value
  failHash(1)
  let prepared = planCurrentAccumulationContinuation(source, policy())
  assert prepared.error == CurrentSequenceError.None, $prepared.error
  assert hashCalls() == 0, "planning selects/partitions existing state without guest execution or hashing"
  failHash(0)
  let plan = prepared.value
  let info = plan.currentContinuationInfo.value
  assert uint64(info.start) == 0 and uint64(info.prefix) == 1 and info.pendingReports == 1
  assert info.accepted == 0 and info.queued == 1 and info.services == 1 and info.dispatch
  assert uint64(info.reportGas) == 10
  let inputs = plan.currentContinuationInputs.value
  assert inputs.invocationServiceCount.value == 1, "initial free99 allowance never recurs"
  let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert uint32(service.service) == 42 and uint64(service.gas) == 10
  assert service.operands == 1 and service.transfers == 0
  assert sameStateSnapshot(plan.currentContinuationState.value, prior)
  assert sameStateSnapshot(plan.currentContinuationPartition.value.partitionPrior.value, prior), "partition uses selected successor, not original parent"
  assert sameStateSnapshot(plan.currentContinuationSource.value.currentSequenceStateAt(
      CurrentSequenceEntryIndex(0)).value, prior)
  assert plan.currentContinuationReportAt(CurrentPlanReportIndex(0)).error ==
      CurrentSequenceError.None
  assert plan.currentContinuationReportAt(CurrentPlanReportIndex(high(uint64))).error ==
      CurrentSequenceError.InvalidIndex
  assert source.currentSequenceCoverageAt(CurrentSequenceEntryIndex(high(uint64))).error ==
      CurrentSequenceError.InvalidIndex
  for mode in 0..<5:
    var limits = policy()
    var expected = CurrentSequenceError.Uninitialized
    case mode
    of 0:
      limits.reports = ElementLimit(0)
      expected = CurrentSequenceError.LimitExceeded
    of 1:
      limits.digests = ElementLimit(0)
      expected = CurrentSequenceError.LimitExceeded
    of 2:
      limits.operands.reports = ElementLimit(0)
      expected = CurrentSequenceError.OperandFailure
    of 3:
      limits.inputs.services = ElementLimit(0)
      expected = CurrentSequenceError.InputFailure
    else:
      limits.partition.transfers = ElementLimit(0)
      expected = CurrentSequenceError.PartitionFailure
    let refused = planCurrentAccumulationContinuation(source, limits)
    assert refused.error == expected, $mode & ":" & $refused.error
    assert sameStateSnapshot(source.currentSequenceLatestState.value, prior), "a later planning refusal cannot publish source changes"
  let terminal = startCurrentAccumulationSequence(initial(base, empty = true)).value
  let ended = planCurrentAccumulationContinuation(terminal, policy()).value
  let endInfo = ended.currentContinuationInfo.value
  assert not endInfo.dispatch and uint64(endInfo.prefix) == 0 and endInfo.pendingReports == 1, "unaffordable original report stays pending for a later block"
  assert ended.currentContinuationInputs.value.invocationServiceCount.value == 0
  assert ended.currentContinuationReportAt(CurrentPlanReportIndex(0)).error ==
      CurrentSequenceError.InvalidIndex
  let badSource = startCurrentAccumulationSequence(default(PreparedCurrentAccumulationRound))
  assert badSource.error == CurrentSequenceError.InvalidSource
  let badPlan = planCurrentAccumulationContinuation(default(CurrentAccumulationSequence), policy())
  assert badPlan.error == CurrentSequenceError.InvalidSource
  assert default(PreparedCurrentContinuation).currentContinuationInfo.error ==
      CurrentSequenceError.Uninitialized
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = startCurrentAccumulationSequence(completed).value
    let next = planCurrentAccumulationContinuation(local, policy()).value
    assert next.currentContinuationInfo.value.queued ==
        1 # Flat source facts and temporary plans release without predecessor certificate chains.
  let after = getOccupiedMem()
  assert occupied == after, "current continuation input owners release"
  recordArcRelease("pvm_current_continuation_inputs", 1000, occupied, after)
  echo "PVM current continuation inputs passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Missing fixtures, admission and unexpected setup failures must fail the native suite.
except:
  quit(2)
