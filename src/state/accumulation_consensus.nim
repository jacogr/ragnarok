# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose the exact authenticated consensus/report chapters with one retained private accumulation candidate.
## The fixed seven-key overlay preserves every accumulation-owned chapter and service record without replay.

import ../codec/[bounded, header, state_layout, state_trie]
import ./[accumulation_authorization, accumulation_preimages, accumulation_activity,
  accumulation_validators, accumulation_times, accumulation_statistics, accumulation_finalization,
  accumulation_outputs, accumulation_execution, accumulation_round, accumulation_queue,
  report_admission, report_assignments, block_transition, block_admission, store]

type
  AccumulationConsensusLimits* = object ## Only payload-copy policies are caller-selected; the source and chapter set are fixed.
    chapterBytes*: ByteLimit ## Maximum exact value extent for each of the seven chapters.
    totalBytes*: ByteLimit   ## Aggregate selected payload copied before one atomic composition batch.
  AccumulationConsensusInfo* = object ## Copied authenticated slot and fixed batch observations contain no writable entry storage.
    slot*: HeaderSlot ## Exact candidate slot from the retained block, never a replacement caller time.
    chapters*: int ## Exactly seven selected Puts, including chapters whose bytes did not change.
    bytes*: int    ## Actual aggregate selected payload; native extent is proved before copies.
  AccumulationConsensusError* {.pure.} = enum ## Defaults and refusals expose no earlier success or partially composed map.
    Uninitialized, None, InvalidSource, LimitExceeded, StateFailure
  # Acyclic immutable retention binds the new complete candidate to all original stage and accumulation authority.
  AccumulationConsensusData = ref object
    source: PreparedAccumulationAuthorization
    info: AccumulationConsensusInfo
    state: StateStoreSnapshot
  PreparedAccumulationConsensus* = object ## Only exact-source composition creates this private complete-map owner.
    data: nil AccumulationConsensusData
  AccumulationConsensusResult*[T] = object ## Selected success alone carries values; selected store failure alone carries its child cause.
    case status: AccumulationConsensusError
    of None:
      completed: T
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Defaults, invalid sources and policy refusals carry reasons alone.

func error*[T](outcome: AccumulationConsensusResult[T]): AccumulationConsensusError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: AccumulationConsensusResult[T]): T {.inline,
    requires: outcome.status == AccumulationConsensusError.None.} =
  ## Extract only complete success in checked optimized builds.
  outcome.completed
func stateError*[T](outcome: AccumulationConsensusResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationConsensusError.StateFailure.} =
  ## Inspect only a genuine selected complete-map lookup or publication refusal.
  outcome.stateReason

proc accumulationConsensusSource*(plan: PreparedAccumulationConsensus):
    AccumulationConsensusResult[PreparedAccumulationAuthorization] =
  ## Retain the exact authorization/accumulation certificate graph and authenticated block authority.
  let data = plan.data
  if data == nil:
    return AccumulationConsensusResult[PreparedAccumulationAuthorization](
      status: AccumulationConsensusError.Uninitialized) # Defaults grant no source authority.
  AccumulationConsensusResult[PreparedAccumulationAuthorization](
    status: AccumulationConsensusError.None, completed: data.source)

proc accumulationConsensusInfo*(plan: PreparedAccumulationConsensus):
    AccumulationConsensusResult[AccumulationConsensusInfo] =
  ## Copy slot and exact batch extent without exposing mutable retained values.
  let data = plan.data
  if data == nil:
    return AccumulationConsensusResult[AccumulationConsensusInfo](
      status: AccumulationConsensusError.Uninitialized) # No fabricated empty completed batch.
  AccumulationConsensusResult[AccumulationConsensusInfo](
    status: AccumulationConsensusError.None, completed: data.info)

proc accumulationConsensusState*(plan: PreparedAccumulationConsensus):
    AccumulationConsensusResult[StateStoreSnapshot] =
  ## Retain the complete private composed successor; every predecessor stays immutable.
  let data = plan.data
  if data == nil:
    return AccumulationConsensusResult[StateStoreSnapshot](
      status: AccumulationConsensusError.Uninitialized) # No default root or partial map escapes.
  AccumulationConsensusResult[StateStoreSnapshot](
    status: AccumulationConsensusError.None, completed: data.state)

proc prepareAccumulationConsensus*(source: PreparedAccumulationAuthorization,
    limits: AccumulationConsensusLimits):
    AccumulationConsensusResult[PreparedAccumulationConsensus] =
  ## Bound exact authenticated chapter payloads, then atomically overlay only the fixed consensus/report keys.
  template fail(reason: AccumulationConsensusError) =
    return AccumulationConsensusResult[PreparedAccumulationConsensus](status: reason)
  let retained = source.accumulationAuthorizationSource
  if retained.error != AccumulationAuthorizationError.None:
    fail(AccumulationConsensusError.InvalidSource) # Defaults cannot supply an authenticated empty source.
  let finalized = retained.value.accumulationPreimagesSource.value.accumulationActivitySource.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let admission = finalized.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
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
      return AccumulationConsensusResult[PreparedAccumulationConsensus](
        status: AccumulationConsensusError.StateFailure,
        stateReason: found.error) # Missing authenticated chapters cannot be substituted from the parent or accumulator.
    views[index] = found.value
    sizes[index] = found.value.byteLength # Retained views bind extents to their original immutable owner.
  sizes[6] = assignedBytes
  var total = 0'u64
  for size in sizes:
    let amount = uint64(size)
    if amount > uint64(limits.chapterBytes): fail(AccumulationConsensusError.LimitExceeded)
    if amount > uint64(limits.totalBytes)-total: fail(AccumulationConsensusError.LimitExceeded)
    if amount > uint64(high(int))-total: fail(AccumulationConsensusError.LimitExceeded)
    total += amount # Subtraction proves policy/native summation before any payload materialization.
  var writes = default(array[7, StateWrite])
  for index, number in chapters:
    writes[index] = StateWrite(key: chapterKey(StateChapter(number)), kind: StateWriteKind.Put,
      value: views[index].bytes) # Exact stage bytes require no re-encoding, signature verification or replay.
  let entry = assignments.reportAssignmentEntry.value
  writes[6] = StateWrite(key: entry.key, kind: StateWriteKind.Put,
    value: entry.value) # New guarantees must replace the earlier post-assurance C(10).
  var working = forkStateStore(source.accumulationAuthorizationState.value).value
  let applied = working.apply(writes)
  if applied.error != StateStoreError.None:
    return AccumulationConsensusResult[PreparedAccumulationConsensus](
      status: AccumulationConsensusError.StateFailure,
      stateReason: applied.error) # Atomic failure releases every scratch entry without exposing a usable successor.
  AccumulationConsensusResult[PreparedAccumulationConsensus](
    status: AccumulationConsensusError.None,
    completed: PreparedAccumulationConsensus(data: AccumulationConsensusData(source: source,
      info: AccumulationConsensusInfo(slot: stage.admitted.admittedHeader.headerInfo.value.unsigned.slot,
        chapters: writes.len, bytes: int(total)), state: applied.value)))
