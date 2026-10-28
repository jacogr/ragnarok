# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect explicit-order or current accpar outgoing transfers with immutable source proof and work limits.
## This captures provenance and values, without certifying round membership or applying deferred credits.

import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/c2_records as codec_c2_records
import ../codec/state_accounts as codec_state_accounts
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_effects as state_accumulation_effects
import ./accumulation_annulment as state_accumulation_annulment

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
    Uninitialized, None, InvalidOutcome, InvalidIndex, LimitExceeded, InvalidSelection, NoAnnulment
  # Private acyclic owner retains the exact normalized sources and complete fixed-value transfer copies.
  TransferCollectionData = ref object
    selection: PreparedAccumulationAnnulment
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

proc transferCollectionAnnulment*(plan: PreparedAccumulationTransfers):
    AccumulationTransferCollectionResult[PreparedAccumulationAnnulment] =
  ## Retain the exact accpar certificate; ordinary explicit-order collections have no conflict-selection claim.
  let data = plan.data
  if data == nil:
    return AccumulationTransferCollectionResult[PreparedAccumulationAnnulment](
        status: AccumulationTransferCollectionError.Uninitialized) # No default collection provenance.
  if data.selection.annulmentInfo.error != AccumulationAnnulmentError.None:
    return AccumulationTransferCollectionResult[PreparedAccumulationAnnulment](
        status: AccumulationTransferCollectionError.NoAnnulment) # Initialized ordinary collections remain distinct from bound accpar projections.
  AccumulationTransferCollectionResult[PreparedAccumulationAnnulment](
      status: AccumulationTransferCollectionError.None, completed: data.selection)

type SelectedTransferSource = object # Sort only nominal service identity; retain original owner and selected count together.
  service: ServiceIndex
  outcome: AccumulationOutcome
  transfers: int

func compareSource(left, right: SelectedTransferSource): int =
  ## Current accpar concatenates in numeric service order, independent of execution/certificate array order.
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0 # Genuine annulment certificates already prove unique service membership.

proc prepareAnnulmentTransfers*(selection: PreparedAccumulationAnnulment,
    limits: AccumulationTransferCollectionLimits):
    AccumulationTransferCollectionResult[PreparedAccumulationTransfers] =
  ## Collect selected outgoing values while retaining every actual producer for pending-budget gas accounting.
  ## The certificate owns common-source/unique-service/conflict proof; no caller-authored flags or substituted maps are accepted.
  template fail(reason: AccumulationTransferCollectionError) =
    return AccumulationTransferCollectionResult[PreparedAccumulationTransfers](status: reason)
  let selected = selection.annulmentInfo
  if selected.error != AccumulationAnnulmentError.None:
    fail(AccumulationTransferCollectionError.InvalidSelection) # A default certificate is not an initialized empty source set.
  let count = selected.value.outcomes
  const sourceBytes = sizeof(SelectedTransferSource)+sizeof(AccumulationOutcome)
  if uint64(count) > uint64(limits.sources) or count > high(int) div sourceBytes:
    fail(AccumulationTransferCollectionError.LimitExceeded) # Bound all producers, including canceled and empty-output originals, before capture/sort.
  var rows = newSeq[SelectedTransferSource](count)
  var total = 0'u64
  for index in 0..<count:
    let ordinal = AccumulationAnnulmentIndex(uint64(index))
    let info = selection.annulmentSelectedInfoAt(ordinal).value
    if uint64(info.transfers) > uint64(limits.transfers)-total:
      fail(AccumulationTransferCollectionError.LimitExceeded) # Only surviving append counts consume the selected record cap.
    total += uint64(info.transfers)
    rows[index] = SelectedTransferSource(service: info.service,
      outcome: selection.annulmentOriginalOutcomeAt(ordinal).value,
      transfers: info.transfers) # Original gas/provisions remain inseparable from their genuine source even when selected transfers are zero.
  if total > uint64(limits.memoBytes) div 128 or total > uint64(high(int) div sizeof(
      DeferredTransfer)):
    fail(AccumulationTransferCollectionError.LimitExceeded) # Prove exact memo bytes and native record extent before allocating or multiplying.
  rows.sort(compareSource)
  var originals = newSeq[AccumulationOutcome](count)
  var transfers = newSeq[DeferredTransfer](int(total))
  var cursor = 0
  for index, row in rows:
    originals[index] = row.outcome # Retain all original producers in the same canonical source order.
    let context = row.outcome.outcomeContext.value
    for ordinal in 0..<row.transfers:
      transfers[cursor] = context.effectTransferAt(AccumulationTransferIndex(uint64(ordinal))).value
      inc cursor # Frozen selected cardinalities and checked total prove every access is in range.
  AccumulationTransferCollectionResult[PreparedAccumulationTransfers](
    status: AccumulationTransferCollectionError.None,
    completed: PreparedAccumulationTransfers(data: TransferCollectionData(selection: selection,
      sources: originals, transfers: transfers,
      info: AccumulationTransferCollectionInfo(sources: count, transfers: int(total),
        memoBytes: AccumulationMemoBytes(total*128)))))
