# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind current final C14 ready state to original admitted rings, availability/time and actually processed package identities.
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/header as codec_header
import ../codec/report_owned as codec_report_owned
import ../codec/state_workqueues as codec_state_workqueues
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ./accumulation_current_finalization as state_accumulation_current_finalization
import ./accumulation_current_accounts as state_accumulation_current_accounts
import ./accumulation_current_statistics as state_accumulation_current_statistics
import ./accumulation_current_driver as state_accumulation_current_driver
import ./accumulation_current_sequence as state_accumulation_current_sequence
import ./accumulation_current_round as state_accumulation_current_round
import ./accumulation_block_guests as state_accumulation_block_guests
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./availability as state_availability
import ./accumulation_ready as state_accumulation_ready
import ./store as state_store

type
  CurrentAccumulationReadyError* {.pure.} = enum ## Failed/default alternatives retain no partial ring, source or successor map.
    Uninitialized, None, InvalidSource, InvalidConfig, MissingState, InvalidState,
      LimitExceeded, CodecFailure, ProjectionFailure, StateFailure
  CurrentReadyData = ref object # Exact current finalization, captured ready ring and private successor form an acyclic graph.
    source: PreparedCurrentAccumulationFinalization
    ring: ReadySnapshot
    state: StateStoreSnapshot
  PreparedCurrentAccumulationReady* = object ## Only current terminal C15/C16 finalization authorizes this selected-state C14 successor.
    data: nil CurrentReadyData
  CurrentAccumulationReadyResult*[T] = object ## Private alternatives carry actual failures without earlier successful prefixes.
    case status: CurrentAccumulationReadyError
    of None:
      completed: T
    of CodecFailure:
      codecReason: WorkQueueError
    of ProjectionFailure:
      projectionReason: AccumulationReadyResult[AccumulationReadyProjection]
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # No synthetic initialized empty map/ring after refusal.
func error*[T](outcome: CurrentAccumulationReadyResult[T]): CurrentAccumulationReadyError =
  ## Inspect only the immutable selected reason.
  outcome.status
func value*[T](outcome: CurrentAccumulationReadyResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationReadyError.None.} =
  ## Extract only complete selected ownership or copied observations.
  outcome.completed
func codecFailure*[T](outcome: CurrentAccumulationReadyResult[T]): WorkQueueError {.inline,
    requires: outcome.status == CurrentAccumulationReadyError.CodecFailure.} =
  ## Preserve the actual original-parent ring capture refusal.
  outcome.codecReason
func projectionFailure*[T](outcome: CurrentAccumulationReadyResult[T]): AccumulationReadyResult[
    AccumulationReadyProjection] {.inline,

requires: outcome.status == CurrentAccumulationReadyError.ProjectionFailure.} =
  ## Preserve the actual failed pure ready equation, never a successful prefix.
  outcome.projectionReason
func stateFailure*[T](outcome: CurrentAccumulationReadyResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationReadyError.StateFailure.} =
  ## Preserve only the actual private successor-store refusal.
  outcome.stateReason
proc prepareCurrentAccumulationReady*(source: PreparedCurrentAccumulationFinalization,
    config: AccumulationReadyConfig): CurrentAccumulationReadyResult[
        PreparedCurrentAccumulationReady] =
  ## Original parent rings, authenticated availability/time and final processed set belong to one terminal source.
  template fail(reason: CurrentAccumulationReadyError) =
    return CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady](status: reason)
  if source.currentFinalizationInfo.error != CurrentAccumulationFinalizationError.None:
    fail(CurrentAccumulationReadyError.InvalidSource) # No caller-authored ring, replacement parent or detached processed set is accepted.
  let completed = source.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let bound = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value
  let stage = bound.accumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(profile.cores) != uint64(config.queues.cores) or
      uint64(profile.epochSlots) != uint64(config.queues.epochSlots):
    fail(CurrentAccumulationReadyError.InvalidConfig) # Reject mismatched profiles before any chapter copies.
  let step = stage.value
  let parent = step.admitted.admittedState
  let ready = parent.lookup(chapterKey(StateChapter(14)))
  let accumulated = parent.lookup(chapterKey(StateChapter(15)))
  if ready.error == StateStoreError.MissingKey or accumulated.error == StateStoreError.MissingKey:
    fail(CurrentAccumulationReadyError.MissingState) # Never replace absent chapters with empty rings.
  if ready.error != StateStoreError.None or accumulated.error != StateStoreError.None:
    fail(CurrentAccumulationReadyError.InvalidState) # Require complete parent access.
  if uint64(ready.value.byteLength) > uint64(config.queues.maxBytes) or
      uint64(accumulated.value.byteLength) > uint64(config.queues.maxBytes):
    fail(CurrentAccumulationReadyError.LimitExceeded) # Bound stored-byte copies first.
  let readyBytes = ready.value.bytes
  let accumulatedBytes = accumulated.value.bytes
  let decodedReady = decodeReadyState(readyBytes, config.queues)
  let decodedAccumulated = decodeAccumulatedState(accumulatedBytes, config.queues)
  for reason in [decodedReady.error, decodedAccumulated.error]:
    if reason != WorkQueueError.None:
      return CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady](
        status: CurrentAccumulationReadyError.CodecFailure,
        codecReason: reason) # Failed chapter capture never authorizes partial projection.
  if decodedReady.value.consumed != readyBytes.len or decodedAccumulated.value.consumed !=
      accumulatedBytes.len:
    fail(CurrentAccumulationReadyError.InvalidState) # Chapter prefixes with trailing bytes are invalid.
  let count = step.availability.availableReportCount
  let ring = source.currentFinalizationHistory.value
  let last = WorkQueueSlot(uint64(profile.epochSlots)-1)
  let processedCount = ring.accumulatedSlotCount(last).value
  if uint64(count) > uint64(config.items):
    fail(CurrentAccumulationReadyError.LimitExceeded) # Bound availability traversal before allocation.
  if uint64(processedCount) > uint64(config.items)-uint64(count):
    fail(CurrentAccumulationReadyError.LimitExceeded) # Charge the certified processed set without overflow.
  if count > high(int) div sizeof(OwnedReport) or processedCount > high(int) div sizeof(PackageHash):
    fail(CurrentAccumulationReadyError.LimitExceeded) # Bound native adapter descriptors before allocation.
  var available = newSeq[OwnedReport](count)
  for index in 0..<count: available[index] = step.availability.availableReportAt(index).value
  var processed = newSeq[PackageHash](processedCount)
  for index in 0..<processedCount: processed[index] = ring.accumulatedHashAt(last,
      WorkQueueHashIndex(uint64(index))).value
  let projected = projectAccumulationReady(decodedReady.value.snapshot,
    decodedAccumulated.value.snapshot,
    available, processed, headerInfo(step.admitted.admittedParent).value.unsigned.slot,
    headerInfo(step.admitted.admittedHeader).value.unsigned.slot, config)
  if projected.error != AccumulationReadyError.None:
    return CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady](
      status: CurrentAccumulationReadyError.ProjectionFailure,
      projectionReason: projected) # Full parent/input work policies apply even when removal/expiry shrinks output.
  var working = forkStateStore(source.currentFinalizationState.value).value # Genuine finalization retains the complete selected map and inherited store ceilings.
  let applied = working.apply([StateWrite(key: projected.value.entry.key, kind: StateWriteKind.Put,
    value: projected.value.entry.value)])
  if applied.error != StateStoreError.None:
    return CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady](
      status: CurrentAccumulationReadyError.StateFailure,
      stateReason: applied.error) # No ready-only map prefix survives a failed private apply.
  CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady](
    status: CurrentAccumulationReadyError.None,
    completed: PreparedCurrentAccumulationReady(data: CurrentReadyData(source: source,
      ring: projected.value.ring, state: applied.value)))

proc currentReadySource*(ready: PreparedCurrentAccumulationReady): CurrentAccumulationReadyResult[
    PreparedCurrentAccumulationFinalization] =
  ## Retain the immutable same-source source; default owners grant no initialized observation.
  let data = ready.data
  if data == nil: return CurrentAccumulationReadyResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationReadyError.Uninitialized) # No synthetic successor.
  CurrentAccumulationReadyResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationReadyError.None, completed: data.source)

proc currentReadyRing*(ready: PreparedCurrentAccumulationReady): CurrentAccumulationReadyResult[
    ReadySnapshot] =
  ## Retain the immutable same-source ring; default owners grant no initialized observation.
  let data = ready.data
  if data == nil: return CurrentAccumulationReadyResult[ReadySnapshot](
      status: CurrentAccumulationReadyError.Uninitialized) # No synthetic successor.
  CurrentAccumulationReadyResult[ReadySnapshot](status: CurrentAccumulationReadyError.None,
      completed: data.ring)

proc currentReadyState*(ready: PreparedCurrentAccumulationReady): CurrentAccumulationReadyResult[
    StateStoreSnapshot] =
  ## Retain the immutable same-source state; default owners grant no initialized observation.
  let data = ready.data
  if data == nil: return CurrentAccumulationReadyResult[StateStoreSnapshot](
      status: CurrentAccumulationReadyError.Uninitialized) # No synthetic successor.
  CurrentAccumulationReadyResult[StateStoreSnapshot](status: CurrentAccumulationReadyError.None,
      completed: data.state)

proc currentReadyEntry*(ready: PreparedCurrentAccumulationReady): CurrentAccumulationReadyResult[StateEntry] =
  ## Copy complete C14 bytes from the private successor; caller mutation cannot affect the retained ring/map.
  let data = ready.data
  if data == nil: return CurrentAccumulationReadyResult[StateEntry](
      status: CurrentAccumulationReadyError.Uninitialized) # No default empty encoding.
  let key = chapterKey(StateChapter(14))
  CurrentAccumulationReadyResult[StateEntry](status: CurrentAccumulationReadyError.None,
    completed: StateEntry(key: key, value: data.state.lookup(key).value.bytes))
