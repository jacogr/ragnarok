# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current accseq pending transfers: prior queued records precede newly emitted records without a double gas refund.
## Pure owned preparation checks explicit budget facts; authenticated round integration belongs to callers.
import std/assertions
import ../../codec/[bounded, composite]
import ../../codec/state/accounts as state_accounts
import ../../codec/c2_records
import ./[transfers as accumulation_transfers, transfer_partition as accumulation_transfer_partition,
    outcome as accumulation_outcome]
import ../store

type
  PendingTransferIndex* = distinct uint64 ## Pending ordinal cannot substitute an outgoing-collection or partition ordinal.
  PendingTransferLimits* = object ## Copied pending records and memo work have independent explicit ceilings.
    sources*: ElementLimit ## Charge every retained producer inspected, including empty-output outcomes.
    transfers*: ElementLimit ## Charge carried and new records, including duplicates and zero-gas transfers.
    memoBytes*: ByteLimit ## Charge128 fixed memo octets per copied record.
  PendingTransferInfo* = object ## Copied observations retain arithmetic provenance without certifying caller-supplied gas facts.
    transfers*, carried*, outgoing*: int ## Ordered pending count and its old/new components.
    sourceBudget*, gasUsed*: Gas ## Explicit prior budget and usage derived from retained producer outcomes.
    budget*, carriedGas*, outgoingGas*, reservedGas*,
      reportBudget*: Gas                 ## Proven recursive budget, reservations and remaining report allowance.
  PendingTransferError* {.pure.} = enum ## Default/refused alternatives retain no queue, copied record or partial budget.
    Uninitialized, None, InvalidSource, InvalidBudget, LimitExceeded, InvalidIndex, NoPrevious, PartitionFailure
  PendingData = ref object # Acyclic provenance handles and independent fixed records retain no parent queues.
    outgoing: PreparedAccumulationTransfers
    previous: PreparedTransferPartition
    hasPrevious: bool
    values: seq[DeferredTransfer]
    info: PendingTransferInfo
  PreparedPendingTransfers* = object ## Only successful checked construction supplies an owned pending sequence.
    data: nil PendingData
  PendingTransferResult*[T] = object ## Selected success or selected nested partition failure alone exposes its private payload.
    case status: PendingTransferError
    of None:
      completed: T # Private successful payload cannot be retagged by callers.
    of PartitionFailure:
      partitionReason: TransferPartitionError # No successful partition or partial queue escapes failure.
    else:
      discard      # Ordinary refusal carries only its reason.

func error*[T](outcome: PendingTransferResult[T]): PendingTransferError =
  ## Inspect a reason without exposing inactive success or nested-failure storage.
  outcome.status
func value*[T](outcome: PendingTransferResult[T]): T {.inline,
    requires: outcome.status == PendingTransferError.None.} =
  ## Extract only an actual selected success, including checked optimized builds.
  outcome.completed
func partitionError*[T](outcome: PendingTransferResult[T]): TransferPartitionError {.inline,
    requires: outcome.status == PendingTransferError.PartitionFailure.} =
  ## Inspect only the reason of an actual nested partition refusal.
  outcome.partitionReason

proc pendingTransferInfo*(plan: PreparedPendingTransfers): PendingTransferResult[
    PendingTransferInfo] =
  ## Copy exact pending counts and proven recursive gas arithmetic.
  let data = plan.data
  if data == nil:
    return PendingTransferResult[PendingTransferInfo](
        status: PendingTransferError.Uninitialized) # No default successful empty queue.
  PendingTransferResult[PendingTransferInfo](status: PendingTransferError.None,
      completed: data.info)
proc pendingTransferAt*(plan: PreparedPendingTransfers,
    index: PendingTransferIndex): PendingTransferResult[DeferredTransfer] =
  ## Copy a complete fixed pending record after bounding the full nominal ordinal.
  let data = plan.data
  if data == nil:
    return PendingTransferResult[DeferredTransfer](
        status: PendingTransferError.Uninitialized) # No fabricated record.
  if uint64(index) >= uint64(data.values.len):
    return PendingTransferResult[DeferredTransfer](
        status: PendingTransferError.InvalidIndex) # Bound before native narrowing.
  PendingTransferResult[DeferredTransfer](status: PendingTransferError.None, completed: data.values[
      int(uint64(index))])
proc pendingOutgoing*(plan: PreparedPendingTransfers): PendingTransferResult[
    PreparedAccumulationTransfers] =
  ## Retain the exact newly emitted producer collection; carried records never masquerade as a new refund source.
  let data = plan.data
  if data == nil:
    return PendingTransferResult[PreparedAccumulationTransfers](
        status: PendingTransferError.Uninitialized) # No substitute outgoing owner.
  PendingTransferResult[PreparedAccumulationTransfers](status: PendingTransferError.None,
      completed: data.outgoing)
proc pendingPreviousPartition*(plan: PreparedPendingTransfers): PendingTransferResult[
    PreparedTransferPartition] =
  ## Retain the actual carried source; first entries report NoPrevious instead of inventing an empty partition.
  let data = plan.data
  if data == nil:
    return PendingTransferResult[PreparedTransferPartition](
        status: PendingTransferError.Uninitialized) # Defaults are not first-entry provenance.
  if not data.hasPrevious:
    return PendingTransferResult[PreparedTransferPartition](
        status: PendingTransferError.NoPrevious) # Initial queues retain no prior partition.
  PendingTransferResult[PreparedTransferPartition](status: PendingTransferError.None,
      completed: data.previous)

proc preparePending(outgoing: PreparedAccumulationTransfers, previous: PreparedTransferPartition,
    hasPrevious: bool, budget: Gas, limits: PendingTransferLimits): PendingTransferResult[
        PreparedPendingTransfers] =
  ## Shared checked capture has no public raw-record or caller-selected payload shortcut.
  template fail(reason: PendingTransferError) =
    return PendingTransferResult[PreparedPendingTransfers](status: reason)
  let source = outgoing.transferCollectionInfo
  if source.error != AccumulationTransferCollectionError.None:
    fail(PendingTransferError.InvalidSource) # A default collection never authorizes a paid-gas refund.
  if uint64(source.value.sources) > uint64(limits.sources):
    fail(PendingTransferError.LimitExceeded) # Bound producer traversal independently of emitted record counts.
  var carried = 0
  if hasPrevious:
    let prior = previous.partitionCount(TransferPartitionKind.Queued)
    if prior.error != TransferPartitionError.None:
      fail(PendingTransferError.InvalidSource) # A later queue requires a genuinely prepared prior partition.
    carried = prior.value
  let count = source.value.transfers
  if carried > high(int)-count:
    fail(PendingTransferError.LimitExceeded) # Prove native concatenation before adding counts.
  let total = carried+count
  if uint64(total) > uint64(limits.transfers) or total > high(int) div sizeof(DeferredTransfer) or
      uint64(total) > uint64(limits.memoBytes) div 128:
    fail(PendingTransferError.LimitExceeded) # Bound every fixed allocation and copied memo before work.
  var remaining = uint64(budget)
  for index in 0..<source.value.sources:
    let producer = outgoing.transferCollectionSourceAt(AccumulationTransferSourceIndex(uint64(index)))
    if producer.error != AccumulationTransferCollectionError.None:
      fail(PendingTransferError.InvalidSource) # No substituted source can contribute actual usage.
    let used = producer.value.outcomeInfo
    if used.error != AccumulationOutcomeError.None:
      fail(PendingTransferError.InvalidSource) # Require actual normalized producer facts.
    if uint64(used.value.gasUsed) > remaining:
      fail(PendingTransferError.InvalidBudget) # Subtract every use without forming an overflowing aggregate.
    remaining -= uint64(used.value.gasUsed)
  let gasUsed = uint64(budget)-remaining
  var reportBudget = remaining
  var refundable = gasUsed
  var values = newSeq[DeferredTransfer](total)
  for index in 0..<carried:
    let row = previous.partitionTransferAt(TransferPartitionKind.Queued, TransferPartitionIndex(
        uint64(index)))
    if row.error != TransferPartitionError.None:
      fail(PendingTransferError.InvalidSource) # Failed source extraction cannot become a partial successful queue.
    if uint64(row.value.gas) > reportBudget:
      fail(PendingTransferError.InvalidBudget) # Old queued gas stays reserved; it is never added back as a refund.
    reportBudget -= uint64(row.value.gas)
    values[index] = row.value # Carried subsequence precedes every newly emitted record, including duplicates.
  for index in 0..<count:
    let row = outgoing.collectedTransferAt(CollectedTransferIndex(uint64(index)))
    if row.error != AccumulationTransferCollectionError.None:
      fail(PendingTransferError.InvalidSource) # Retain only complete canonical producer output.
    if uint64(row.value.gas) > refundable:
      fail(PendingTransferError.InvalidBudget) # Only newly emitted gas paid within actual usage can be restored.
    refundable -= uint64(row.value.gas)
    values[carried+index] = row.value # Proven total extent bounds the ordered append position.
  let paid = gasUsed-refundable
  let held = remaining-reportBudget
  let next = remaining+paid # paid<=gasUsed proves next<=budget and no overflow.
  let reserved = held+paid # held<=remaining proves this sum<=next and no overflow.
  let info = PendingTransferInfo(transfers: total, carried: carried, outgoing: count,
      sourceBudget: budget, gasUsed: Gas(gasUsed), budget: Gas(next), carriedGas: Gas(held),
          outgoingGas: Gas(paid),
      reservedGas: Gas(reserved), reportBudget: Gas(reportBudget))
  PendingTransferResult[PreparedPendingTransfers](status: PendingTransferError.None,
      completed: PreparedPendingTransfers(data: PendingData(outgoing: outgoing, previous: previous,
          hasPrevious: hasPrevious, values: values, info: info)))

proc prepareInitialPendingTransfers*(outgoing: PreparedAccumulationTransfers, budget: Gas,
    limits: PendingTransferLimits): PendingTransferResult[PreparedPendingTransfers] =
  ## Prepare the first queue from genuine outgoing values, their actual usage and an explicit prior budget.
  preparePending(outgoing, default(PreparedTransferPartition), false, budget, limits)
proc prepareCarriedPendingTransfers*(previous: PreparedTransferPartition,
    outgoing: PreparedAccumulationTransfers,

budget: Gas, limits: PendingTransferLimits): PendingTransferResult[
        PreparedPendingTransfers] =
  ## Queue prior held values before new output without restoring their paid gas twice.
  preparePending(outgoing, previous, true, budget, limits)
proc partitionPendingTransfers*(plan: PreparedPendingTransfers, prior: StateStoreSnapshot,
    active: openArray[ServiceIndex], limits: TransferPartitionLimits): PendingTransferResult[
        PreparedTransferPartition] =
  ## Partition this exact owned sequence against the caller's explicit current immutable state and active services.
  let data = plan.data
  if data == nil:
    return PendingTransferResult[PreparedTransferPartition](
        status: PendingTransferError.Uninitialized) # No default queue can fabricate an empty partition.
  let partition = prepareAccumulationTransferPartition(prior, data.values, active, limits)
  if partition.error != TransferPartitionError.None:
    return PendingTransferResult[PreparedTransferPartition](
        status: PendingTransferError.PartitionFailure,

partitionReason: partition.error) # Preserve the actual nested refusal with no partial partition.
  PendingTransferResult[PreparedTransferPartition](status: PendingTransferError.None,
      completed: partition.value)
