# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fulfill the exact admitted lookup extrinsic on its authenticated accumulation activity successor.
## Source-derived slot and cached original-parent admission authorize only a private complete-map candidate.

import ../../codec/[bounded, header]
import ./[activity as accumulation_activity, validators as accumulation_validators,
    times as accumulation_times, statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../[preimages, store]

type
  AccumulationPreimageLimits* = object ## Independent fulfillment work limits supplement retained admission and store policies.
    items*: ElementLimit ## Maximum admitted pairs traversed, including those no longer outstanding.
    bytes*: ByteLimit    ## Maximum admitted raw payload budget, including pairs later skipped.
  AccumulationPreimageInfo* = object ## Copied original-extrinsic observations do not claim every pair was still needed.
    slot*: HeaderSlot                ## Authenticated block slot used by every newly fulfilled request.
    admitted*: PreimageAdmissionInfo ## Actual admitted items, service groups and payload bytes.
  AccumulationPreimageError* {.pure.} = enum ## Refusals retain neither a source nor any partially fulfilled candidate.
    Uninitialized, None, InvalidSource, LimitExceeded, PreimageFailure
  # Acyclic retention keeps the exact source certificate graph and immutable complete successor alive.
  AccumulationPreimageData = ref object
    source: PreparedAccumulationActivity
    info: AccumulationPreimageInfo
    state: StateStoreSnapshot
  PreparedAccumulationPreimages* = object ## Only source-bound fulfillment can create this private successor owner.
    data: nil AccumulationPreimageData
  AccumulationPreimageResult*[T] = object ## Only selected complete success carries an owner or observations.
    case status: AccumulationPreimageError
    of None:
      completed: T
    of PreimageFailure:
      preimageReason: PreimageTransitionError
    else:
      discard # Default, invalid-source and policy alternatives carry reasons alone.

func error*[T](outcome: AccumulationPreimageResult[T]): AccumulationPreimageError =
  ## Inspect the selected reason without exposing writable tags.
  outcome.status
func value*[T](outcome: AccumulationPreimageResult[T]): T {.inline,
    requires: outcome.status == AccumulationPreimageError.None.} =
  ## Extract only a selected complete success under checked optimized builds.
  outcome.completed
func preimageError*[T](outcome: AccumulationPreimageResult[T]): PreimageTransitionError {.inline,
    requires: outcome.status == AccumulationPreimageError.PreimageFailure.} =
  ## Inspect only a genuine atomic fulfillment refusal.
  outcome.preimageReason

proc accumulationPreimagesSource*(plan: PreparedAccumulationPreimages):
    AccumulationPreimageResult[PreparedAccumulationActivity] =
  ## Retain the exact activity candidate, including its original-parent admission owner.
  let data = plan.data
  if data == nil:
    return AccumulationPreimageResult[PreparedAccumulationActivity](
      status: AccumulationPreimageError.Uninitialized) # Defaults grant no source authority.
  AccumulationPreimageResult[PreparedAccumulationActivity](status: AccumulationPreimageError.None,
    completed: data.source)

proc accumulationPreimagesInfo*(plan: PreparedAccumulationPreimages):
    AccumulationPreimageResult[AccumulationPreimageInfo] =
  ## Copy the authenticated slot and original admitted populations without mutable storage access.
  let data = plan.data
  if data == nil:
    return AccumulationPreimageResult[AccumulationPreimageInfo](
      status: AccumulationPreimageError.Uninitialized) # No fabricated zero-slot empty success.
  AccumulationPreimageResult[AccumulationPreimageInfo](status: AccumulationPreimageError.None,
    completed: data.info)

proc accumulationPreimagesState*(plan: PreparedAccumulationPreimages):
    AccumulationPreimageResult[StateStoreSnapshot] =
  ## Retain the complete private successor; source snapshots remain immutable.
  let data = plan.data
  if data == nil:
    return AccumulationPreimageResult[StateStoreSnapshot](
      status: AccumulationPreimageError.Uninitialized) # No partial map or default root escapes.
  AccumulationPreimageResult[StateStoreSnapshot](status: AccumulationPreimageError.None,
    completed: data.state)

proc prepareAccumulationPreimages*(source: PreparedAccumulationActivity,
    limits: AccumulationPreimageLimits):
    AccumulationPreimageResult[PreparedAccumulationPreimages] =
  ## Recheck posterior solicitation and atomically fulfill the exact original-parent admitted body at its authenticated slot.
  let retained = source.accumulationActivitySource
  if retained.error != AccumulationActivityError.None:
    return AccumulationPreimageResult[PreparedAccumulationPreimages](
      status: AccumulationPreimageError.InvalidSource) # Defaults cannot stand for authenticated empty input.
  let admitted = source.accumulationActivityPreimages.value
  let counts = admitted.preimageInfo.value
  if uint64(counts.items) > uint64(limits.items):
    return AccumulationPreimageResult[PreparedAccumulationPreimages](
      status: AccumulationPreimageError.LimitExceeded) # Bound all admitted rows before filtering or hashing.
  if uint64(counts.bytes) > uint64(limits.bytes):
    return AccumulationPreimageResult[PreparedAccumulationPreimages](
      status: AccumulationPreimageError.LimitExceeded) # Compare actual full-width payload work without narrowing ceilings.
  let finalized = retained.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let admission = finalized.finalAccumulationAdmission.value
  let binding = admission.reportBlockStage.value.value.admitted
  let slot = binding.admittedHeader.headerInfo.value.unsigned.slot
  var working = forkStateStore(source.accumulationActivityState.value).value
  let applied = integratePreimages(working, admitted, slot)
  if applied.error != PreimageTransitionError.None:
    return AccumulationPreimageResult[PreparedAccumulationPreimages](
      status: AccumulationPreimageError.PreimageFailure,
      preimageReason: applied.error) # Key, state or Merkle refusal publishes no partial successor.
  AccumulationPreimageResult[PreparedAccumulationPreimages](status: AccumulationPreimageError.None,
    completed: PreparedAccumulationPreimages(data: AccumulationPreimageData(source: source,
      info: AccumulationPreimageInfo(slot: slot, admitted: counts), state: applied.value)))
