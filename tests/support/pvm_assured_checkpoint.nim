# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared genuine checkpoint-deletion witnesses preserve all terminal, local-limit, publication and ownership assertions.

import std/[assertions, syncio]
import ../../src/state/assured/[chain as assured_chain, composition as assured_composition,
    execution as assured_execution, queue as assured_queue]
import ../../src/state/accumulation/[execution as accumulation_execution,
    round as accumulation_round, inputs as accumulation_inputs, batch as accumulation_batch,
    provisions as accumulation_provisions, outcome as accumulation_outcome,
    context as accumulation_context, effects as accumulation_effects,
    consensus as accumulation_consensus, runner as accumulation_runner,
    dispatch as accumulation_dispatch]
import ../../src/state/store
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/bounded
import ../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    service_values as state_service_values, statistics as state_statistics,
    workqueues as state_workqueues]
import ../../src/pvm/[machine, step]
import ./[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## The account survives successive writes; decode its exact canonical fields at each retained full-map owner.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, present: bool) =
  ## Distinguish retained checkpoint absence from both the initial parent and actual later regular restoration.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  let found = state.lookup(key)
  let account = metadata(state)
  if present:
    assert found.error == StateStoreError.None
    assert found.value.bytes == @[1'u8, 22, 23, 255, 255, 255, 255, 255, 255, 255, 255]
    assert uint32(account.storageItems) == 1 and uint64(account.storageBytes) == 46
  else:
    assert found.error == StateStoreError.MissingKey
    assert uint32(account.storageItems) == 0 and uint64(account.storageBytes) == 0
  assert uint64(account.balance) == 58
proc config(fixture: AssuredOutcomeFixture): AssuredExecutionConfig =
  ## Match original mode-specific local scheduling while certifying only the selected checkpoint deletion.
  result = assuredExecutionConfig(fixture.queue)
  result.runner.steps = ExecutionStepLimit(32)
  result.runner.calls = HostCallLimit(5)
  result.runner.completion.batch.selfValueBytes = ByteLimit(0)
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Execute the real fetch/deletion/checkpoint/read/restoration/branch sequence under the unchanged original protocol tuple.
  let outcome = executeAssuredAccumulation(fixture.queue, config(fixture))
  if outcome.error != AssuredExecutionError.None:
    echo "checkpoint execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Compose the selected checkpoint deletion without replaying initial guest work.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None: echo "checkpoint composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
proc cycle(fixture: AssuredOutcomeFixture) =
  ## Execute the input-controlled checkpoint fault, compose and publish its absent key, then release every successor owner.
  let source = compose(execute(fixture))
  var state = fixture.state
  var view = fixture.view
  let published = advanceAssuredChain(state, view, source)
  assert published.error == AssuredChainError.None
  storage(published.value.assuredChainSnapshot.value, false)
proc verifyCheckpointDeletion*(mode: ComputedStorageMode, evidenceName: string) =
  ## Execute one originally authored terminal path through the full pipeline and retain distinct suite ARC evidence.
  assert mode in {ComputedStorageMode.ReadCheckpointPanic, ComputedStorageMode.ReadCheckpointFault,
    ComputedStorageMode.ReadCheckpointProtection, ComputedStorageMode.ReadCheckpointWrapLoad,
    ComputedStorageMode.ReadCheckpointWrapStore, ComputedStorageMode.ReadCheckpointNegativeBranch,
    ComputedStorageMode.ReadCheckpointUntakenBranch}
  let fixture = assuredOutcomeFixture(mode)
  let original = fixture.state.snapshot.value
  let oldView = fixture.view
  storage(original, true)
  assert uint32(metadata(original).lastAccumulation) == 2
  let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
  assert first.outcomeInfo.value.dimension == AccumulationDimension.Regular
  storage(first.outcomeContext.value.effectAccounts.value, true)
  let firstInputs = fixture.first.executionRound.value.roundProjection.value.roundInputs.value
  assert firstInputs.invocationServiceAt(InvocationServiceIndex(0)).value.operands == 1
  let source = execute(fixture)
  let completed = source.assuredExecutionCompleted.value
  let info = completed.executionInfo.value
  assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
  assert info.batch.selfWrites == 1 and info.batch.selfValueBytes == 0
  assert info.batch.deletedAccounts == 0 and info.batch.createdAccounts == 0
  assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
  let nextInputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  assert nextInputs.invocationServiceAt(InvocationServiceIndex(0)).value.operands == 2
  assert uint64(info.gasUsed) > 7696 and uint64(info.gasUsed) <= 9690
  assert uint64(first.outcomeInfo.value.gasUsed) > 7696 and uint64(
      first.outcomeInfo.value.gasUsed) <= 9690
  let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let terminal = selected.outcomeInfo.value
  assert terminal.termination == AccumulationTermination.Panic and terminal.dimension ==
      AccumulationDimension.Exceptional
  assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
  assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
  storage(selected.outcomeContext.value.effectAccounts.value, false)
  let policy = config(fixture)
  var minimal = policy
  minimal.runner.copyBytes = MemoryByteLimit(11)
  minimal.runner.steps = ExecutionStepLimit(30) # Two current write selectors add two actual guest instructions.
  let exact = executeAssuredAccumulation(fixture.queue, minimal)
  assert exact.error == AssuredExecutionError.None
  assert exact.value.assuredExecutionCompleted.value.executionInfo.value.batch.selfWrites == 1
  storage(exact.value.assuredExecutionCompleted.value.executionBatch.value.batchOutcomeAt(
      AccumulationProvisionSourceIndex(0)).value.outcomeContext.value.effectAccounts.value, false)
  for ceiling in 3..4:
    # Calls3 reaches the read; calls4 reaches the regular restoration, proving that neither actual host can be skipped.
    var short = policy
    short.runner.calls = HostCallLimit(ceiling)
    let calls = executeAssuredAccumulation(fixture.queue, short)
    assert calls.error == AssuredExecutionError.RunnerFailure
    assert calls.runnerFailure.error == AccumulationRunnerError.DispatchFailure
    assert calls.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
    assert calls.runnerFailure.dispatchFailure.executionError == StepError.HostCallLimitExceeded
  var short = minimal
  short.runner.steps = ExecutionStepLimit(29) # One below the independently counted thirty-instruction path.
  let steps = executeAssuredAccumulation(fixture.queue, short)
  assert steps.error == AssuredExecutionError.RunnerFailure
  assert steps.runnerFailure.error == AccumulationRunnerError.DispatchFailure
  assert steps.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
  assert steps.runnerFailure.dispatchFailure.executionError == StepError.StepLimitExceeded
  short = minimal
  short.runner.copyBytes = MemoryByteLimit(10)
  let copy = executeAssuredAccumulation(fixture.queue, short)
  assert copy.error == AssuredExecutionError.RunnerFailure
  assert copy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
  assert copy.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
  short = minimal
  short.runner.completion.batch.selfWrites = ElementLimit(0)
  let keys = executeAssuredAccumulation(fixture.queue, short)
  assert keys.error == AssuredExecutionError.RunnerFailure
  assert keys.runnerFailure.error == AccumulationRunnerError.CompletionFailure
  assert keys.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
  assert keys.runnerFailure.completionFailure.batchFailure.error ==
      AccumulationBatchError.LimitExceeded
  short = minimal
  short.runner.accountWriteKeys = ElementLimit(0)
  let proof = executeAssuredAccumulation(fixture.queue, short)
  assert proof.error == AssuredExecutionError.RunnerFailure
  assert proof.runnerFailure.error == AccumulationRunnerError.CompletionFailure
  assert proof.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
  assert proof.runnerFailure.completionFailure.batchFailure.error ==
      AccumulationBatchError.UnsupportedAccountEffects
  let composed = compose(source)
  let candidate = composed.assuredCompositionPlan.value.accumulationConsensusState.value
  storage(candidate, false)
  assert uint32(metadata(candidate).lastAccumulation) == 3
  assert array[32, byte](metadata(candidate).codeHash) == array[32, byte](metadata(
      original).codeHash)
  let queueConfig = assuredCompositionConfig().composition.ready.queues
  assert decodeAccumulatedState(candidate.lookup(chapterKey(StateChapter(15))).value.bytes,
      queueConfig).value.snapshot.accumulatedInfo.value.items == 3
  let activity = decodeActivityState(candidate.lookup(chapterKey(StateChapter(13))).value.bytes,
    ActivityConfig(cores: queueConfig.cores, current: typeof(
        fixture.view.bestBlock.value.activeValidators)(9), previous: typeof(
        fixture.view.bestBlock.value.activeValidators)(6), maxServices: ElementLimit(4),
        maxBytes: ByteLimit(10000))).value.snapshot
  let counters = activity.serviceActivityAt(StatisticsServiceIndex(0)).value.statistics
  assert uint64(counters.counters[ServiceMeasure.AccumulationCount]) == 2
  assert uint64(counters.counters[ServiceMeasure.RefinementCount]) == 0
  assert uint64(counters.accumulationGas) == uint64(info.gasUsed)
  var state = fixture.state
  var view = fixture.view
  let published = advanceAssuredChain(state, view, composed)
  assert published.error == AssuredChainError.None
  assert published.value.assuredChainBlock.value.slot == 3 and view.retainedCount == 3 and
      view.finalizedBlock.value.slot == 1
  assert sameStateSnapshot(state.snapshot.value, candidate)
  storage(published.value.assuredChainSnapshot.value, false)
  for field in low(Parameter)..high(Parameter):
    assert published.value.assuredChainBlock.value.chainParameters.get(field) ==
        source.assuredExecutionParameters.value.get(
        field) # Actual checkpoint selection retains the original complete chain tuple.
  assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
  storage(original, true)
  assert uint32(metadata(original).lastAccumulation) == 2
  cycle(fixture)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(fixture) # The original parent keeps its key while each actual readback/canonical child retires completely.
  let after = getOccupiedMem()
  assert before == after, "assured checkpoint fault ARC release"
  recordArcRelease(evidenceName, 1000, before, after)
