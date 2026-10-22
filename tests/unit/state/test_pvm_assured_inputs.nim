# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_inputs_arc_release"}

## Genuine guests copy actual first/second report operand bytes to storage and preserve full-width absence through canonical publication.

import std/[assertions, syncio]
import ../../../src/state/[assured_chain, assured_composition, assured_execution, assured_queue,
  accumulation_execution, accumulation_round, accumulation_inputs, accumulation_batch,
  accumulation_provisions, accumulation_outcome, accumulation_context, accumulation_effects,
  accumulation_consensus, accumulation_finalization, accumulation_runner, accumulation_dispatch,
  report_admission, block_transition, block_admission, store]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, c2_records, state_accounts, state_layout, state_service_values,
  state_statistics, state_workqueues]
import ../../../src/pvm/[machine, step]
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode the actual account at the original, selected and published map owners.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, expected: openArray[byte]) =
  ## Exact guest-derived bytes distinguish actual input consumption from the unchanged initial writable prefix.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @expected
  assert uint32(metadata(state).storageItems) == 1 and uint64(metadata(state).storageBytes) == 38
proc hashPrefix(completed: CompletedBlockAccumulation, index: uint64): seq[byte] =
  ## Independent C.2 field oracle: tag0 is followed immediately by packageHash, so fetch offset1 selects its first three bytes.
  let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  let input = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(index)).value
  assert input.kind == AccumulationKind.Operand
  let hash = input.operand.operandInfo.value.packageHash.bytes
  @[hash[0], hash[1], hash[2]]
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Execute authentic prepared inputs under the inherited original parameters and unchanged independent runner ceilings.
  let outcome = executeAssuredAccumulation(fixture.queue, assuredExecutionConfig(fixture.queue))
  if outcome.error != AssuredExecutionError.None:
    echo "input guest execution ", outcome.error
    if outcome.error == AssuredExecutionError.RunnerFailure: echo "runner ",
        outcome.runnerFailure.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Preserve actual input-derived guest effects through real stopped history and every maintained state phase.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None:
    echo "input guest composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
proc witness(mode: ComputedStorageMode): AssuredOutcomeFixture =
  ## Compare historical single-input behavior with actual two-input successor behavior, then prove exact canonical installation.
  let fixture = assuredOutcomeFixture(mode)
  let original = fixture.state.snapshot.value
  let oldView = fixture.view
  let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
  assert first.outcomeInfo.value.dimension == AccumulationDimension.Regular
  let expectedFirst = if mode == ComputedStorageMode.FetchFirst: hashPrefix(fixture.first,
      0) else: @[21'u8, 22, 23]
  storage(first.outcomeContext.value.effectAccounts.value, expectedFirst)
  storage(original, expectedFirst)
  assert uint32(metadata(original).lastAccumulation) == 2
  let executed = execute(fixture)
  let completed = executed.assuredExecutionCompleted.value
  let info = completed.executionInfo.value
  assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
  assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
  let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert service.operands == 2 and service.transfers == 0 and uint64(service.gas) == 20000
  let left = hashPrefix(completed, 0)
  let right = hashPrefix(completed, 1)
  assert left != right and left != @[21'u8, 22, 23] and right != @[21'u8, 22, 23]
  let expected = case mode
    of ComputedStorageMode.FetchFirst: left
    of ComputedStorageMode.FetchSecond: right
    else: @[21'u8, 22, 23] # Maximum-width absence must not wrap to either actual report index or overwrite memory.
  let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  let terminal = selected.outcomeInfo.value
  assert terminal.termination == AccumulationTermination.Halt and terminal.dimension ==
      AccumulationDimension.Regular
  assert not terminal.hasYield and terminal.transfers == 0 and terminal.provisions == 0
  assert uint64(info.gasUsed) > 2804 and uint64(info.gasUsed) <=
      3801 # Fetch355+ceil(344*3/1024)=357, write2447, one block at most997.
  assert uint64(terminal.gasUsed) == uint64(info.gasUsed)
  assert info.batch.selfWrites == 1 and info.batch.selfValueBytes == 3
  storage(selected.outcomeContext.value.effectAccounts.value, expected)
  let composed = compose(executed)
  let candidate = composed.assuredCompositionPlan.value.accumulationConsensusState.value
  storage(candidate, expected)
  assert uint32(metadata(candidate).lastAccumulation) == 3 and uint64(metadata(
      candidate).balance) == 50
  assert array[32, byte](metadata(candidate).codeHash) == array[32, byte](metadata(
      original).codeHash)
  let queueConfig = assuredCompositionConfig().composition.ready.queues
  let history = decodeAccumulatedState(candidate.lookup(chapterKey(StateChapter(15))).value.bytes,
      queueConfig).value.snapshot
  assert history.accumulatedInfo.value.items == 3
  let activity = decodeActivityState(candidate.lookup(chapterKey(StateChapter(13))).value.bytes,
    ActivityConfig(cores: queueConfig.cores, current: typeof(
        fixture.view.bestBlock.value.activeValidators)(9),
      previous: typeof(fixture.view.bestBlock.value.activeValidators)(6), maxServices: ElementLimit(
          4), maxBytes: ByteLimit(10000))).value.snapshot
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
  storage(published.value.assuredChainSnapshot.value, expected)
  for field in low(Parameter)..high(Parameter):
    assert published.value.assuredChainBlock.value.chainParameters.get(field) ==
        executed.assuredExecutionParameters.value.get(
        field) # Actual input content cannot substitute protocol parameters.
  if mode != ComputedStorageMode.FetchMissing:
    var short = assuredExecutionConfig(fixture.queue)
    short.runner.copyBytes = MemoryByteLimit(2)
    let copy = executeAssuredAccumulation(fixture.queue, short)
    assert copy.error == AssuredExecutionError.RunnerFailure
    assert copy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
    assert copy.runnerFailure.dispatchFailure.error ==
        AccumulationDispatchError.LimitExceeded # Three actual selected bytes exceed the real fetch copy cap before storage executes.
  var short = assuredExecutionConfig(fixture.queue)
  short.runner.calls = HostCallLimit(1)
  let calls = executeAssuredAccumulation(fixture.queue, short)
  assert calls.error == AssuredExecutionError.RunnerFailure
  assert calls.runnerFailure.error == AccumulationRunnerError.DispatchFailure
  assert calls.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
  assert calls.runnerFailure.dispatchFailure.executionError == StepError.HostCallLimitExceeded
  short = assuredExecutionConfig(fixture.queue)
  short.runner.completion.batch.selfValueBytes = ByteLimit(2)
  let effects = executeAssuredAccumulation(fixture.queue, short)
  assert effects.error == AssuredExecutionError.RunnerFailure
  assert effects.runnerFailure.error == AccumulationRunnerError.CompletionFailure
  assert effects.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
  assert effects.runnerFailure.completionFailure.batchFailure.error ==
      AccumulationBatchError.LimitExceeded
  assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
  storage(original, expectedFirst)
  assert uint32(metadata(original).lastAccumulation) == 2
  fixture

let modes = [ComputedStorageMode.FetchFirst, ComputedStorageMode.FetchSecond,
    ComputedStorageMode.FetchMissing]
var fixtures: seq[AssuredOutcomeFixture] = @[]
for mode in modes: fixtures.add(witness(mode)) # Each distinct original guest is committed/refined/signed before its actual operands exist.
proc cycle(fixtures: openArray[AssuredOutcomeFixture]) =
  ## Fetch real operands, execute, compose, publish and release every selected or absent-input guest per ownership cycle.
  for fixture in fixtures:
    let source = compose(execute(fixture))
    var state = fixture.state
    var view = fixture.view
    let published = advanceAssuredChain(state, view, source)
    assert published.error == AssuredChainError.None
cycle(fixtures)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixtures) # Three actual guest input-consumption paths and all private/public successor owners retire each cycle.
let after = getOccupiedMem()
assert before == after, "assured inputs ARC release"
recordArcRelease("pvm_assured_inputs", 1000, before, after)
echo "PVM assured inputs passed"
echo "ARC_RELEASE cycles=1000 unchanged"
