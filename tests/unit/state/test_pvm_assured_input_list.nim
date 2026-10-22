# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_input_list_arc_release"}

## Real guest consumption of compact list counts ignores item indices and retains full capture provenance through canonical publication.

import std/[assertions, syncio]
import ../../../src/state/[assured_chain, assured_composition, assured_execution, assured_queue,
  accumulation_execution, accumulation_round, accumulation_inputs, accumulation_batch,
  accumulation_provisions, accumulation_outcome, accumulation_context, accumulation_effects,
  accumulation_consensus, accumulation_runner, accumulation_dispatch, store]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, c2_records, state_accounts, state_layout, state_service_values,
  state_workqueues, state_statistics]
import ../../../src/pvm/machine
import ../../support/[pvm_assured_outcomes, pvm_computed_storage_program,
  pvm_assured_execution, pvm_assured_composition, arc_evidence]

proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode actual canonical account fields at each state owner rather than substitute copied observations.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot, expected: openArray[byte]) =
  ## Exact prefix bytes include the list count and first record tag; footprint remains one three-byte value.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @expected
  assert uint32(metadata(state).storageItems) == 1 and uint64(metadata(state).storageBytes) == 38
proc listPrefix(completed: CompletedBlockAccumulation, count: byte): seq[byte] =
  ## Small counts are one literal compact byte, followed by operand tag0 then its actual package-hash byte.
  let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
  let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert service.operands == int(count) and service.transfers == 0
  let first = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(0)).value
  assert first.kind == AccumulationKind.Operand
  @[count, 0'u8, first.operand.operandInfo.value.packageHash.bytes[0]]
proc execute(fixture: AssuredOutcomeFixture): ExecutedAssuredAccumulation =
  ## Run the actual list-fetch guest with retained inputs and unchanged original parameter authority.
  let outcome = executeAssuredAccumulation(fixture.queue, assuredExecutionConfig(fixture.queue))
  if outcome.error != AssuredExecutionError.None: echo "input-list execution ", outcome.error
  assert outcome.error == AssuredExecutionError.None
  outcome.value
proc compose(source: ExecutedAssuredAccumulation): ComposedAssuredState =
  ## Stop and compose the real selected list-prefix write without replaying the initial guest.
  let outcome = composeAssuredState(source, assuredCompositionConfig())
  if outcome.error != AssuredCompositionError.None: echo "input-list composition ", outcome.error
  assert outcome.error == AssuredCompositionError.None
  outcome.value
let fixture = assuredOutcomeFixture(ComputedStorageMode.FetchList)
let original = fixture.state.snapshot.value
let oldView = fixture.view
let expectedFirst = listPrefix(fixture.first, 1)
storage(original, expectedFirst)
let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
storage(first.outcomeContext.value.effectAccounts.value, expectedFirst)
let executed = execute(fixture)
let completed = executed.assuredExecutionCompleted.value
let expected = listPrefix(completed, 2)
assert expected != expectedFirst and expected[0] == 2 and expected[1] == 0
let info = completed.executionInfo.value
assert info.services == 1 and info.batch.executions == 1 and info.batch.completeInputs
assert info.batch.selfWrites == 1 and info.batch.selfValueBytes == 3
assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
assert uint64(info.gasUsed) > 2736 and uint64(info.gasUsed) <= 3733
let selected = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
assert selected.outcomeInfo.value.termination == AccumulationTermination.Halt
assert selected.outcomeInfo.value.dimension == AccumulationDimension.Regular
assert not selected.outcomeInfo.value.hasYield
assert uint64(selected.outcomeInfo.value.gasUsed) == uint64(info.gasUsed)
storage(selected.outcomeContext.value.effectAccounts.value, expected)
let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
var wireBytes = 1'u64
let config = assuredExecutionConfig(fixture.queue)
for index in 0..<2:
  let input = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(uint64(index))).value
  let measured = ownedOperandSize(input.operand, config.runner.fetch.operand)
  assert measured.error == RecordError.None and measured.value > 0 and measured.value <= 4000
  wireBytes += uint64(measured.value) # Exactly two individually bounded records plus the known one-byte count prove this sum fits.
var exact = config
exact.runner.fetch.bytes = ByteLimit(wireBytes)
exact.runner.copyBytes = MemoryByteLimit(3)
let exactResult = executeAssuredAccumulation(fixture.queue, exact)
assert exactResult.error == AssuredExecutionError.None
storage(exactResult.value.assuredExecutionCompleted.value.executionBatch.value.batchOutcomeAt(
    AccumulationProvisionSourceIndex(0)).value.outcomeContext.value.effectAccounts.value, expected)
exact.runner.fetch.bytes = ByteLimit(wireBytes-1)
let shortList = executeAssuredAccumulation(fixture.queue, exact)
assert shortList.error == AssuredExecutionError.RunnerFailure
assert shortList.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert shortList.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
exact = config
exact.runner.copyBytes = MemoryByteLimit(2)
let shortCopy = executeAssuredAccumulation(fixture.queue, exact)
assert shortCopy.error == AssuredExecutionError.RunnerFailure
assert shortCopy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert shortCopy.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
exact = config
exact.runner.completion.batch.selfValueBytes = ByteLimit(2)
let shortEffect = executeAssuredAccumulation(fixture.queue, exact)
assert shortEffect.error == AssuredExecutionError.RunnerFailure
assert shortEffect.runnerFailure.error == AccumulationRunnerError.CompletionFailure
assert shortEffect.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
assert shortEffect.runnerFailure.completionFailure.batchFailure.error ==
    AccumulationBatchError.LimitExceeded
let composed = compose(executed)
let candidate = composed.assuredCompositionPlan.value.accumulationConsensusState.value
storage(candidate, expected)
assert uint32(metadata(candidate).lastAccumulation) == 3 and uint64(metadata(candidate).balance) == 50
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
storage(published.value.assuredChainSnapshot.value, expected)
for field in low(Parameter)..high(Parameter):
  assert published.value.assuredChainBlock.value.chainParameters.get(field) ==
      executed.assuredExecutionParameters.value.get(
      field) # List framing never supplies replacement protocol authority.
assert sameStateSnapshot(fixture.state.snapshot.value, original) and sameChainView(fixture.view, oldView)
storage(original, expectedFirst)
assert uint32(metadata(original).lastAccumulation) == 2
proc detached(): AdvancedAssuredChain =
  ## Retain the actual guest-derived canonical child after fixture/source/caller handles retire.
  let fixture = assuredOutcomeFixture(ComputedStorageMode.FetchList)
  let source = compose(execute(fixture))
  var state = fixture.state
  var view = fixture.view
  advanceAssuredChain(state, view, source).value
let held = detached()
assert held.assuredChainSnapshot.value.lookup(serviceStorageKey(ServiceIndex(42), @[11'u8],
    ByteLimit(1)).value).value.bytes[0] == 2
proc cycle(fixture: AssuredOutcomeFixture) =
  ## Fetch a full actual report list, compose its storage prefix and release canonical/source owners every cycle.
  let source = compose(execute(fixture))
  var state = fixture.state
  var view = fixture.view
  let published = advanceAssuredChain(state, view, source)
  assert published.error == AssuredChainError.None
cycle(fixture)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixture) # Each cycle includes real PVM execution, termination, all state phases and direct-child capture.
let after = getOccupiedMem()
assert before == after, "assured input list ARC release"
recordArcRelease("pvm_assured_input_list", 1000, before, after)
echo "PVM assured input list passed"
echo "ARC_RELEASE cycles=1000 unchanged"
