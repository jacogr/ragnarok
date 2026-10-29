# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind current timestamped accounts, terminal C16 output and exact processed C15 history on one private selected-state fork.
import ../../../codec/[bounded, composite, report_owned]
import ../../../codec/state/[layout as state_layout, outputs as state_outputs,
    workqueues as state_workqueues]
import ../../../codec/work/digest as work_digest
import ./[accounts as accumulation_current_accounts, statistics as accumulation_current_statistics,
    outputs as accumulation_current_outputs, driver as accumulation_current_driver,
    sequence as accumulation_current_sequence, round as accumulation_current_round]
import "../block/guests" as accumulation_block_guests
import ../[round as accumulation_round, queue as accumulation_queue,
    operands as accumulation_operands]
import ../../report/admission as report_admission
import "../../block/transition" as block_transition
import ../history as accumulation_history
import ../../store

type
  CurrentAccumulationFinalizationConfig* = object ## All values are local ceilings; original queue, completed prefix and chain shape come from the source.
    outputs*: CurrentAccumulationOutputLimits
    history*: AccumulationHistoryConfig
  CurrentAccumulationFinalizationInfo* = object ## Current accumulation progress does not claim C14/C13 or whole-block publication.
    processed*: AccumulationReportPrefix
    pendingReports*: int
    budget*: Gas
    history*: AccumulationHistoryInfo
    outputs*: CurrentAccumulationOutputsInfo
  CurrentAccumulationFinalizationError* {.pure.} = enum ## Failures retain only actual reasons and never an earlier successor prefix.
    Uninitialized, None, InvalidSource, InvalidConfig, MissingState, InvalidState,
      LimitExceeded, OutputFailure, QueueFailure, ProjectionFailure, StateFailure
  CurrentFinalizationData = ref object # Same-source account/output owners, complete private map and immutable history form an acyclic graph.
    accounts: PreparedCurrentAccumulationAccounts
    outputs: PreparedCurrentAccumulationOutputs
    ring: AccumulatedSnapshot
    state: StateStoreSnapshot
    info: CurrentAccumulationFinalizationInfo
  PreparedCurrentAccumulationFinalization* = object ## This current selected-state successor remains distinct from complete block publication and legacy completion.
    data: nil CurrentFinalizationData
  CurrentAccumulationFinalizationResult*[T] = object ## Private alternatives expose no successful component when another phase refuses.
    case status: CurrentAccumulationFinalizationError
    of None:
      completed: T
    of OutputFailure:
      outputReason: CurrentAccumulationOutputsResult[PreparedCurrentAccumulationOutputs]
    of QueueFailure:
      queueReason: WorkQueueError
    of ProjectionFailure:
      projectionReason: AccumulationHistoryResult[AccumulationHistoryProjection]
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Default, shape, missing and local-cap refusals carry reasons alone.

func error*[T](outcome: CurrentAccumulationFinalizationResult[
    T]): CurrentAccumulationFinalizationError =
  ## Inspect only the immutable selected reason.
  outcome.status
func value*[T](outcome: CurrentAccumulationFinalizationResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationFinalizationError.None.} =
  ## Extract only complete selected success.
  outcome.completed
func outputFailure*[T](outcome: CurrentAccumulationFinalizationResult[
    T]): CurrentAccumulationOutputsResult[PreparedCurrentAccumulationOutputs] {.inline,

requires: outcome.status == CurrentAccumulationFinalizationError.OutputFailure.} =
  ## Preserve the actual failed terminal pair union, never its successful prefix.
  outcome.outputReason
func queueFailure*[T](outcome: CurrentAccumulationFinalizationResult[T]): WorkQueueError {.inline,
    requires: outcome.status == CurrentAccumulationFinalizationError.QueueFailure.} =
  ## Preserve the actual parent C15 decoder refusal.
  outcome.queueReason
func projectionFailure*[T](outcome: CurrentAccumulationFinalizationResult[
    T]): AccumulationHistoryResult[AccumulationHistoryProjection] {.inline,

requires: outcome.status == CurrentAccumulationFinalizationError.ProjectionFailure.} =
  ## Preserve the actual failed pure history projection.
  outcome.projectionReason
func stateFailure*[T](outcome: CurrentAccumulationFinalizationResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationFinalizationError.StateFailure.} =
  ## Preserve the actual atomic private-store refusal.
  outcome.stateReason
proc prepareCurrentAccumulationFinalization*(accounts: PreparedCurrentAccumulationAccounts,
    config: CurrentAccumulationFinalizationConfig): CurrentAccumulationFinalizationResult[
        PreparedCurrentAccumulationFinalization] =
  ## Derive output, original processed report identities and history profile from one genuine timestamped terminal source.
  template fail(reason: CurrentAccumulationFinalizationError) =
    return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](status: reason)
  if accounts.currentAccountsInfo.error != CurrentAccumulationAccountError.None:
    fail(CurrentAccumulationFinalizationError.InvalidSource) # No caller-authored prior, detached pairs or independently completed queue is accepted.
  let completed = accounts.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let bound = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value
  let profile = bound.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  if uint64(config.history.queues.cores) != uint64(profile.cores) or
      uint64(config.history.queues.epochSlots) != uint64(profile.epochSlots):
    fail(CurrentAccumulationFinalizationError.InvalidConfig) # Empty output/history still belongs to the authenticated chain shape.
  let info = sequence.currentSequenceInfo.value
  let processed = uint64(info.processedReports)
  if processed > uint64(config.history.reports) or processed > uint64(high(int) div sizeof(PackageHash)):
    fail(CurrentAccumulationFinalizationError.LimitExceeded) # Bound original prefix traversal and all fixed hash storage first.
  let collected = prepareCurrentAccumulationOutputs(completed, config.outputs)
  if collected.error != CurrentAccumulationOutputsError.None:
    return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationFinalizationError.OutputFailure,
      outputReason: collected) # No successful timestamped map is exposed through this refusal.
  let prior = accounts.currentAccountsState.value
  let stored = prior.lookup(chapterKey(StateChapter(15)))
  if stored.error == StateStoreError.MissingKey:
    fail(CurrentAccumulationFinalizationError.MissingState) # Absence is never an initialized empty history ring.
  if stored.error != StateStoreError.None:
    fail(CurrentAccumulationFinalizationError.InvalidState) # Require complete-map metadata access.
  if uint64(stored.value.byteLength) > uint64(config.history.queues.maxBytes):
    fail(CurrentAccumulationFinalizationError.LimitExceeded) # Bound copied original chapter bytes, not only its shrunken successor.
  let bytes = stored.value.bytes
  let parent = decodeAccumulatedState(bytes, config.history.queues)
  if parent.error != WorkQueueError.None:
    return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationFinalizationError.QueueFailure,
      queueReason: parent.error) # Never reinterpret malformed parent bytes as an empty ring.
  if parent.value.consumed != bytes.len:
    fail(CurrentAccumulationFinalizationError.InvalidState) # Stored chapters require exact consumption.
  let queue = bound.accumulationProjection.value
  var packages = newSeq[PackageHash](int(processed))
  for index in 0..<packages.len:
    packages[index] = queue.accumulationAt(AccumulationIndex(uint64(
        index))).value.ownedReportInfo.value.header.packageHash # Only original processed identities enter the final history row.
  let projected = projectAccumulationHistory(parent.value.snapshot, packages, config.history)
  if projected.error != AccumulationHistoryError.None:
    return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationFinalizationError.ProjectionFailure,
      projectionReason: projected) # Preserve the exact pure input/output ring refusal.
  let output = collected.value.currentOutputsEntry.value
  var working = forkStateStore(prior).value # Genuine account ownership retains the complete map and inherited storage policy.
  let applied = working.apply([StateWrite(key: projected.value.entry.key, kind: StateWriteKind.Put,
      value: projected.value.entry.value),
    StateWrite(key: output.key, kind: StateWriteKind.Put, value: output.value)])
  if applied.error != StateStoreError.None:
    return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](
      status: CurrentAccumulationFinalizationError.StateFailure,
      stateReason: applied.error) # No C15-only or C16-only map prefix survives backend/cap failure.
  let ring = projected.value.ring
  let historyInfo = ring.accumulatedInfo.value
  let terminal = completed.completedSequencePlan.value.currentContinuationInfo.value
  CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization](
    status: CurrentAccumulationFinalizationError.None,
    completed: PreparedCurrentAccumulationFinalization(data: CurrentFinalizationData(
      accounts: accounts,
      outputs: collected.value, ring: ring, state: applied.value,
      info: CurrentAccumulationFinalizationInfo(processed: info.processedReports,
        pendingReports: terminal.pendingReports, budget: info.budget,
        history: AccumulationHistoryInfo(processedReports: int(processed),
          newPackages: ring.accumulatedSlotCount(WorkQueueSlot(uint64(historyInfo.slots-1))).value,
          slots: historyInfo.slots, packages: historyInfo.items),
              outputs: collected.value.currentOutputsInfo.value))))

proc currentFinalizationInfo*(finalized: PreparedCurrentAccumulationFinalization): CurrentAccumulationFinalizationResult[
    CurrentAccumulationFinalizationInfo] =
  ## Retain the exact immutable info projection; default finalization grants no initialized successor.
  let data = finalized.data
  if data == nil: return CurrentAccumulationFinalizationResult[CurrentAccumulationFinalizationInfo](
      status: CurrentAccumulationFinalizationError.Uninitialized) # No synthetic completion.
  CurrentAccumulationFinalizationResult[CurrentAccumulationFinalizationInfo](
      status: CurrentAccumulationFinalizationError.None, completed: data.info)

proc currentFinalizationAccounts*(finalized: PreparedCurrentAccumulationFinalization): CurrentAccumulationFinalizationResult[
    PreparedCurrentAccumulationAccounts] =
  ## Retain the exact immutable accounts projection; default finalization grants no initialized successor.
  let data = finalized.data
  if data == nil: return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationAccounts](
      status: CurrentAccumulationFinalizationError.Uninitialized) # No synthetic completion.
  CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationAccounts](
      status: CurrentAccumulationFinalizationError.None, completed: data.accounts)

proc currentFinalizationOutputs*(finalized: PreparedCurrentAccumulationFinalization): CurrentAccumulationFinalizationResult[
    PreparedCurrentAccumulationOutputs] =
  ## Retain the exact immutable outputs projection; default finalization grants no initialized successor.
  let data = finalized.data
  if data == nil: return CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationOutputs](
      status: CurrentAccumulationFinalizationError.Uninitialized) # No synthetic completion.
  CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationOutputs](
      status: CurrentAccumulationFinalizationError.None, completed: data.outputs)

proc currentFinalizationHistory*(finalized: PreparedCurrentAccumulationFinalization): CurrentAccumulationFinalizationResult[
    AccumulatedSnapshot] =
  ## Retain the exact immutable ring projection; default finalization grants no initialized successor.
  let data = finalized.data
  if data == nil: return CurrentAccumulationFinalizationResult[AccumulatedSnapshot](
      status: CurrentAccumulationFinalizationError.Uninitialized) # No synthetic completion.
  CurrentAccumulationFinalizationResult[AccumulatedSnapshot](
      status: CurrentAccumulationFinalizationError.None, completed: data.ring)

proc currentFinalizationState*(finalized: PreparedCurrentAccumulationFinalization): CurrentAccumulationFinalizationResult[
    StateStoreSnapshot] =
  ## Retain the exact immutable state projection; default finalization grants no initialized successor.
  let data = finalized.data
  if data == nil: return CurrentAccumulationFinalizationResult[StateStoreSnapshot](
      status: CurrentAccumulationFinalizationError.Uninitialized) # No synthetic completion.
  CurrentAccumulationFinalizationResult[StateStoreSnapshot](
      status: CurrentAccumulationFinalizationError.None, completed: data.state)
