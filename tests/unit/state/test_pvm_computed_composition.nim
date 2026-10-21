# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_composition_arc_release"}

## Real computed state composition preserves pending guarantees and authenticated prefix while consuming historical work once.

import std/[assertions, syncio]
import ../../../src/state/[computed_composition, computed_finalization, computed_execution,
  computed_round, computed_publication, computed_admission, report_admission, report_assignments,
  accumulation_completion, accumulation_consensus, accumulation_finalization,
  accumulation_execution,
  accumulation_history, accumulation_ready, accumulation_recent, accumulation_times,
  accumulation_round, accumulation_queue,
  accumulation_validators, accumulation_activity, accumulation_preimages,
  accumulation_authorization,
  block_transition, block_admission, store]
import ../../../src/codec/[bounded, state_layout, state_workqueues, state_statistics, assurances,
    report_owned, owned]
import ../../support/[pvm_computed_composition, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse real private map/root work after the full genuine source execution completes.
proc expect[T](outcome: ComputedCompositionResult[T], reason: ComputedCompositionError) =
  ## Print the originating maintained phase only on unexpected failure, without weakening the exact expected outcome.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == ComputedCompositionError.CompositionFailure:
      let child = outcome.compositionFailure
      echo "composition ", child.error
      if child.error == AccumulationCompletionError.HistoryFailure: echo "history ",
          child.historyFailure.error
      if child.error == AccumulationCompletionError.ReadyFailure: echo "ready ",
          child.readyFailure.error
      if child.error == AccumulationCompletionError.RecentFailure: echo "recent ",
          child.recentFailure.error
      if child.error == AccumulationCompletionError.TimesFailure: echo "times ",
          child.timesFailure.error
      if child.error == AccumulationCompletionError.ValidatorsFailure: echo "validators ",
          child.validatorsFailure.error
      if child.error == AccumulationCompletionError.ActivityFailure: echo "activity ",
          child.activityFailure.error
      if child.error == AccumulationCompletionError.PreimagesFailure: echo "preimages ",
          child.preimagesFailure.error
      if child.error == AccumulationCompletionError.AuthorizationFailure: echo "authorization ",
          child.authorizationFailure.error
      if child.error == AccumulationCompletionError.ConsensusFailure: echo "consensus ",
          child.consensusFailure.error
  assert outcome.error == reason, "computed composition reason"
let source = compositionFixture()
let limits = computedCompositionLimits()
let outcome = composeComputedState(source, limits)
expect(outcome, ComputedCompositionError.None)
let done = outcome.value
let plan = done.computedCompositionPlan.value
let state = plan.accumulationConsensusState.value
let final = source.computedFinalizationPlan.value
let admission = final.finalAccumulationAdmission.value
let stage = admission.reportBlockStage.value.value
let parent = final.finalAccumulationParent.value
assert state.lookup(chapterKey(StateChapter(10))).value.bytes ==
    admission.reportAssignments.value.reportAssignmentEntry.value.value
let pending = source.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSnapshot.value
assert state.lookup(chapterKey(StateChapter(10))).value.bytes == pending.lookup(chapterKey(
    StateChapter(10))).value.bytes
for chapter in [4'u8, 5, 6, 8, 9, 11]:
  assert state.lookup(chapterKey(StateChapter(chapter))).value.bytes == stage.snapshot.lookup(
      chapterKey(StateChapter(
      chapter))).value.bytes # Exact authenticated prefix, never an independently reconstructed map.
assert state.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
let queueConfig = limits.ready.queues
let ready = decodeReadyState(state.lookup(chapterKey(StateChapter(14))).value.bytes,
    queueConfig).value.snapshot
assert ready.readyInfo.value.items == 0
let accumulated = decodeAccumulatedState(state.lookup(chapterKey(StateChapter(15))).value.bytes,
    queueConfig).value.snapshot
assert accumulated.accumulatedInfo.value.items == 1
let initialQueue = source.computedFinalizationSource.value.computedExecutionSource.value.computedRoundPlan.value.roundBlockQueue.value.accumulationProjection.value
let historicalHash = ownedReportInfo(initialQueue.accumulationAt(AccumulationIndex(
    0)).value).value.header.packageHash.bytes
var occurrences = 0
for slot in 0..<12:
  for index in 0..<accumulated.accumulatedSlotCount(WorkQueueSlot(uint64(slot))).value:
    let selected = accumulated.accumulatedHashAt(WorkQueueSlot(uint64(slot)), WorkQueueHashIndex(
        uint64(index))).value
    if selected.bytes == historicalHash: inc occurrences # The exact actual historical work appears once, not just an arbitrary package count.
assert occurrences == 1
let activity = decodeActivityState(state.lookup(chapterKey(StateChapter(13))).value.bytes,
  ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6), previous: ValidatorCount(6),
    maxServices: ElementLimit(4), maxBytes: ByteLimit(10000))).value.snapshot
var blocks = 0'u64
var guarantees = 0'u64
for index in 0..<6:
  let counters = activity.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(
      uint64(index))).value
  blocks += uint64(uint32(counters[ValidatorMeasure.Blocks]))
  guarantees += uint64(uint32(counters[ValidatorMeasure.Guarantees])) # Six actual signer identities occur across the two current reports.
assert blocks == 1 and guarantees == 6
let service = activity.serviceActivityAt(StatisticsServiceIndex(0)).value
assert uint32(service.service) == 42
assert uint64(service.statistics.counters[ServiceMeasure.RefinementCount]) == 2
assert uint64(service.statistics.counters[ServiceMeasure.AccumulationCount]) == 1
let actualGas = source.computedFinalizationSource.value.computedExecutionCompleted.value.executionInfo.value.gasUsed
assert uint64(service.statistics.accumulationGas) == uint64(actualGas)
assert sameStateSnapshot(done.computedCompositionSource.value.computedFinalizationPlan.value.finalAccumulationParent.value, parent)
let missing = compositionFixture(withComposition = false)
let refused = composeComputedState(missing, limits)
expect(refused, ComputedCompositionError.CompositionFailure)
assert refused.compositionFailure.error == AccumulationCompletionError.ValidatorsFailure
assert refused.compositionFailure.validatorsFailure.error ==
    AccumulationValidatorsError.MissingState
expect(composeComputedState(default(FinalizedComputedAccumulation), limits),
    ComputedCompositionError.InvalidSource)
var short = limits
short.history.reports = ElementLimit(0)
let early = composeComputedState(source, short)
expect(early, ComputedCompositionError.CompositionFailure)
assert early.compositionFailure.error == AccumulationCompletionError.HistoryFailure
short = limits
short.consensus.chapterBytes = ByteLimit(0)
let late = composeComputedState(source, short)
expect(late, ComputedCompositionError.CompositionFailure)
assert late.compositionFailure.error == AccumulationCompletionError.ConsensusFailure
reset(1)
let backend = composeComputedState(source, limits)
expect(backend, ComputedCompositionError.CompositionFailure)
assert backend.compositionFailure.error == AccumulationCompletionError.HistoryFailure
assert backend.compositionFailure.historyFailure.error == AccumulationHistoryError.StateFailure
assert backend.compositionFailure.historyFailure.stateError == StateStoreError.BackendFailure
reset(0)
assert sameStateSnapshot(final.finalAccumulationParent.value, parent)
var copied = done.computedCompositionPlan.value
copied = default(PreparedAccumulationConsensus)
assert done.computedCompositionPlan.value.accumulationConsensusInfo.value.chapters == 7
expect(default(ComposedComputedState).computedCompositionSource,
    ComputedCompositionError.Uninitialized)
expect(default(ComposedComputedState).computedCompositionPlan,
    ComputedCompositionError.Uninitialized)
proc detached(): ComposedComputedState =
  ## Retain actual composed state and original computed/terminal provenance after fixture handles retire.
  composeComputedState(compositionFixture(), computedCompositionLimits()).value
let held = detached()
assert held.computedCompositionPlan.value.accumulationConsensusInfo.value.chapters == 7
proc cycle(source: FinalizedComputedAccumulation, limits: AccumulationCompositionLimits) =
  ## Release all private maintained phase maps and retained computed source references each iteration.
  let composed = composeComputedState(source, limits).value
  discard composed.computedCompositionPlan.value.accumulationConsensusState.value
  discard composed.computedCompositionSource.value
cycle(source, limits)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, limits) # Complete state phase histories retire on every bounded iteration.
let after = getOccupiedMem()
assert before == after, "computed composition ARC release"
recordArcRelease("pvm_computed_composition", 1000, before, after)
echo "PVM computed composition passed"
echo "ARC_RELEASE cycles=1000 unchanged"
