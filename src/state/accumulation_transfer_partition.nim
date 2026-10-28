# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP fnpartitionxfers: stable deferred-transfer scheduling with incarnation-bound supervision.
## Pure owned plans retain exact input records/prior; round selection and publication belong to their callers.
import std/assertions
import ../codec/bounded as codec_bounded
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/c2_records as codec_c2_records
import ./store as state_store

type
  TransferPartitionIndex* = distinct uint64 ## Selected-output ordinal cannot substitute a service identity.
  TransferPartitionKind* {.pure.} = enum ## Choose one stable subsequence, never an unordered transfer set.
    Accepted, Queued
  TransferPartitionLimits* = object ## Input counts and predicate work are independent local resource ceilings.
    transfers*, services*: ElementLimit ## Charge every input row, including duplicate active identities.
    checks*: ElementLimit ## Charge each metadata lookup and membership comparison before performing it.
  TransferPartitionInfo* = object ## Copied observations do not replace caller limits or certify a whole accumulation round.
    transfers*, accepted*, queued*, activeEntries*: int ## Exact source/output/input-active counts.
    checks*: uint64 ## Actual bounded metadata and membership checks used for this partition.
  TransferPartitionError* {.pure.} = enum ## Failed/default alternatives contain no plan, transfer, metadata or prior payload.
    Uninitialized, None, InvalidState, MalformedState, UnknownService, LimitExceeded, InvalidKind, InvalidIndex
  Recipient = object # Fixed accepted-recipient cache belongs to one immutable prior only.
    service, supervisor: ServiceIndex
  PartitionData = ref object # Fixed record/index copies retain no borrowed spans or parent plans.
    prior: StateStoreSnapshot
    values: seq[DeferredTransfer]
    accepted, queued: seq[int]
    info: TransferPartitionInfo
  PreparedTransferPartition* = object ## Only successful checked preparation creates a retained partition.
    data: nil PartitionData
  TransferPartitionResult*[T] = object ## Guard all selected payload extraction through value.
    case status: TransferPartitionError
    of None:
      completed: T                     # Private successful payload cannot be retagged by a caller.
    else:
      discard                          # No fabricated empty-success data on refusal.

func error*[T](outcome: TransferPartitionResult[T]): TransferPartitionError =
  ## Inspect a reason without exposing inactive payload storage.
  outcome.status
func value*[T](outcome: TransferPartitionResult[T]): T {.inline,
    requires: outcome.status == TransferPartitionError.None.} =
  ## Copy or retain only an actual successful payload, including checked release builds.
  outcome.completed

proc metadata(prior: StateStoreSnapshot, service: ServiceIndex): TransferPartitionResult[
    ServiceMetadata] =
  ## Read one complete canonical account, preserving absence separately from malformed state.
  let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    return TransferPartitionResult[ServiceMetadata](
        status: TransferPartitionError.UnknownService) # Missing destinations/supervisors have explicit caller handling.
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    return TransferPartitionResult[ServiceMetadata](
        status: TransferPartitionError.MalformedState) # Never repair or guess malformed account metadata.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return TransferPartitionResult[ServiceMetadata](
        status: TransferPartitionError.MalformedState) # Require the canonical version and complete record.
  TransferPartitionResult[ServiceMetadata](status: TransferPartitionError.None,
      completed: decoded.value.metadata)

proc partitionInfo*(plan: PreparedTransferPartition): TransferPartitionResult[
    TransferPartitionInfo] =
  ## Inspect copied counts/work from the exact successfully retained partition.
  let data = plan.data
  if data == nil:
    return TransferPartitionResult[TransferPartitionInfo](
        status: TransferPartitionError.Uninitialized) # No default successful empty plan.
  TransferPartitionResult[TransferPartitionInfo](status: TransferPartitionError.None,
      completed: data.info)
proc partitionPrior*(plan: PreparedTransferPartition): TransferPartitionResult[StateStoreSnapshot] =
  ## Retain the exact immutable prior used for every supervision decision.
  let data = plan.data
  if data == nil:
    return TransferPartitionResult[StateStoreSnapshot](
        status: TransferPartitionError.Uninitialized) # No substituted default state.
  TransferPartitionResult[StateStoreSnapshot](status: TransferPartitionError.None,
      completed: data.prior)
proc partitionCount*(plan: PreparedTransferPartition,
    kind: TransferPartitionKind): TransferPartitionResult[int] =
  ## Count one stable output without exposing mutable index or record storage.
  let data = plan.data
  if data == nil:
    return TransferPartitionResult[int](status: TransferPartitionError.Uninitialized) # Defaults own neither output.
  if kind notin {TransferPartitionKind.Accepted, TransferPartitionKind.Queued}:
    return TransferPartitionResult[int](status: TransferPartitionError.InvalidKind) # No invalid selector can borrow another output's bounds.
  let count = if kind == TransferPartitionKind.Accepted: data.accepted.len else: data.queued.len
  TransferPartitionResult[int](status: TransferPartitionError.None, completed: count)
proc partitionTransferAt*(plan: PreparedTransferPartition, kind: TransferPartitionKind,
    index: TransferPartitionIndex): TransferPartitionResult[DeferredTransfer] =
  ## Copy a complete fixed record at a checked nominal output ordinal.
  let count = plan.partitionCount(kind)
  if count.error != TransferPartitionError.None:
    return TransferPartitionResult[DeferredTransfer](
        status: count.error) # Defaults/invalid selectors expose no record.
  if uint64(index) >= uint64(count.value):
    return TransferPartitionResult[DeferredTransfer](
        status: TransferPartitionError.InvalidIndex) # Bound the whole register-sized ordinal before narrowing.
  let data = plan.data
  assert data != nil # Successful count retains this initialized owner.
  let source = if kind == TransferPartitionKind.Accepted: data.accepted[int(uint64(
      index))] else: data.queued[int(uint64(index))]
  assert source >= 0 and source < data.values.len # Only preparation writes these bounded private source ordinals.
  TransferPartitionResult[DeferredTransfer](status: TransferPartitionError.None,
      completed: data.values[source])

proc prepareAccumulationTransferPartition*(prior: StateStoreSnapshot,
    transfers: openArray[DeferredTransfer], active: openArray[ServiceIndex],
    limits: TransferPartitionLimits): TransferPartitionResult[PreparedTransferPartition] =
  ## Apply the exact left-to-right paper predicates against one immutable prior, preserving both subsequence orders.
  ## Borrowed inputs must stay stable during this call; success owns independent fixed records and output indices.
  template fail(reason: TransferPartitionError) =
    return TransferPartitionResult[PreparedTransferPartition](status: reason)
  if not sameStateSnapshot(prior, prior):
    fail(TransferPartitionError.InvalidState) # A default prior cannot authorize supervision or an empty certificate.
  if uint64(transfers.len) > uint64(limits.transfers) or uint64(active.len) > uint64(
      limits.services):
    fail(TransferPartitionError.LimitExceeded) # Bound both complete source traversals, including duplicate rows.
  const extent = sizeof(DeferredTransfer)+sizeof(bool)+2*sizeof(int)+sizeof(Recipient)
  if transfers.len > high(int) div extent:
    fail(TransferPartitionError.LimitExceeded) # Prove every typed scratch/retained allocation extent before multiplying or allocating.
  var work = 0'u64
  template spend() =
    if work >= uint64(limits.checks):
      fail(TransferPartitionError.LimitExceeded)
    inc work # The preceding comparison proves the unsigned increment fits.
  var held = newSeq[bool](transfers.len)
  var recipients = newSeq[Recipient](transfers.len)
  var recipientCount = 0
  var acceptedCount = 0
  var queuedCount = 0
  for index, transfer in transfers:
    spend()
    let found = metadata(prior, transfer.destination)
    if found.error == TransferPartitionError.UnknownService:
      inc acceptedCount # A missing target is accepted, but cannot join the present-recipient set.
      continue
    if found.error != TransferPartitionError.None:
      fail(found.error) # No malformed metadata becomes an absent account or fallback supervisor.
    let target = transfer.destination
    var supervisor = target
    if uint32(found.value.supervisor) != uint32(target):
      spend()
      let nominee = metadata(prior, found.value.supervisor)
      if nominee.error == TransferPartitionError.None:
        if uint32(nominee.value.created) == uint32(found.value.supervisorCreated):
          supervisor = found.value.supervisor # Current matching incarnation alone grants effective supervision.
      elif nominee.error != TransferPartitionError.UnknownService:
        fail(nominee.error) # A missing nominee falls back to self; corrupt nominees do not.
    var queued = false
    if uint32(supervisor) != uint32(target):
      for service in active:
        spend()
        if uint32(service) == uint32(supervisor):
          queued = true
          break # Active report/always services prevent concurrent transfer credit to their junior.
      if not queued:
        for ordinal in 0..<recipientCount:
          spend()
          if uint32(recipients[ordinal].service) == uint32(supervisor):
            queued = true
            break # Earlier accepted supervisor transfers are active in this same round too.
    var repeated = false
    if not queued:
      for ordinal in 0..<recipientCount:
        spend()
        let earlier = recipients[ordinal]
        if uint32(earlier.service) == uint32(target):
          repeated = true # Duplicate recipients alone never conflict or consume a second cache slot.
        elif uint32(earlier.supervisor) == uint32(target):
          queued = true
          break # A supervisor cannot receive a transfer after an accepted junior in the same round.
    held[index] = queued
    if queued:
      inc queuedCount # Neither this target nor its supervisor enters the accepted-recipient set.
    else:
      inc acceptedCount
      if not repeated:
        assert recipientCount < recipients.len # At most one present recipient is added per visited source row.
        recipients[recipientCount] = Recipient(service: target, supervisor: supervisor)
        inc recipientCount
  var values = newSeq[DeferredTransfer](transfers.len)
  var accepted = newSeq[int](acceptedCount)
  var queued = newSeq[int](queuedCount)
  var now = 0
  var later = 0
  for index, transfer in transfers:
    values[index] = transfer # Fixed memos and every flag/gas/amount remain independent of caller storage.
    if held[index]:
      queued[later] = index
      inc later
    else:
      accepted[now] = index
      inc now
  let info = TransferPartitionInfo(transfers: transfers.len, accepted: acceptedCount,
      queued: queuedCount, activeEntries: active.len, checks: work)
  TransferPartitionResult[PreparedTransferPartition](status: TransferPartitionError.None,
      completed: PreparedTransferPartition(data: PartitionData(prior: prior, values: values,
          accepted: accepted, queued: queued, info: info)))
