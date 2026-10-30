# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fulfill the exact original-parent admitted lookup extrinsic on its genuine current activity successor.
## Source-derived slot and cached original-parent admission authorize only a private complete-map candidate.

import ../../../codec/[bounded, header]
import ../preimages as accumulation_preimages
import ./[activity as accumulation_current_activity, validators as accumulation_current_validators,
    recent as accumulation_current_recent, ready as accumulation_current_ready,
    finalization as accumulation_current_finalization, accounts as accumulation_current_accounts,
    statistics as accumulation_current_statistics, driver as accumulation_current_driver,
    sequence as accumulation_current_sequence, round as accumulation_current_round]
import "../block/guests" as accumulation_block_guests
import ../[round as accumulation_round, queue as accumulation_queue]
import ../../report/admission as report_admission
import "../../block/transition" as block_transition
import "../../block/admission" as block_admission
import ../../[preimages, store]

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
