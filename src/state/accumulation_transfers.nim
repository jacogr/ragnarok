# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect ordered outgoing transfers from immutable terminal-selected outcomes with explicit work limits.
## This captures provenance and values, without certifying round membership or applying deferred credits.

import ../codec/[bounded, c2_records]
import ./[accumulation_outcome, accumulation_effects]

type
  AccumulationTransferSourceIndex* = distinct uint64 ## Source ordinal is distinct from a transfer's ordinal inside a selected context.
  CollectedTransferIndex* = distinct uint64 ## Ordinal in this collection, never an account or per-context index.
  AccumulationMemoBytes* = distinct uint64 ## Observed memo storage is separate from caller byte ceilings.
  AccumulationTransferCollectionLimits* = object ## Repeated outcomes and duplicate records consume all applicable ceilings.
    sources*, transfers*: ElementLimit
    memoBytes*: ByteLimit
  AccumulationTransferCollectionInfo* = object ## Copied observations cannot replace source provenance or collection storage.
    sources*, transfers*: int
    memoBytes*: AccumulationMemoBytes
  AccumulationTransferCollectionError* {.pure.} = enum ## Defaults and failures never retain partial transfers or successful source handles.
    Uninitialized, None, InvalidOutcome, InvalidIndex, LimitExceeded
  # Private acyclic owner retains the exact normalized sources and complete fixed-value transfer copies.
  TransferCollectionData = ref object
    sources: seq[AccumulationOutcome]
    transfers: seq[DeferredTransfer]
    info: AccumulationTransferCollectionInfo
  PreparedAccumulationTransfers* = object ## Only successful bounded collection can initialize this immutable owner.
    data: nil TransferCollectionData
  AccumulationTransferCollectionResult*[T] = object ## Guarded success extraction prevents default or refused collection from fabricating values.
    case status: AccumulationTransferCollectionError
    of None:
      completed: T # No mutable discriminator or success storage is public.
    else:
      discard      # Failed/default alternatives contain the reason alone.

func error*[T](outcome: AccumulationTransferCollectionResult[
    T]): AccumulationTransferCollectionError =
  ## Inspect the selected reason without permitting result retagging.
  outcome.status
func value*[T](outcome: AccumulationTransferCollectionResult[T]): T {.inline,
    requires: outcome.status == AccumulationTransferCollectionError.None.} =
  ## Extract only complete selected success under optimized native contracts.
  outcome.completed

proc transferCollectionInfo*(plan: PreparedAccumulationTransfers):
    AccumulationTransferCollectionResult[AccumulationTransferCollectionInfo] =
  ## Copy cardinalities and memo accounting without exposing retained arrays.
  let data = plan.data
  if data == nil:
    return AccumulationTransferCollectionResult[AccumulationTransferCollectionInfo](status:
      AccumulationTransferCollectionError.Uninitialized) # A default plan is not an initialized empty collection.
  AccumulationTransferCollectionResult[AccumulationTransferCollectionInfo](status:
    AccumulationTransferCollectionError.None, completed: data.info)

proc transferCollectionSourceAt*(plan: PreparedAccumulationTransfers,
    index: AccumulationTransferSourceIndex): AccumulationTransferCollectionResult[
        AccumulationOutcome] =
  ## Retain one exact terminal-selected source independently of this collection's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationTransferCollectionResult[AccumulationOutcome](status:
      AccumulationTransferCollectionError.Uninitialized) # No default source provenance is fabricated.
  if uint64(index) >= uint64(data.sources.len):
    return AccumulationTransferCollectionResult[AccumulationOutcome](status:
      AccumulationTransferCollectionError.InvalidIndex) # Prove the full ordinal before native narrowing.
  AccumulationTransferCollectionResult[AccumulationOutcome](status:
    AccumulationTransferCollectionError.None, completed: data.sources[int(uint64(index))])

proc collectedTransferAt*(plan: PreparedAccumulationTransfers,
    index: CollectedTransferIndex): AccumulationTransferCollectionResult[DeferredTransfer] =
  ## Copy every fixed field and memo byte; no mutable reference into collection storage escapes.
  let data = plan.data
  if data == nil:
    return AccumulationTransferCollectionResult[DeferredTransfer](status:
      AccumulationTransferCollectionError.Uninitialized) # Default plans own no transfer values.
  if uint64(index) >= uint64(data.transfers.len):
    return AccumulationTransferCollectionResult[DeferredTransfer](status:
      AccumulationTransferCollectionError.InvalidIndex) # Reject high bits before converting to a native index.
  AccumulationTransferCollectionResult[DeferredTransfer](status:
    AccumulationTransferCollectionError.None, completed: data.transfers[int(uint64(index))])

proc prepareAccumulationTransfers*(sources: openArray[AccumulationOutcome],
    limits: AccumulationTransferCollectionLimits):
    AccumulationTransferCollectionResult[PreparedAccumulationTransfers] =
  ## Borrow the stable source array only during collection; retain immutable outcomes and copy complete transfers.
  ## Supplied source order is explicit and no unique service membership or common-parent certificate is implied.
  # Return the selected reason without exposing partially collected owners.
  template fail(reason: AccumulationTransferCollectionError) =
    return AccumulationTransferCollectionResult[PreparedAccumulationTransfers](status: reason)
  if uint64(sources.len) > uint64(limits.sources) or
      sources.len > high(int) div sizeof(AccumulationOutcome):
    fail(AccumulationTransferCollectionError.LimitExceeded) # Bound source traversal and allocation before inspecting owners.
  var count = 0'u64
  for source in sources:
    # Validate every selected owner and extent before allocating any retained array or transfer copy.
    let info = source.outcomeInfo
    if info.error != AccumulationOutcomeError.None:
      fail(AccumulationTransferCollectionError.InvalidOutcome) # A default is never interpreted as a zero-transfer execution.
    if uint64(info.value.transfers) > uint64(limits.transfers)-count:
      fail(AccumulationTransferCollectionError.LimitExceeded) # Subtraction proves the aggregate cannot wrap.
    count += uint64(info.value.transfers)
  if count > uint64(limits.memoBytes) div 128 or
      count > uint64(high(int) div sizeof(DeferredTransfer)):
    fail(AccumulationTransferCollectionError.LimitExceeded) # Prove fixed memo multiplication and native transfer allocation.
  var retained = newSeq[AccumulationOutcome](sources.len)
  var transfers = newSeq[DeferredTransfer](int(count))
  var cursor = 0
  for index, source in sources:
    # Preserve both caller outcome order and the selected context's append order, without deduplication.
    retained[index] = source
    let context = source.outcomeContext.value
    for ordinal in 0..<source.outcomeInfo.value.transfers:
      transfers[cursor] = context.effectTransferAt(AccumulationTransferIndex(uint64(ordinal))).value
      inc cursor # Preflighted immutable cardinalities prove this native cursor is bounded.
  AccumulationTransferCollectionResult[PreparedAccumulationTransfers](status:
    AccumulationTransferCollectionError.None, completed: PreparedAccumulationTransfers(
      data: TransferCollectionData(sources: retained, transfers: transfers,
        info: AccumulationTransferCollectionInfo(sources: sources.len, transfers: int(count),
          memoBytes: AccumulationMemoBytes(count*128)))))
