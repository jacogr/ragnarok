# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_continuation_execution_arc_release"}

## Actual later-round CPU outcomes and certified skips retain complete coverage and canonical actual gas.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_continuation_invocation as state_accumulation_continuation_invocation
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_layout as codec_state_layout
import ../../support/state_accumulation_continuation_execution_context
import ../../support/state_accumulation_execution_context
import ../../support/state_report_context
import ../../support/pvm_accumulation_provision
import ../../support/testing_arc_evidence

# Detect any hidden hashing during coverage/provenance preflight and no-op completion/application.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[
      index]) # Static report transport precedes genuine parent signing.
  let base = decodeOwnedReport(bytes, 2).value
  let fixture = continuationExecutionFixture(base)
  let source = fixture.source
  let prior = source.continuationState.value
  let limits = executionLimits()
  let first = continuationGuest(source, 0)
  let second = continuationGuest(source, 1)
  failHash(3)
  let completed = completeAccumulationContinuation(source, [second, first], [], limits).value
  let info = completed.executionInfo.value
  assert info.batch.completeInputs and info.services == 2
  assert uint64(info.round.completedPrefix) == 1 and uint64(info.round.prefix) == 1
  assert uint64(info.round.budget) == 200956 and uint64(info.round.reportGas) == 600
  assert uint64(info.gasUsed) == 44
  for index, id in [42'u32, 99]:
    let usage = completed.executionGasAt(InvocationServiceIndex(uint64(index))).value
    assert uint32(usage.service) == id and uint64(usage.gasUsed) == 22 # Numeric order differs from caller order.
  assert uint32(completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.service) == 99
  assert sameAccumulationInputs(completed.executionContinuation.value.continuationInputs.value,
    source.continuationInputs.value)
  assert sameStateSnapshot(completed.executionContinuation.value.continuationState.value, prior)
  var copied = info
  copied.gasUsed = Gas(999)
  copied.round.budget = Gas(999)
  var row = completed.executionGasAt(InvocationServiceIndex(0)).value
  row.gasUsed = Gas(999)
  assert uint64(completed.executionInfo.value.gasUsed) == 44
  assert uint64(completed.executionGasAt(InvocationServiceIndex(0)).value.gasUsed) == 22
  assert completed.executionGasAt(InvocationServiceIndex(high(uint64))).error ==
    AccumulationContinuationExecutionError.InvalidIndex
  var working = forkStateStore(prior).value
  assert applyAccumulationBatch(working, completed.executionBatch.value).error ==
      AccumulationBatchError.None
  assert sameStateSnapshot(working.snapshot.value, prior)
  assert hashCalls() == 0
  # Incomplete, duplicate and refused dispatches cannot fabricate zero-gas coverage.
  assert completeAccumulationContinuation(source, [first], [], limits).batchFailure.error ==
    AccumulationBatchError.IncompleteCoverage
  assert completeAccumulationContinuation(source, [first, first], [], limits).batchFailure.error ==
    AccumulationBatchError.DuplicateService
  let invalidExecution = default(AccumulationDispatchResult)
  assert completeAccumulationContinuation(source, [first, invalidExecution], [],
    limits).batchFailure.error == AccumulationBatchError.InvalidExecution
  assert completeAccumulationContinuation(source, [], [default(SkippedAccumulation), default(
      SkippedAccumulation)],
    limits).batchFailure.error == AccumulationBatchError.InvalidSkip
  assert completeAccumulationContinuation(source, [first, second], [], executionLimits(1)).error ==
    AccumulationContinuationExecutionError.LimitExceeded
  let empty = default(CompletedAccumulationContinuation)
  assert empty.executionInfo.error == AccumulationContinuationExecutionError.Uninitialized
  assert empty.executionGasAt(InvocationServiceIndex(0)).error ==
      AccumulationContinuationExecutionError.Uninitialized
  assert empty.executionBatch.error == AccumulationContinuationExecutionError.Uninitialized
  assert empty.executionContinuation.error == AccumulationContinuationExecutionError.Uninitialized
  let defaultResult = default(AccumulationContinuationExecutionResult[CompletedAccumulationContinuation])
  assert defaultResult.error ==
    AccumulationContinuationExecutionError.Uninitialized
  assert completeAccumulationContinuation(default(PreparedAccumulationContinuationInputs), [], [],
      limits).error ==
    AccumulationContinuationExecutionError.InvalidInputs
  assert hashCalls() == 0
  failHash(0)
  # A re-prepared owner and an equal-root cloned map remain foreign despite identical visible metadata.
  let other = prepareAccumulationContinuationInputs(source.continuationPlan.value,
    AccumulationContinuationInputConfig(operands: executionRoundConfig().operands,
      inputs: executionRoundConfig().inputs)).value
  let foreignInputs = continuationGuest(other, 1)
  let bound = prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(1),
    continuationServiceConfig(), ServiceProbeLimit(1)).value.bootstrapProjection.value
  let entropy = bound.bootstrapInfo.value.entropy
  let cloned = newStateStore(fixture.initial.entries, state_report_context.limits()).value.snapshot.value
  let foreignService = prepareAccumulationService(source.continuationInputs.value,
    InvocationServiceIndex(1), cloned, HeaderSlot(2), continuationServiceConfig()).value
  let foreignState = continuationRun(prepareAccumulationInvocation(foreignService, entropy,
      ServiceProbeLimit(1)).value)
  let lateService = prepareAccumulationService(source.continuationInputs.value,
    InvocationServiceIndex(1), prior, HeaderSlot(3), continuationServiceConfig()).value
  let wrongSlot = continuationRun(prepareAccumulationInvocation(lateService, entropy,
      ServiceProbeLimit(1)).value)
  var changedEntropy = array[32, byte](entropy)
  changedEntropy[0] = changedEntropy[0] xor 1
  let wrongEntropy = continuationRun(prepareAccumulationInvocation(bound.bootstrapService.value,
    StateEntropyWord(changedEntropy), ServiceProbeLimit(1)).value)
  failHash(3)
  for foreign in [foreignInputs, foreignState]:
    assert completeAccumulationContinuation(source, [first, foreign], [],
        limits).batchFailure.error ==
      AccumulationBatchError.SourceMismatch
  assert completeAccumulationContinuation(source, [first, wrongSlot], [],
      limits).batchFailure.terminalError ==
    AccumulationTerminalProvisionError.InvalidSlot
  assert completeAccumulationContinuation(source, [first, wrongEntropy], [], limits).error ==
    AccumulationContinuationExecutionError.EntropyMismatch
  assert hashCalls() == 0
  failHash(0)
  # Panic rolls back effects but retains gas spent; an unpaid basic block consumes zero, a host debt consumes all credit.
  let panic = continuationExecutionFixture(base, first = ExecutionEnding.Panic)
  let panicPlan = completeAccumulationContinuation(panic.source,
    [continuationGuest(panic.source, 0), continuationGuest(panic.source, 1)], [], limits).value
  assert uint64(panicPlan.executionInfo.value.gasUsed) == 225
  assert uint64(panicPlan.executionGasAt(InvocationServiceIndex(0)).value.gasUsed) == 203
  let panicOutcome = panicPlan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value
  assert panicOutcome.termination == AccumulationTermination.Panic
  let mixed = continuationExecutionFixture(base, first = ExecutionEnding.Exhausted,
    second = ExecutionEnding.Missing, firstGas = 1)
  let mixedPlan = completeAccumulationContinuation(mixed.source, [continuationGuest(mixed.source, 0)],
    [continuationSkip(mixed.source, 1)], limits).value
  assert uint64(mixedPlan.executionInfo.value.gasUsed) == 0 and
      mixedPlan.executionInfo.value.batch.skipped == 1
  assert mixedPlan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.termination == AccumulationTermination.OutOfGas
  let host = continuationExecutionFixture(base, first = ExecutionEnding.HostExhausted,
    second = ExecutionEnding.Missing, firstGas = 200)
  let hostPlan = completeAccumulationContinuation(host.source, [continuationGuest(host.source, 0)],
    [continuationSkip(host.source, 1)], limits).value
  assert uint64(hostPlan.executionInfo.value.gasUsed) == 200
  let allSkip = continuationExecutionFixture(base, first = ExecutionEnding.Missing,
      second = ExecutionEnding.Missing)
  let skipA = continuationSkip(allSkip.source, 0)
  let skipB = continuationSkip(allSkip.source, 1)
  let noReports = continuationExecutionFixture(base, empty = true)
  failHash(3)
  let skipPlan = completeAccumulationContinuation(allSkip.source, [], [skipB, skipA], limits).value
  assert uint64(skipPlan.executionInfo.value.gasUsed) == 0
  assert uint32(skipPlan.executionGasAt(InvocationServiceIndex(0)).value.service) == 42
  let emptyPlan = completeAccumulationContinuation(noReports.source, [], [], executionLimits(0)).value
  assert emptyPlan.executionInfo.value.services == 0 and
      not emptyPlan.executionInfo.value.round.dispatch
  assert emptyPlan.executionGasAt(InvocationServiceIndex(0)).error ==
      AccumulationContinuationExecutionError.InvalidIndex
  assert hashCalls() == 0
  failHash(0)
  # Actual initial provisions produce a different map: later outcomes must bind to that successor, never the parent.
  let provided = continuationProvidedFixture(base)
  let providedPrior = provided.source.continuationState.value
  assert not sameStateSnapshot(providedPrior, provided.initial.state.snapshot.value)
  let provisionGuest = continuationGuest(provided.source, 0, provisionPolicy(items = 2, perBlob = 1, total = 2))
  let provisionOther = continuationGuest(provided.source, 1)
  failHash(3)
  let provisionComplete = completeAccumulationContinuation(provided.source,
    [provisionGuest, provisionOther], [], limits).value
  var providedState = forkStateStore(providedPrior).value
  assert applyAccumulationBatch(providedState, provisionComplete.executionBatch.value).error ==
      AccumulationBatchError.None
  assert sameStateSnapshot(providedState.snapshot.value, providedPrior)
  assert hashCalls() == 0 # Already-fulfilled requests are suppressed by the host before union/application.
  failHash(0)
  let wrongParentService = prepareAccumulationService(provided.source.continuationInputs.value,
    InvocationServiceIndex(1), provided.initial.state.snapshot.value, HeaderSlot(2),
        continuationServiceConfig()).value
  let providedEntropy = prepareContinuationAccumulationInvocation(provided.source,
      InvocationServiceIndex(1),
    continuationServiceConfig(), ServiceProbeLimit(
        1)).value.bootstrapProjection.value.bootstrapInfo.value.entropy
  let wrongParent = continuationRun(prepareAccumulationInvocation(wrongParentService,
    providedEntropy, ServiceProbeLimit(1)).value)
  failHash(3)
  assert completeAccumulationContinuation(provided.source, [provisionGuest, wrongParent], [],
      limits).batchFailure.error == AccumulationBatchError.SourceMismatch
  var originalState = provided.initial.state
  assert applyAccumulationBatch(originalState, provisionComplete.executionBatch.value).error ==
      AccumulationBatchError.StaleState
  assert sameStateSnapshot(originalState.snapshot.value, provided.initial.state.snapshot.value)
  assert hashCalls() == 0
  failHash(0)
  # Exact-prior publication cannot overwrite intervening state; completion itself never publishes caller state.
  var changed = forkStateStore(prior).value
  discard changed.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[7'u8])]).value
  let changedPrior = changed.snapshot.value
  failHash(3)
  assert applyAccumulationBatch(changed, completed.executionBatch.value).error ==
      AccumulationBatchError.StaleState
  assert sameStateSnapshot(changed.snapshot.value, changedPrior)
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, prior)
  assert hashCalls() == 0
  failHash(0)
  var retained: CompletedAccumulationContinuation
  block:
    let local = continuationExecutionFixture(base)
    var runs = @[continuationGuest(local.source, 0), continuationGuest(local.source, 1)]
    retained = completeAccumulationContinuation(local.source, runs, [], limits).value
    runs.setLen(0) # Completion retains actual normalized outcomes after every local fixture/array is released.
  assert uint64(retained.executionInfo.value.gasUsed) == 44
  assert retained.executionContinuation.value.continuationInputs.value.invocationServiceCount.value == 2
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Both retained completion graphs and refused incomplete coverage release every gas/source/batch owner.
    let success = completeAccumulationContinuation(source, [second, first], [], limits).value
    assert uint64(success.executionInfo.value.gasUsed) == 44
    let refusal = completeAccumulationContinuation(source, [first], [], limits)
    assert refusal.batchFailure.error == AccumulationBatchError.IncompleteCoverage
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_continuation_execution", 1000, before, after)
  echo "Accumulation continuation execution and gas passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Missing fixture transport or unexpected exceptions remain native failures.
except:
  quit(2)
