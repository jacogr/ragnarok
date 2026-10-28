# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fulfill the exact original-parent admitted lookup extrinsic on its genuine current activity successor.
## Source-derived slot and cached original-parent admission authorize only a private complete-map candidate.

import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ./accumulation_preimages as state_accumulation_preimages
import ./accumulation_current_activity as state_accumulation_current_activity
import ./accumulation_current_validators as state_accumulation_current_validators
import ./accumulation_current_recent as state_accumulation_current_recent
import ./accumulation_current_ready as state_accumulation_current_ready
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
import ./preimages as state_preimages
import ./store as state_store

type
  CurrentAccumulationPreimageError* {.pure.} = enum ## Refusals retain neither a source nor any partially fulfilled candidate.
    Uninitialized, None, InvalidSource, LimitExceeded, PreimageFailure
  # Acyclic retention keeps the exact source certificate graph and immutable complete successor alive.
  CurrentPreimageData = ref object
    source: PreparedCurrentAccumulationActivity
    info: AccumulationPreimageInfo
    state: StateStoreSnapshot
  PreparedCurrentAccumulationPreimages* = object ## Only source-bound fulfillment can create this private successor owner.
    data: nil CurrentPreimageData
  CurrentAccumulationPreimageResult*[T] = object ## Only selected complete success carries an owner or observations.
    case status: CurrentAccumulationPreimageError
    of None:
      completed: T
    of PreimageFailure:
      preimageReason: PreimageTransitionError
    else:
      discard # Default, invalid-source and policy alternatives carry reasons alone.

func error*[T](outcome: CurrentAccumulationPreimageResult[T]): CurrentAccumulationPreimageError =
  ## Inspect the selected reason without exposing writable tags.
  outcome.status
func value*[T](outcome: CurrentAccumulationPreimageResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationPreimageError.None.} =
  ## Extract only a selected complete success under checked optimized builds.
  outcome.completed
func preimageError*[T](outcome: CurrentAccumulationPreimageResult[
    T]): PreimageTransitionError {.inline,

requires: outcome.status == CurrentAccumulationPreimageError.PreimageFailure.} =
  ## Inspect only a genuine atomic fulfillment refusal.
  outcome.preimageReason

proc currentPreimagesSource*(plan: PreparedCurrentAccumulationPreimages):
    CurrentAccumulationPreimageResult[PreparedCurrentAccumulationActivity] =
  ## Retain the exact activity candidate, including its original-parent admission owner.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationPreimageResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationPreimageError.Uninitialized) # Defaults grant no source authority.
  CurrentAccumulationPreimageResult[PreparedCurrentAccumulationActivity](
    status: CurrentAccumulationPreimageError.None,
    completed: data.source)

proc currentPreimagesInfo*(plan: PreparedCurrentAccumulationPreimages):
    CurrentAccumulationPreimageResult[AccumulationPreimageInfo] =
  ## Copy the authenticated slot and original admitted populations without mutable storage access.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationPreimageResult[AccumulationPreimageInfo](
      status: CurrentAccumulationPreimageError.Uninitialized) # No fabricated zero-slot empty success.
  CurrentAccumulationPreimageResult[AccumulationPreimageInfo](
    status: CurrentAccumulationPreimageError.None,
    completed: data.info)

proc currentPreimagesState*(plan: PreparedCurrentAccumulationPreimages):
    CurrentAccumulationPreimageResult[StateStoreSnapshot] =
  ## Retain the complete private successor; source snapshots remain immutable.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationPreimageResult[StateStoreSnapshot](
      status: CurrentAccumulationPreimageError.Uninitialized) # No partial map or default root escapes.
  CurrentAccumulationPreimageResult[StateStoreSnapshot](
    status: CurrentAccumulationPreimageError.None,
    completed: data.state)

proc prepareCurrentAccumulationPreimages*(source: PreparedCurrentAccumulationActivity,
    limits: AccumulationPreimageLimits):
    CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages] =
  ## Recheck posterior solicitation and atomically fulfill the exact original-parent admitted body at its authenticated slot.
  let retained = source.currentActivitySource
  if retained.error != CurrentAccumulationActivityError.None:
    return CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages](
      status: CurrentAccumulationPreimageError.InvalidSource) # Defaults cannot stand for authenticated empty input.
  let admitted = source.currentActivityPreimages.value
  let counts = admitted.preimageInfo.value
  if uint64(counts.items) > uint64(limits.items):
    return CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages](
      status: CurrentAccumulationPreimageError.LimitExceeded) # Bound all admitted rows before filtering or hashing.
  if uint64(counts.bytes) > uint64(limits.bytes):
    return CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages](
      status: CurrentAccumulationPreimageError.LimitExceeded) # Compare actual full-width payload work without narrowing ceilings.
  let finalized = retained.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value
  let completed = finalized.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let admission = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  let binding = admission.reportBlockStage.value.value.admitted
  let slot = binding.admittedHeader.headerInfo.value.unsigned.slot
  var working = forkStateStore(source.currentActivityState.value).value
  let applied = integratePreimages(working, admitted, slot)
  if applied.error != PreimageTransitionError.None:
    return CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages](
      status: CurrentAccumulationPreimageError.PreimageFailure,
      preimageReason: applied.error) # Key, state or Merkle refusal publishes no partial successor.
  CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages](
    status: CurrentAccumulationPreimageError.None,
    completed: PreparedCurrentAccumulationPreimages(data: CurrentPreimageData(source: source,
      info: AccumulationPreimageInfo(slot: slot, admitted: counts), state: applied.value)))
