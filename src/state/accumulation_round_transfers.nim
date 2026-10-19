# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind canonical outgoing transfer collection and paid gas to an actual completed admitted initial round.
## No replacement outcome array, source state or caller-authored gas observation is accepted.

import std/algorithm
import ../codec/[composite, work_digest]
import ./[accumulation_execution, accumulation_batch, accumulation_outcome,
  accumulation_provisions, accumulation_transfers]

type
  AccumulationRoundTransferError* {.pure.} = enum ## Default/refused results retain no earlier collection, source or gas progress.
    Uninitialized, None, InvalidSource, LimitExceeded
  AccumulationRoundTransferInfo* = object ## Copied observations keep exact collected cardinalities separate from paid outgoing gas.
    collection*: AccumulationTransferCollectionInfo
    gas*: Gas
  # Fixed sort rows retain immutable outcomes; numeric identity alone determines cross-service order.
  RoundTransferRow = object
    service: ServiceIndex
    outcome: AccumulationOutcome
  # Acyclic owner binds exact completed provenance and its canonical collection without mutable replacement fields.
  RoundTransferData = ref object
    source: CompletedBlockAccumulation
    collection: PreparedAccumulationTransfers
    gas: Gas
  PreparedRoundAccumulationTransfers* = object ## Only a completed admitted round can authorize this stronger collection owner.
    data: nil RoundTransferData
  AccumulationRoundTransferResult*[T] = object ## Guarded success extraction preserves the reason-only refusal contract.
    case status: AccumulationRoundTransferError
    of None:
      completed: T # No public discriminator or successful payload permits retagging.
    else:
      discard      # Defaults and failures own no source, partial collection or gas observation.

func error*[T](outcome: AccumulationRoundTransferResult[T]): AccumulationRoundTransferError =
  ## Inspect the selected reason without exposing mutable result storage.
  outcome.status
func value*[T](outcome: AccumulationRoundTransferResult[T]): T {.inline,
    requires: outcome.status == AccumulationRoundTransferError.None.} =
  ## Extract complete selected success under optimized native contracts.
  outcome.completed

# Numeric service order is independent of caller execution order and serialized key bytes.
func compareRow(left, right: RoundTransferRow): int =
  if uint32(left.service) < uint32(right.service): return -1 # Smaller service emits its entire selected sequence first.
  if uint32(left.service) > uint32(right.service): return 1
  0

proc roundTransferInfo*(plan: PreparedRoundAccumulationTransfers):
    AccumulationRoundTransferResult[AccumulationRoundTransferInfo] =
  ## Copy collected cardinalities and paid outgoing gas, never backing arrays.
  let data = plan.data
  if data == nil:
    return AccumulationRoundTransferResult[AccumulationRoundTransferInfo](status:
      AccumulationRoundTransferError.Uninitialized) # A default is not a valid empty completed round.
  AccumulationRoundTransferResult[AccumulationRoundTransferInfo](status:
    AccumulationRoundTransferError.None, completed: AccumulationRoundTransferInfo(
      collection: data.collection.transferCollectionInfo.value, gas: data.gas))

proc roundTransferSource*(plan: PreparedRoundAccumulationTransfers):
    AccumulationRoundTransferResult[CompletedBlockAccumulation] =
  ## Retain the exact admitted completion independently of this collection's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationRoundTransferResult[CompletedBlockAccumulation](status:
      AccumulationRoundTransferError.Uninitialized) # No synthesized round provenance.
  AccumulationRoundTransferResult[CompletedBlockAccumulation](status:
    AccumulationRoundTransferError.None, completed: data.source)

proc roundTransferCollection*(plan: PreparedRoundAccumulationTransfers):
    AccumulationRoundTransferResult[PreparedAccumulationTransfers] =
  ## Retain canonical fixed transfer values and terminal-selected source owners without exposing mutable storage.
  let data = plan.data
  if data == nil:
    return AccumulationRoundTransferResult[PreparedAccumulationTransfers](status:
      AccumulationRoundTransferError.Uninitialized) # Defaults own no canonical sequence.
  AccumulationRoundTransferResult[PreparedAccumulationTransfers](status:
    AccumulationRoundTransferError.None, completed: data.collection)

proc prepareRoundAccumulationTransfers*(source: CompletedBlockAccumulation,
    limits: AccumulationTransferCollectionLimits):
    AccumulationRoundTransferResult[PreparedRoundAccumulationTransfers] =
  ## Capture only the completed batch's selected outcomes in numeric service order, charging all copied memo bytes.
  # Refuse atomically without exposing any earlier retained outcome or partial gas sum.
  template fail(reason: AccumulationRoundTransferError) =
    return AccumulationRoundTransferResult[PreparedRoundAccumulationTransfers](status: reason)
  let completed = source.executionInfo
  if completed.error != AccumulationExecutionError.None:
    fail(AccumulationRoundTransferError.InvalidSource) # No caller-authored replacement certificate or budget is accepted.
  let info = completed.value
  let count = info.batch.executions
  if uint64(count) > uint64(limits.sources) or
      count > high(int) div (sizeof(RoundTransferRow)+sizeof(AccumulationOutcome)):
    fail(AccumulationRoundTransferError.LimitExceeded) # Bound canonical sort descriptors and captured handles before allocation.
  let batch = source.executionBatch.value
  var rows = newSeq[RoundTransferRow](count)
  for index in 0..<count:
    let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    rows[index] = RoundTransferRow(service: outcome.outcomeInfo.value.service,
        outcome: outcome) # Complete coverage already proves unique service identity.
  rows.sort(compareRow)
  var outcomes = newSeq[AccumulationOutcome](count)
  for index, row in rows:
    outcomes[index] = row.outcome # Canonical collection keeps each service's own append order unchanged.
  let collected = prepareAccumulationTransfers(outcomes, limits)
  if collected.error == AccumulationTransferCollectionError.LimitExceeded:
    fail(AccumulationRoundTransferError.LimitExceeded) # Preserve the existing item/memo/native storage policy refusal.
  if collected.error != AccumulationTransferCollectionError.None:
    fail(AccumulationRoundTransferError.InvalidSource) # Private completed owners cannot legitimately supply invalid selected outcomes.
  let collection = collected.value
  var available = uint64(info.gasUsed)
  for index in 0..<collection.transferCollectionInfo.value.transfers:
    let transfer = collection.collectedTransferAt(CollectedTransferIndex(uint64(index))).value
    if uint64(transfer.gas) > available:
      fail(AccumulationRoundTransferError.InvalidSource) # Every selected transfer paid offered gas before commit; never wrap or fabricate a larger refund.
    available -= uint64(transfer.gas)
  AccumulationRoundTransferResult[PreparedRoundAccumulationTransfers](status:
    AccumulationRoundTransferError.None, completed: PreparedRoundAccumulationTransfers(
      data: RoundTransferData(source: source, collection: collection,
        gas: Gas(uint64(info.gasUsed)-available))))
