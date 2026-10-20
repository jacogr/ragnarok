# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind canonical outgoing transfer collection and paid gas to an actual completed admitted initial round.
## No replacement outcome array, source state or caller-authored gas observation is accepted.

import ../codec/work_digest
import ./[accumulation_execution, accumulation_batch, accumulation_transfers]

type
  AccumulationRoundTransferError* {.pure.} = enum ## Default/refused results retain no earlier collection, source or gas progress.
    Uninitialized, None, InvalidSource, LimitExceeded
  AccumulationRoundTransferInfo* = object ## Copied observations keep exact collected cardinalities separate from paid outgoing gas.
    collection*: AccumulationTransferCollectionInfo
    gas*: Gas
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
  let collected = prepareBatchAccumulationTransfers(source.executionBatch.value, limits)
  if collected.error == AccumulationBatchError.LimitExceeded:
    fail(AccumulationRoundTransferError.LimitExceeded) # Shared canonical collection owns source/item/memo/native extent checks.
  if collected.error != AccumulationBatchError.None:
    fail(AccumulationRoundTransferError.InvalidSource) # Only this completion's actual initialized batch is accepted.
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
