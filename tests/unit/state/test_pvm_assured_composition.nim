# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_composition_arc_release"}

## Genuine assured execution composes current history and bookkeeping without replaying guests or mutating the original parent.

import std/[assertions, syncio]
import ../../../src/state/[assured_composition, assured_execution, assured_queue,
  computed_assurances,
  accumulation_driver, accumulation_finalization, accumulation_outputs, accumulation_completion,
  accumulation_consensus, accumulation_execution, accumulation_round, accumulation_queue,
  accumulation_history, accumulation_activity, accumulation_validators,
  accumulation_continuation_inputs, accumulation_batch, validator_projection,
  accumulation_continuation,
  report_admission,
  block_transition, block_admission, report_assignments, store]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, assurances, state_layout, state_accounts, state_service_values,
  state_workqueues, state_statistics, report_owned]
import ../../../src/pvm/step
import ../../support/[pvm_assured_composition, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse real private root work only after genuine source execution and authentication have completed.
proc expect[T](outcome: AssuredCompositionResult[T], reason: AssuredCompositionError) =
  ## Keep the originating selected phase visible on unexpected refusal without weakening exact assertions.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == AssuredCompositionError.DriverFailure: echo "driver ",
        outcome.driverFailure.error
    if outcome.error == AssuredCompositionError.FinalizationFailure: echo "finalization ",
        outcome.finalizationFailure.error
    if outcome.error == AssuredCompositionError.CompositionFailure:
      let child = outcome.compositionFailure
      echo "composition ", child.error
      if child.error == AccumulationCompletionError.HistoryFailure: echo "history ",
          child.historyFailure.error
      if child.error == AccumulationCompletionError.ValidatorsFailure: echo "validators ",
          child.validatorsFailure.error
      if child.error == AccumulationCompletionError.ActivityFailure: echo "activity ",
          child.activityFailure.error
      if child.error == AccumulationCompletionError.ConsensusFailure: echo "consensus ",
          child.consensusFailure.error
  assert outcome.error == reason, "assured composition reason"
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode exact canonical account fields at the actual source, final and composed maps.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
proc storage(state: StateStoreSnapshot) =
  ## Preserve exact guest bytes and independently known one-key footprint through all private state phases.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @[21'u8, 22, 23]
  assert uint32(metadata(state).storageItems) == 1 and uint64(metadata(state).storageBytes) == 38
let source = assuredCompositionFixture()
let config = assuredCompositionConfig()
let initial = source.assuredExecutionCompleted.value
let original = source.assuredExecutionSource.value.assuredQueueAdmission.value.reportBlockStage.value.value.admitted.admittedState
let stage = source.assuredExecutionSource.value.assuredQueueAdmission.value.reportBlockStage.value.value
let paid = uint64(initial.executionInfo.value.gasUsed)
let outcome = composeAssuredState(source, config)
expect(outcome, AssuredCompositionError.None)
let done = outcome.value
assert done.assuredCompositionStopped.value.stoppedKind == StoppedAccumulationKind.Continuation
let final = done.assuredCompositionFinal.value
let facts = final.finalAccumulationInfo.value
assert uint64(facts.completedPrefix) == 2 and facts.pendingReports == 0
assert uint64(facts.remainingGas) == 1000000-paid
assert facts.outputs.rounds == 2 and facts.outputs.executions == 1
assert facts.outputs.outputs == 0 and facts.outputs.encodedBytes == 1
assert sameStateSnapshot(final.finalAccumulationParent.value, original)
storage(final.finalAccumulationState.value)
assert uint32(metadata(final.finalAccumulationState.value).lastAccumulation) == 2
let plan = done.assuredCompositionPlan.value
assert plan.accumulationConsensusInfo.value.chapters == 7
let state = plan.accumulationConsensusState.value
storage(state)
assert uint32(metadata(state).lastAccumulation) == 3
assert uint64(metadata(state).balance) == 50
assert array[32, byte](metadata(state).codeHash) == array[32, byte](metadata(original).codeHash)
assert uint64(metadata(state).minimumAccumulationGas) == uint64(metadata(
    original).minimumAccumulationGas)
assert uint64(metadata(state).minimumTransferGas) == uint64(metadata(original).minimumTransferGas)
assert state.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
assert state.lookup(chapterKey(StateChapter(10))).value.bytes ==
    source.assuredExecutionSource.value.assuredQueueAdmission.value.reportAssignments.value.reportAssignmentEntry.value.value
assert state.lookup(chapterKey(StateChapter(10))).value.bytes == stage.snapshot.lookup(chapterKey(
    StateChapter(10))).value.bytes
assert state.lookup(chapterKey(StateChapter(10))).value.bytes != original.lookup(chapterKey(
    StateChapter(10))).value.bytes
for chapter in [4'u8, 5, 6, 8, 9, 11]:
  assert state.lookup(chapterKey(StateChapter(chapter))).value.bytes == stage.snapshot.lookup(
      chapterKey(StateChapter(
      chapter))).value.bytes # Preserve the real authenticated prefix instead of reconstructing equal-root inputs.
let queueConfig = config.composition.ready.queues
let ready = decodeReadyState(state.lookup(chapterKey(StateChapter(14))).value.bytes,
    queueConfig).value.snapshot
assert ready.readyInfo.value.items == 0
let historical = decodeAccumulatedState(original.lookup(chapterKey(StateChapter(15))).value.bytes,
    queueConfig).value.snapshot
assert historical.accumulatedInfo.value.items == 1
let accumulated = decodeAccumulatedState(state.lookup(chapterKey(StateChapter(15))).value.bytes,
    queueConfig).value.snapshot
assert accumulated.accumulatedInfo.value.items == 3
for reportIndex in 0..<2:
  let queue = initial.executionRound.value.roundBlockQueue.value.accumulationProjection.value
  let hash = queue.accumulationAt(AccumulationIndex(uint64(
      reportIndex))).value.ownedReportInfo.value.header.packageHash.bytes
  var occurrences = 0
  for slot in 0..<12:
    for index in 0..<accumulated.accumulatedSlotCount(WorkQueueSlot(uint64(slot))).value:
      if accumulated.accumulatedHashAt(WorkQueueSlot(uint64(slot)), WorkQueueHashIndex(uint64(
          index))).value.bytes ==
          hash: inc occurrences # Both genuinely assured packages occur once, not merely any two extra hashes.
  assert occurrences == 1
for slot in 0..<12:
  for index in 0..<historical.accumulatedSlotCount(WorkQueueSlot(uint64(slot))).value:
    let hash = historical.accumulatedHashAt(WorkQueueSlot(uint64(slot)), WorkQueueHashIndex(uint64(
        index))).value.bytes
    var occurrences = 0
    for nextSlot in 0..<12:
      for nextIndex in 0..<accumulated.accumulatedSlotCount(WorkQueueSlot(uint64(nextSlot))).value:
        if accumulated.accumulatedHashAt(WorkQueueSlot(uint64(nextSlot)), WorkQueueHashIndex(uint64(
            nextIndex))).value.bytes ==
            hash: inc occurrences # Previously accumulated work is retained once across the successor boundary.
    assert occurrences == 1
let activity = decodeActivityState(state.lookup(chapterKey(StateChapter(13))).value.bytes,
  ActivityConfig(cores: CoreCount(3), current: ValidatorCount(9), previous: ValidatorCount(6),
      maxServices: ElementLimit(4), maxBytes: ByteLimit(10000))).value.snapshot
let service = activity.serviceActivityAt(StatisticsServiceIndex(0)).value
assert uint32(service.service) == 42
assert uint64(service.statistics.counters[ServiceMeasure.RefinementCount]) == 0
assert uint64(service.statistics.counters[ServiceMeasure.AccumulationCount]) == 2
assert uint64(service.statistics.accumulationGas) == paid
var blocks = 0'u64
var guarantees = 0'u64
var assuranceCount = 0'u64
for index in 0..<9:
  let counters = activity.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(
      uint64(index))).value
  blocks += uint64(uint32(counters[ValidatorMeasure.Blocks]))
  guarantees += uint64(uint32(counters[ValidatorMeasure.Guarantees]))
  assuranceCount += uint64(uint32(counters[ValidatorMeasure.Assurances])) # Seven actual signatures contribute once to the preserved validator epoch counters.
assert blocks == 2 and guarantees == 6 and assuranceCount == 7
for field in low(Parameter)..high(Parameter):
  assert done.assuredCompositionParameters.value.get(field) ==
      source.assuredExecutionParameters.value.get(
      field) # Keep the entire original tuple, not just the fields read by this layer.
assert sameStateSnapshot(done.assuredCompositionSource.value.assuredExecutionSource.value.assuredQueueAdmission.value.reportBlockStage.value.value.admitted.admittedState, original)
assert uint32(metadata(original).lastAccumulation) == 2
var idle = config
idle.driver.execution.steps = ExecutionStepLimit(0)
expect(composeAssuredState(source, idle), AssuredCompositionError.None)
let emptySource = assuredCompositionFixture(votes = 6)
let empty = composeAssuredState(emptySource, config)
expect(empty, AssuredCompositionError.None)
assert uint64(empty.value.assuredCompositionFinal.value.finalAccumulationInfo.value.completedPrefix) == 0
assert uint64(empty.value.assuredCompositionFinal.value.finalAccumulationInfo.value.remainingGas) == 1000000
assert uint32(metadata(empty.value.assuredCompositionPlan.value.accumulationConsensusState.value).lastAccumulation) == 2
expect(composeAssuredState(default(ExecutedAssuredAccumulation), config),
    AssuredCompositionError.InvalidSource)
var short = config
short.driver.preparation.selection.executions = ElementLimit(0)
let driver = composeAssuredState(source, short)
expect(driver, AssuredCompositionError.DriverFailure)
assert driver.driverFailure.error == AccumulationDriverError.SelectionFailure
assert driver.driverFailure.selectionFailure.error == AccumulationContinuationError.LimitExceeded
short = config
short.outputs.rounds = ElementLimit(1)
let outputs = composeAssuredState(source, short)
expect(outputs, AssuredCompositionError.FinalizationFailure)
assert outputs.finalizationFailure.error == AccumulationFinalizationError.OutputFailure
assert outputs.finalizationFailure.outputError == AccumulationOutputsError.LimitExceeded
short = config
short.composition.history.reports = ElementLimit(1)
let history = composeAssuredState(source, short)
expect(history, AssuredCompositionError.CompositionFailure)
assert history.compositionFailure.error == AccumulationCompletionError.HistoryFailure
assert history.compositionFailure.historyFailure.error == AccumulationHistoryError.LimitExceeded
short = config
short.composition.validators.projection.assurances = ElementLimit(6)
let assuranceLimit = composeAssuredState(source, short)
expect(assuranceLimit, AssuredCompositionError.CompositionFailure)
assert assuranceLimit.compositionFailure.error == AccumulationCompletionError.ValidatorsFailure
assert assuranceLimit.compositionFailure.validatorsFailure.error ==
    AccumulationValidatorsError.LimitExceeded
short = config
short.composition.validators.projection.rows = ElementLimit(14)
let rowLimit = composeAssuredState(source, short)
expect(rowLimit, AssuredCompositionError.CompositionFailure)
assert rowLimit.compositionFailure.error == AccumulationCompletionError.ValidatorsFailure
assert rowLimit.compositionFailure.validatorsFailure.error ==
    AccumulationValidatorsError.ProjectionFailure
short = config
short.composition.activity.available = ElementLimit(1)
let available = composeAssuredState(source, short)
expect(available, AssuredCompositionError.CompositionFailure)
assert available.compositionFailure.error == AccumulationCompletionError.ActivityFailure
assert available.compositionFailure.activityFailure.error == AccumulationActivityError.LimitExceeded
short = config
short.composition.consensus.chapterBytes = ByteLimit(0)
let late = composeAssuredState(source, short)
expect(late, AssuredCompositionError.CompositionFailure)
assert late.compositionFailure.error == AccumulationCompletionError.ConsensusFailure
failHash(1)
let backend = composeAssuredState(source, config)
expect(backend, AssuredCompositionError.DriverFailure)
assert backend.driverFailure.error == AccumulationDriverError.InputFailure
assert backend.driverFailure.inputFailure.error == AccumulationContinuationInputError.BatchFailure
assert backend.driverFailure.inputFailure.batchFailure.error == AccumulationBatchError.StoreFailure
assert backend.driverFailure.inputFailure.batchFailure.storeError == StateStoreError.BackendFailure
failHash(0)
assert sameStateSnapshot(final.finalAccumulationParent.value, original)
storage(original)
assert uint32(metadata(original).lastAccumulation) == 2
expect(default(ComposedAssuredState).assuredCompositionSource,
    AssuredCompositionError.Uninitialized)
expect(default(ComposedAssuredState).assuredCompositionStopped,
    AssuredCompositionError.Uninitialized)
expect(default(ComposedAssuredState).assuredCompositionFinal, AssuredCompositionError.Uninitialized)
expect(default(ComposedAssuredState).assuredCompositionPlan, AssuredCompositionError.Uninitialized)
expect(default(ComposedAssuredState).assuredCompositionParameters,
    AssuredCompositionError.Uninitialized)
var copied = done.assuredCompositionPlan.value
copied = default(PreparedAccumulationConsensus)
assert done.assuredCompositionPlan.value.accumulationConsensusInfo.value.chapters == 7
proc detached(): ComposedAssuredState =
  ## Preserve complete successor and original authenticated computation after caller-local fixture handles retire.
  composeAssuredState(assuredCompositionFixture(), assuredCompositionConfig()).value
let held = detached()
assert uint32(metadata(held.assuredCompositionPlan.value.accumulationConsensusState.value).lastAccumulation) == 3
proc cycle(source: ExecutedAssuredAccumulation, config: AssuredCompositionConfig) =
  ## Release every successful private state phase plus a late refused composed prefix without replaying the initial guests.
  let done = composeAssuredState(source, config).value
  discard done.assuredCompositionPlan.value.accumulationConsensusState.value
  discard done.assuredCompositionSource.value
  var short = config
  short.composition.consensus.chapterBytes = ByteLimit(0)
  expect(composeAssuredState(source, short), AssuredCompositionError.CompositionFailure)
cycle(source, config)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, config) # Actual stopped/finalized/composed histories and all late-refusal maps retire each cycle.
let after = getOccupiedMem()
assert before == after, "assured composition ARC release"
recordArcRelease("pvm_assured_composition", 1000, before, after)
echo "PVM assured composition passed"
echo "ARC_RELEASE cycles=1000 unchanged"
