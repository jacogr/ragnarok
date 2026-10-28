# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_composition_arc_release"}

## Real computed state composition preserves pending guarantees and authenticated prefix while consuming historical work once.

import std/assertions
import std/syncio
import ../../../src/state/computed_composition as state_computed_composition
import ../../../src/state/computed_finalization as state_computed_finalization
import ../../../src/state/computed_execution as state_computed_execution
import ../../../src/state/computed_round as state_computed_round
import ../../../src/state/computed_publication as state_computed_publication
import ../../../src/state/computed_admission as state_computed_admission
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/report_assignments as state_report_assignments
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_history as state_accumulation_history
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/accumulation_times as state_accumulation_times
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_statistics as codec_state_statistics
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../support/pvm_computed_composition
import ../../support/testing_arc_evidence

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
