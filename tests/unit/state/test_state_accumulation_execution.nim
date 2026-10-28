# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_execution_arc_release"}

## Real admitted initial rounds retain complete batches and canonical actual gas observations.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_layout as codec_state_layout
import ../../support/state_accumulation_execution_context
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Prove gas collection, retained queries and empty state publication do not perform new hashes.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc main() {.raises.} =
  # Read the checksum-verified static witness through the runner's explicit fixture contract.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let limits = executionLimits()
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.signed.withAvailable = true
  let fixture = executionFixture(base, executionOptions0)
  let first = executionGuest(fixture, 0)
  let second = executionGuest(fixture, 1)
  assert first.error == AccumulationDispatchError.None and second.error ==
      AccumulationDispatchError.None
  failHash(1)
  let plan = completeBlockAccumulation(fixture.round, [second, first], [], limits).value
  let info = plan.executionInfo.value
  assert info.services == 2 and info.batch.completeInputs
  assert uint64(info.round.allowanceGas) == 200000 and uint64(info.round.reportGas) == 10
  assert uint64(info.round.prefix) == 1 and uint64(info.round.budget) == 300000
  assert uint64(info.gasUsed) == 44, $uint64(info.gasUsed) # Two independent jump-indirect blocks cost 22 each.
  for index, service in [42'u32, 99'u32]:
    let row = plan.executionGasAt(InvocationServiceIndex(uint64(index))).value
    assert uint32(row.service) == service and uint64(row.gasUsed) == 22
  assert uint32(plan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.service) == 99
  assert sameAccumulationInputs(plan.executionRound.value.roundProjection.value.roundInputs.value,
    fixture.round.roundProjection.value.roundInputs.value)
  assert plan.executionGasAt(InvocationServiceIndex(high(uint64))).error ==
      AccumulationExecutionError.InvalidIndex
  var copied = info
  copied.gasUsed = Gas(999)
  copied.round.budget = Gas(999)
  var row = plan.executionGasAt(InvocationServiceIndex(0)).value
  row.gasUsed = Gas(999)
  assert uint64(plan.executionInfo.value.gasUsed) == 44
  assert uint64(plan.executionGasAt(InvocationServiceIndex(0)).value.gasUsed) == 22
  var state = fixture.state
  assert applyAccumulationBatch(state, plan.executionBatch.value).error ==
      AccumulationBatchError.None
  assert sameStateSnapshot(state.snapshot.value, fixture.state.snapshot.value)
  assert hashCalls() == 0
  failHash(0)
  # A checkpoint rollback retains actual gas spent before panic; gas is not rolled back with effects.
  var executionOptions1 = executionFixtureConfig()
  executionOptions1.first = ExecutionEnding.Panic
  let panic = executionFixture(base, executionOptions1)
  let panicPlan = completeBlockAccumulation(panic.round,
    [executionGuest(panic, 0), executionGuest(panic, 1)], [], limits).value
  assert uint64(panicPlan.executionGasAt(InvocationServiceIndex(0)).value.gasUsed) == 203,
    $uint64(panicPlan.executionGasAt(InvocationServiceIndex(0)).value.gasUsed)
  assert uint64(panicPlan.executionInfo.value.gasUsed) == 225
  let panicOutcome = panicPlan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value
  assert panicOutcome.termination == AccumulationTermination.Panic
  # Basic-block out-of-gas retains the original credit; no unpaid block is charged. A skip also uses zero.
  var executionOptions2 = executionFixtureConfig()
  executionOptions2.first = ExecutionEnding.Exhausted
  executionOptions2.second = ExecutionEnding.Missing
  let mixed = executionFixture(base, executionOptions2)
  let exhausted = executionGuest(mixed, 0)
  let skipped = executionSkip(mixed, 1)
  let mixedPlan = completeBlockAccumulation(mixed.round, [exhausted], [skipped], limits).value
  assert uint64(mixedPlan.executionInfo.value.gasUsed) == 0
  assert uint64(mixedPlan.executionGasAt(InvocationServiceIndex(1)).value.gasUsed) == 0
  assert mixedPlan.executionInfo.value.batch.skipped == 1
  let outOfGas = mixedPlan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value
  assert outOfGas.termination == AccumulationTermination.OutOfGas
  # Host out-of-gas differs: its negative posterior gas is capped at the entire initial credit.
  var executionOptions3 = executionFixtureConfig()
  executionOptions3.first = ExecutionEnding.HostExhausted
  executionOptions3.second = ExecutionEnding.Missing
  let host = executionFixture(base, executionOptions3)
  let hostPlan = completeBlockAccumulation(host.round, [executionGuest(host, 0)], [executionSkip(
      host, 1)], limits).value
  assert uint64(hostPlan.executionInfo.value.gasUsed) == 200
  assert uint64(hostPlan.executionGasAt(InvocationServiceIndex(0)).value.gasUsed) == 200
  var executionOptions4 = executionFixtureConfig()
  executionOptions4.first = ExecutionEnding.Missing
  executionOptions4.second = ExecutionEnding.Missing
  let allSkip = executionFixture(base, executionOptions4)
  let allSkipA = executionSkip(allSkip, 0)
  let allSkipB = executionSkip(allSkip, 1)
  failHash(1)
  let skippedPlan = completeBlockAccumulation(allSkip.round, [], [allSkipB, allSkipA], limits).value
  assert uint64(skippedPlan.executionInfo.value.gasUsed) == 0
  assert uint32(skippedPlan.executionGasAt(InvocationServiceIndex(0)).value.service) == 42
  assert hashCalls() == 0
  failHash(0)
  var executionOptions5 = executionFixtureConfig()
  executionOptions5.empty = true
  let empty = executionFixture(base, executionOptions5)
  failHash(1)
  let emptyPlan = completeBlockAccumulation(empty.round, [], [], executionLimits(0)).value
  assert emptyPlan.executionInfo.value.services == 0
  assert not emptyPlan.executionInfo.value.round.dispatch
  assert uint64(emptyPlan.executionInfo.value.gasUsed) == 0
  assert emptyPlan.executionGasAt(InvocationServiceIndex(0)).error ==
      AccumulationExecutionError.InvalidIndex
  let defaultPlan = default(CompletedBlockAccumulation)
  assert defaultPlan.executionInfo.error == AccumulationExecutionError.Uninitialized
  assert defaultPlan.executionGasAt(InvocationServiceIndex(0)).error ==
      AccumulationExecutionError.Uninitialized
  assert defaultPlan.executionBatch.error == AccumulationExecutionError.Uninitialized
  assert defaultPlan.executionRound.error == AccumulationExecutionError.Uninitialized
  let defaultResult = default(AccumulationExecutionResult[CompletedBlockAccumulation])
  assert defaultResult.error == AccumulationExecutionError.Uninitialized
  assert completeBlockAccumulation(default(BlockAccumulationRound), [], [], limits).error ==
      AccumulationExecutionError.InvalidRound
  assert completeBlockAccumulation(fixture.round, [first, second], [], executionLimits(1)).error ==
      AccumulationExecutionError.LimitExceeded
  let omitted = completeBlockAccumulation(fixture.round, [first], [], limits)
  assert omitted.batchFailure.error == AccumulationBatchError.IncompleteCoverage
  let duplicated = completeBlockAccumulation(fixture.round, [first, first], [], limits)
  assert duplicated.batchFailure.error == AccumulationBatchError.DuplicateService
  let invalid = default(AccumulationDispatchResult)
  assert completeBlockAccumulation(fixture.round, [first, invalid], [],
      limits).batchFailure.error == AccumulationBatchError.InvalidExecution
  assert hashCalls() == 0
  failHash(0)
  var foreign = fixture
  foreign.round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value,
      executionRoundConfig()).value
  let foreignInput = executionGuest(foreign, 1)
  foreign = fixture
  foreign.state = newStateStore(fixture.entries, state_report_context.limits()).value
  let foreignState = executionGuest(foreign, 1)
  let wrongSlot = executionGuest(fixture, 1, HeaderSlot(3))
  let wrongEntropy = executionGuest(fixture, 1, wrongEntropy = true)
  failHash(1)
  for source in [foreignInput, foreignState]:
    assert completeBlockAccumulation(fixture.round, [first, source], [],
        limits).batchFailure.error == AccumulationBatchError.SourceMismatch
  assert completeBlockAccumulation(fixture.round, [first, wrongEntropy], [], limits).error ==
      AccumulationExecutionError.EntropyMismatch
  let slot = completeBlockAccumulation(fixture.round, [first, wrongSlot], [], limits)
  assert slot.batchFailure.terminalError == AccumulationTerminalProvisionError.InvalidSlot
  assert hashCalls() == 0
  failHash(0)
  # Existing exact-prior publication rejects any intervening state change before gas certificates can overwrite it.
  var changed = fixture.state
  discard changed.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[7'u8])]).value
  let changedPrior = changed.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(changed, plan.executionBatch.value).error ==
      AccumulationBatchError.StaleState
  assert sameStateSnapshot(changed.snapshot.value, changedPrior)
  assert hashCalls() == 0
  failHash(0)
  var retained: CompletedBlockAccumulation
  var detached: StateStore
  block:
    let source = executionFixture(base)
    var executions = @[executionGuest(source, 0), executionGuest(source, 1)]
    retained = completeBlockAccumulation(source.round, executions, [], limits).value
    detached = source.state
    executions.setLen(0) # Completion retains source/batch certificates and copied rows beyond every local source scope.
  assert uint64(retained.executionInfo.value.gasUsed) == 44
  assert applyAccumulationBatch(detached, retained.executionBatch.value).error ==
      AccumulationBatchError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Repeated complete and refused owners release admitted sources, gas rows and normalized batch certificates.
    let completed = completeBlockAccumulation(fixture.round, [second, first], [], limits).value
    assert uint64(completed.executionInfo.value.gasUsed) == 44
    assert completeBlockAccumulation(fixture.round, [first], [], limits).batchFailure.error ==
        AccumulationBatchError.IncompleteCoverage
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_execution", 1000, before, after)
  echo "Admitted accumulation execution and gas passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O or unexpected exceptions remain unsuccessful native executions.
except:
  quit(2)
