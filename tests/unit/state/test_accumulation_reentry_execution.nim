# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_reentry_execution_arc_release"}

## Bound reentry entropy/provenance survives real PVM execution, complete coverage and canonical actual gas.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_reentry_invocation, accumulation_reentry_execution,
  accumulation_reentry, accumulation_continuation_execution, accumulation_continuation_inputs,
  accumulation_continuation, accumulation_execution, accumulation_round, accumulation_queue,
  accumulation_inputs, accumulation_batch, accumulation_service, accumulation_invocation,
  accumulation_dispatch, accumulation_skip, accumulation_outcome, accumulation_provisions,
  accumulation_terminal_provisions, accumulation_machine, report_admission, block_transition, store]
import ../../../src/codec/[bounded, composite, report_owned, header, state_safrole, state_layout,
  state_trie, work_digest]
import ../../../src/pvm/[initialize, machine, program]
import ../../support/[accumulation_reentry_context, accumulation_continuation_execution_context,
  accumulation_execution_context, report_context, arc_evidence]

# Refuse the maintained test provider after signed fixture construction; observations and preflight must remain hash-free.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index]) # Preserve static source bytes before signing.
  let base = decodeOwnedReport(bytes, 2).value
  let limits = executionLimits()
  let fixture = reentryFixture(base)
  let source = fixture.source
  let inputs = source.reentryInputs.value
  let prior = source.reentryState.value
  let bound = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0),
    continuationServiceConfig(), ServiceProbeLimit(1)).value
  let projection = bound.bootstrapProjection.value
  let info = projection.bootstrapInfo.value
  assert projection.bootstrapArguments.value == @[2'u8, 42, 2] # Literal compact slot/service/two selected inputs.
  assert uint64(projection.bootstrapService.value.serviceInfo.value.gas) == 1000
  assert serviceSourceMatches(projection.bootstrapService.value, inputs, prior)
  assert sameStateSnapshot(bound.bootstrapReentry.value.reentryState.value, prior)
  let initial = source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value
  let stage = initial.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let posterior = decodeStateEntropy(stage.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let parent = decodeStateEntropy(prior.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  assert array[32, byte](posterior) != array[32, byte](parent)
  assert array[32, byte](info.entropy) == array[32, byte](posterior)
  assert uint32(info.nextService) == uint32(initialAccumulationService(info.service, posterior,
      info.slot).value)
  var copied = info
  copied.entropy = parent
  var args = projection.bootstrapArguments.value
  args[0] = 9
  assert projection.bootstrapArguments.value == @[2'u8, 42, 2]
  assert array[32, byte](projection.bootstrapInfo.value.entropy) == array[32, byte](posterior)
  let cpu = initializeAccumulationMachine(projection, InitializationLimits(
      envelope: InitializationByteLimit(512),
    program: ProgramByteLimit(256), jumps: JumpCountLimit(0), pages: PageLimit(
        5))).value.accumulationMachine.value.machineInfo.value
  assert uint32(cpu.pc) == 5 and uint64(cpu.gas) == 1000
  let first = reentryGuest(source, 0)
  let second = reentryGuest(source, 1)
  failHash(3)
  let completed = completeAccumulationReentry(source, [second, first], [], limits).value
  let facts = completed.executionInfo.value
  assert uint64(facts.round.completedPrefix) == 2 and uint64(facts.round.prefix) == 2
  assert uint64(facts.round.budget) == 200912 and uint64(facts.round.reportGas) == 2000
  assert facts.batch.completeInputs and facts.services == 2 and uint64(facts.gasUsed) == 44
  for index, id in [42'u32, 99]:
    let row = completed.executionGasAt(InvocationServiceIndex(uint64(index))).value
    assert uint32(row.service) == id and uint64(row.gasUsed) == 22
  assert uint32(completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.service) == 99
  assert sameAccumulationInputs(completed.executionReentry.value.reentryInputs.value, inputs)
  var observation = facts
  observation.gasUsed = Gas(999)
  assert uint64(completed.executionInfo.value.gasUsed) == 44
  assert completed.executionGasAt(InvocationServiceIndex(high(uint64))).error ==
      AccumulationReentryExecutionError.InvalidIndex
  var working = forkStateStore(prior).value
  assert applyAccumulationBatch(working, completed.executionBatch.value).error ==
      AccumulationBatchError.None
  assert sameStateSnapshot(working.snapshot.value, prior)
  assert completeAccumulationReentry(source, [first], [], limits).batchFailure.error ==
      AccumulationBatchError.IncompleteCoverage
  assert completeAccumulationReentry(source, [first, first], [], limits).batchFailure.error ==
      AccumulationBatchError.DuplicateService
  let refusedExecution = default(AccumulationDispatchResult)
  let invalidRun = completeAccumulationReentry(source, [first, refusedExecution], [], limits)
  assert invalidRun.batchFailure.error == AccumulationBatchError.InvalidExecution
  let refusedSkip = default(SkippedAccumulation)
  let invalidSkip = completeAccumulationReentry(source, [], [refusedSkip, refusedSkip], limits)
  assert invalidSkip.batchFailure.error == AccumulationBatchError.InvalidSkip
  assert completeAccumulationReentry(source, [first, second], [], executionLimits(1)).error ==
      AccumulationReentryExecutionError.LimitExceeded
  let empty = default(CompletedAccumulationReentry)
  assert empty.executionInfo.error == AccumulationReentryExecutionError.Uninitialized
  assert empty.executionGasAt(InvocationServiceIndex(0)).error ==
      AccumulationReentryExecutionError.Uninitialized
  assert empty.executionBatch.error == AccumulationReentryExecutionError.Uninitialized
  assert empty.executionReentry.error == AccumulationReentryExecutionError.Uninitialized
  assert completeAccumulationReentry(default(PreparedAccumulationReentry), [], [], limits).error ==
      AccumulationReentryExecutionError.InvalidInputs
  assert hashCalls() == 0
  failHash(0)
  let defaultBound = default(ReentryAccumulationInvocation)
  assert defaultBound.bootstrapProjection.error == AccumulationReentryInvocationError.Uninitialized
  assert defaultBound.bootstrapReentry.error == AccumulationReentryInvocationError.Uninitialized
  assert prepareReentryAccumulationInvocation(default(PreparedAccumulationReentry),
      InvocationServiceIndex(0),
    continuationServiceConfig(), ServiceProbeLimit(1)).error ==
        AccumulationReentryInvocationError.InvalidInputs
  assert prepareReentryAccumulationInvocation(source, InvocationServiceIndex(high(uint64)),
    continuationServiceConfig(), ServiceProbeLimit(1)).serviceError ==
        AccumulationServiceError.InvalidIndex
  var limited = continuationServiceConfig()
  limited.preimageBytes = ByteLimit(0)
  assert prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0), limited,
    ServiceProbeLimit(1)).serviceError == AccumulationServiceError.LimitExceeded
  assert prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0),
      continuationServiceConfig(),
    ServiceProbeLimit(0)).invocationError == AccumulationInvocationError.LimitExceeded
  failHash(1)
  assert prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0),
      continuationServiceConfig(),
    ServiceProbeLimit(1)).serviceError == AccumulationServiceError.BackendFailure
  failHash(0)
  # Equal visible metadata cannot replace either the exact prepared input owner or complete prior-map owner.
  let foreign = reentryFixture(base)
  let foreignInput = reentryGuest(foreign.source, 1)
  let clone = newStateStore(fixture.initial.entries, report_context.limits()).value.snapshot.value
  let cloneService = prepareAccumulationService(inputs, InvocationServiceIndex(1), clone,
      HeaderSlot(2), continuationServiceConfig()).value
  let foreignState = reentryRun(prepareAccumulationInvocation(cloneService, posterior,
      ServiceProbeLimit(1)).value)
  let lateService = prepareAccumulationService(inputs, InvocationServiceIndex(1), prior, HeaderSlot(
      3), continuationServiceConfig()).value
  let late = reentryRun(prepareAccumulationInvocation(lateService, posterior, ServiceProbeLimit(1)).value)
  var wrong = array[32, byte](posterior)
  wrong[0] = wrong[0] xor 1
  let wrongEntropy = reentryRun(prepareAccumulationInvocation(projection.bootstrapService.value,
    StateEntropyWord(wrong), ServiceProbeLimit(1)).value)
  failHash(3)
  for run in [foreignInput, foreignState]:
    assert completeAccumulationReentry(source, [first, run], [], limits).batchFailure.error ==
        AccumulationBatchError.SourceMismatch
  let invalidSlot = completeAccumulationReentry(source, [first, late], [], limits)
  assert invalidSlot.batchFailure.terminalError == AccumulationTerminalProvisionError.InvalidSlot
  assert completeAccumulationReentry(source, [second, wrongEntropy], [], limits).error ==
      AccumulationReentryExecutionError.EntropyMismatch
  assert hashCalls() == 0
  failHash(0)
  let panic = reentryFixture(base, first = ExecutionEnding.Panic)
  let panicPlan = completeAccumulationReentry(panic.source,
    [reentryGuest(panic.source, 0), reentryGuest(panic.source, 1)], [], limits).value
  assert uint64(panicPlan.executionInfo.value.gasUsed) == 225
  assert panicPlan.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.termination == AccumulationTermination.Panic
  let mixed = reentryFixture(base, first = ExecutionEnding.Exhausted,
      second = ExecutionEnding.Missing, firstGas = 1)
  let mixedPlan = completeAccumulationReentry(mixed.source, [reentryGuest(mixed.source, 0)],
    [reentrySkip(mixed.source, 1)], limits).value
  assert uint64(mixedPlan.executionInfo.value.gasUsed) == 0 and
      mixedPlan.executionInfo.value.batch.skipped == 1
  let host = reentryFixture(base, first = ExecutionEnding.HostExhausted,
      second = ExecutionEnding.Missing, firstGas = 200)
  let hostPlan = completeAccumulationReentry(host.source, [reentryGuest(host.source, 0)],
    [reentrySkip(host.source, 1)], limits).value
  assert uint64(hostPlan.executionInfo.value.gasUsed) == 200
  let missing = reentryFixture(base, first = ExecutionEnding.Missing,
      second = ExecutionEnding.Missing)
  assert prepareReentryAccumulationInvocation(missing.source, InvocationServiceIndex(0),
      continuationServiceConfig(),
    ServiceProbeLimit(1)).invocationError == AccumulationInvocationError.CodeUnavailable
  let skipA = reentrySkip(missing.source, 0)
  let skipB = reentrySkip(missing.source, 1)
  let stopped = reentryFixture(base, stopped = true)
  let noReports = reentryFixture(base, empty = true)
  failHash(3)
  assert uint64(completeAccumulationReentry(missing.source, [], [skipB, skipA],
      limits).value.executionInfo.value.gasUsed) == 0
  for stoppedSource in [stopped.source, noReports.source]:
    let plan = completeAccumulationReentry(stoppedSource, [], [], executionLimits(0)).value
    assert plan.executionInfo.value.services == 0 and not plan.executionInfo.value.round.dispatch
  assert hashCalls() == 0
  failHash(0)
  # The previous completed batch genuinely changed this map; old priors must be refused even with the same input owner.
  let provided = reentryFixture(base, provided = true)
  let actual = provided.source.reentryState.value
  let old = provided.source.reentrySource.value.executionContinuation.value.continuationState.value
  assert not sameStateSnapshot(actual, old)
  let providedBound = prepareReentryAccumulationInvocation(provided.source, InvocationServiceIndex(0),
    continuationServiceConfig(), ServiceProbeLimit(1)).value.bootstrapProjection.value
  assert serviceSourceMatches(providedBound.bootstrapService.value,
      provided.source.reentryInputs.value, actual)
  let providedFirst = reentryGuest(provided.source, 0, provided = true)
  let providedSecond = reentryGuest(provided.source, 1)
  let providedRuns = [providedFirst, providedSecond]
  let providedPlan = completeAccumulationReentry(provided.source, providedRuns, [], limits).value
  let staleService = prepareAccumulationService(provided.source.reentryInputs.value,
      InvocationServiceIndex(1), old,
    HeaderSlot(2), continuationServiceConfig()).value
  let stale = reentryRun(prepareAccumulationInvocation(staleService,
      providedBound.bootstrapInfo.value.entropy, ServiceProbeLimit(1)).value)
  failHash(3)
  let wrongPrior = completeAccumulationReentry(provided.source, [providedFirst, stale], [], limits)
  assert wrongPrior.batchFailure.error == AccumulationBatchError.SourceMismatch
  var changed = forkStateStore(prior).value
  failHash(0)
  discard changed.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[7'u8])]).value
  let changedPrior = changed.snapshot.value
  failHash(3)
  assert applyAccumulationBatch(changed, completed.executionBatch.value).error ==
      AccumulationBatchError.StaleState
  assert sameStateSnapshot(changed.snapshot.value, changedPrior)
  var oldStore = forkStateStore(old).value
  assert applyAccumulationBatch(oldStore, providedPlan.executionBatch.value).error ==
      AccumulationBatchError.StaleState
  assert hashCalls() == 0
  failHash(0)
  var retained: CompletedAccumulationReentry
  var retainedBound: ReentryAccumulationInvocation
  block:
    let local = reentryFixture(base)
    retainedBound = prepareReentryAccumulationInvocation(local.source, InvocationServiceIndex(0),
      continuationServiceConfig(), ServiceProbeLimit(1)).value
    retained = completeAccumulationReentry(local.source, [reentryGuest(local.source, 0),
        reentryGuest(local.source, 1)], [], limits).value
  assert retainedBound.bootstrapProjection.value.bootstrapArguments.value == @[2'u8, 42, 2]
  assert retained.executionReentry.value.reentryInfo.value.pendingReports == 2
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let invocation = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0),
        continuationServiceConfig(), ServiceProbeLimit(1)).value
    assert invocation.bootstrapProjection.value.bootstrapArguments.value == @[2'u8, 42, 2]
    let success = completeAccumulationReentry(source, [second, first], [], limits).value
    assert uint64(success.executionInfo.value.gasUsed) == 44
    let refusal = completeAccumulationReentry(source, [first], [], limits)
    assert refusal.batchFailure.error == AccumulationBatchError.IncompleteCoverage
    let probe = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(0),
        continuationServiceConfig(), ServiceProbeLimit(0))
    assert probe.invocationError == AccumulationInvocationError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_reentry_execution", 1000, before, after)
  echo "Accumulation reentry invocation and execution passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O and unexpected exceptions remain native failures.
except:
  quit(2)
