# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose the exact authenticated consensus/report chapters with one retained private accumulation candidate.
## The fixed seven-key overlay preserves every accumulation-owned chapter and service record without replay.

import ../../../codec/[bounded, header]
import ../../../codec/state/[layout as state_layout, trie as state_trie]
import ../consensus as accumulation_consensus
import ./[authorization as accumulation_current_authorization,
    preimages as accumulation_current_preimages, activity as accumulation_current_activity,
    validators as accumulation_current_validators, recent as accumulation_current_recent,
    ready as accumulation_current_ready, finalization as accumulation_current_finalization,
    accounts as accumulation_current_accounts, statistics as accumulation_current_statistics,
    driver as accumulation_current_driver, sequence as accumulation_current_sequence,
    round as accumulation_current_round]
import "../block/guests" as accumulation_block_guests
import ../[round as accumulation_round, queue as accumulation_queue]
import ../../report/[admission as report_admission, assignments as report_assignments]
import "../../block/transition" as block_transition
import "../../block/admission" as block_admission
import ../../store

type
  CurrentAccumulationConsensusError* {.pure.} = enum ## Defaults and refusals expose no earlier success or partially composed map.
    Uninitialized, None, InvalidSource, LimitExceeded, StateFailure
  # Acyclic immutable retention binds the new complete candidate to all original stage and accumulation authority.
  CurrentConsensusData = ref object
    source: PreparedCurrentAccumulationAuthorization
    info: AccumulationConsensusInfo
    state: StateStoreSnapshot
  PreparedCurrentAccumulationConsensus* = object ## Only exact-source composition creates this private complete-map owner.
    data: nil CurrentConsensusData
  CurrentAccumulationConsensusResult*[T] = object ## Selected success alone carries values; selected store failure alone carries its child cause.
    case status: CurrentAccumulationConsensusError
    of None:
      completed: T
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Defaults, invalid sources and policy refusals carry reasons alone.

func error*[T](outcome: CurrentAccumulationConsensusResult[T]): CurrentAccumulationConsensusError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: CurrentAccumulationConsensusResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationConsensusError.None.} =
  ## Extract only complete success in checked optimized builds.
  outcome.completed
func stateError*[T](outcome: CurrentAccumulationConsensusResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationConsensusError.StateFailure.} =
  ## Inspect only a genuine selected complete-map lookup or publication refusal.
  outcome.stateReason

proc currentConsensusSource*(plan: PreparedCurrentAccumulationConsensus):
    CurrentAccumulationConsensusResult[PreparedCurrentAccumulationAuthorization] =
  ## Retain the exact authorization/accumulation certificate graph and authenticated block authority.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationConsensusResult[PreparedCurrentAccumulationAuthorization](
      status: CurrentAccumulationConsensusError.Uninitialized) # Defaults grant no source authority.
  CurrentAccumulationConsensusResult[PreparedCurrentAccumulationAuthorization](
    status: CurrentAccumulationConsensusError.None, completed: data.source)

proc currentConsensusInfo*(plan: PreparedCurrentAccumulationConsensus):
    CurrentAccumulationConsensusResult[AccumulationConsensusInfo] =
  ## Copy slot and exact batch extent without exposing mutable retained values.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationConsensusResult[AccumulationConsensusInfo](
      status: CurrentAccumulationConsensusError.Uninitialized) # No fabricated empty completed batch.
  CurrentAccumulationConsensusResult[AccumulationConsensusInfo](
    status: CurrentAccumulationConsensusError.None, completed: data.info)

proc currentConsensusState*(plan: PreparedCurrentAccumulationConsensus):
    CurrentAccumulationConsensusResult[StateStoreSnapshot] =
  ## Retain the complete private composed successor; every predecessor stays immutable.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationConsensusResult[StateStoreSnapshot](
      status: CurrentAccumulationConsensusError.Uninitialized) # No default root or partial map escapes.
  CurrentAccumulationConsensusResult[StateStoreSnapshot](
    status: CurrentAccumulationConsensusError.None, completed: data.state)

proc prepareCurrentAccumulationConsensus*(source: PreparedCurrentAccumulationAuthorization,
    limits: AccumulationConsensusLimits):
    CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus] =
  ## Bound exact authenticated chapter payloads, then atomically overlay only the fixed consensus/report keys.
  template fail(reason: CurrentAccumulationConsensusError) =
    return CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus](status: reason)
  let retained = source.currentAuthorizationSource
  if retained.error != CurrentAccumulationAuthorizationError.None:
    fail(CurrentAccumulationConsensusError.InvalidSource) # Defaults cannot supply an authenticated empty source.
  let finalized = retained.value.currentPreimagesSource.value.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value
  let completed = finalized.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let admission = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  let stage = admission.reportBlockStage.value.value
  let assignments = admission.reportAssignments.value
  let assignedBytes = assignments.reportAssignmentByteLength.value
  # These six stage keys plus the completed assignment key are fixed, unique and disjoint from accumulation-owned state.
  let chapters = [4'u8, 5, 6, 8, 9, 11]
  var views = default(array[6, StateValue])
  var sizes = default(array[7, int])
  for index, number in chapters:
    let found = stage.snapshot.lookup(chapterKey(StateChapter(number)))
    if found.error != StateStoreError.None:
      return CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus](
        status: CurrentAccumulationConsensusError.StateFailure,
        stateReason: found.error) # Missing authenticated chapters cannot be substituted from the parent or accumulator.
    views[index] = found.value
    sizes[index] = found.value.byteLength # Retained views bind extents to their original immutable owner.
  sizes[6] = assignedBytes
  var total = 0'u64
  for size in sizes:
    let amount = uint64(size)
    if amount > uint64(limits.chapterBytes): fail(CurrentAccumulationConsensusError.LimitExceeded)
    if amount > uint64(limits.totalBytes)-total: fail(
        CurrentAccumulationConsensusError.LimitExceeded)
    if amount > uint64(high(int))-total: fail(CurrentAccumulationConsensusError.LimitExceeded)
    total += amount # Subtraction proves policy/native summation before any payload materialization.
  var writes = default(array[7, StateWrite])
  for index, number in chapters:
    writes[index] = StateWrite(key: chapterKey(StateChapter(number)), kind: StateWriteKind.Put,
      value: views[index].bytes) # Exact stage bytes require no re-encoding, signature verification or replay.
  let entry = assignments.reportAssignmentEntry.value
  writes[6] = StateWrite(key: entry.key, kind: StateWriteKind.Put,
    value: entry.value) # New guarantees must replace the earlier post-assurance C(10).
  var working = forkStateStore(source.currentAuthorizationState.value).value
  let applied = working.apply(writes)
  if applied.error != StateStoreError.None:
    return CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus](
      status: CurrentAccumulationConsensusError.StateFailure,
      stateReason: applied.error) # Atomic failure releases every scratch entry without exposing a usable successor.
  CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus](
    status: CurrentAccumulationConsensusError.None,
    completed: PreparedCurrentAccumulationConsensus(data: CurrentConsensusData(source: source,
      info: AccumulationConsensusInfo(slot: stage.admitted.admittedHeader.headerInfo.value.unsigned.slot,
        chapters: writes.len, bytes: int(total)), state: applied.value)))
