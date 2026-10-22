# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Plan the transfer-aware initial accseq continuation after an admitted completed initial round.
## Retains source and original queue without copying prior reports, executing guests or publishing state.

import ../codec/[bounded, work_digest, report_owned]
import ./[accumulation_execution, accumulation_round, accumulation_queue, accumulation_operands,
  accumulation_round_transfers, accumulation_transfers, accumulation_pending_transfers]

type
  AccumulationContinuationLimits* = object ## Independent traversal ceilings include inspected but unaffordable work.
    executions*: ElementLimit ## Maximum completed execution outcomes inspected for outgoing transfers.
    transfers*: ElementLimit ## Maximum outgoing fixed records copied; zero authorizes no nonempty sequence.
    memoBytes*: ByteLimit ## Aggregate copied memo bytes, including repeated transfers.
    reports*: ElementLimit ## Maximum unprocessed reports inspected, including the first rejected report.
    digests*: ElementLimit ## Maximum digest gas values inspected, including those in a rejected report.
  AccumulationContinuationInfo* = object ## Copied recursive-entry planning facts do not certify later execution or state publication.
    completedPrefix*: AccumulationReportPrefix ## Reports already processed by the completed initial round.
    pendingReports*: int              ## Reports in the original priority suffix before this new selection.
    prefix*: AccumulationReportPrefix ## Newly selected whole-report prefix of that suffix.
    budget*: Gas ## Recursive input budget: original minus actual initial gas plus paid outgoing gas.
    transfers*: int                   ## Selected outgoing records, including zero-gas transfers.
    transferGas*: Gas ## Paid outgoing gas restored to the budget and reserved before report selection.
    reportGas*: Gas                   ## Declared digest gas reserved by the newly selected reports.
    dispatch*: bool ## True exactly when a remaining report or outgoing transfer is selected; no free allowances recur.
  ContinuationReportIndex* = distinct uint64 ## Plan-local selected-report ordinal, distinct from original queue positions.
  AccumulationContinuationError* {.pure.} = enum ## Refusals retain no selected prefix, source owner or partial gas progress.
    Uninitialized, ## Default result or plan without initialized ownership.
    None,          ## Complete selected success permits guarded extraction.
    InvalidSource, ## The supplied completion is uninitialized or has no valid queue-prefix provenance.
    InvalidIndex,  ## The full-width plan-local ordinal is outside its selected report range.
    LimitExceeded, ## Outcome, remaining-report or digest inspection exceeds its independent ceiling.
    UnsupportedTransfers ## Reserved historical refusal; transfer support requires explicit count/memo policy.
  # Private acyclic storage keeps the actual completion and original immutable priority queue together.
  ContinuationData = ref object
    source: CompletedBlockAccumulation
    queue: AccumulationQueuePlan
    transfers: PreparedRoundAccumulationTransfers
    pending: PreparedPendingTransfers
    info: AccumulationContinuationInfo
  PreparedAccumulationContinuation* = object ## Only a completed admitted initial round can authorize this transfer-aware initial recursive prefix plan.
    data: nil ContinuationData
  AccumulationContinuationResult*[T] = object ## Failed/default alternatives carry reasons alone, never an earlier successful candidate.
    case status: AccumulationContinuationError
    of None:
      completed: T # Complete selected success alone exposes an immutable owner or copied observation.
    else:
      discard # No partial selection or default report handle accompanies refusal.

func error*[T](outcome: AccumulationContinuationResult[T]): AccumulationContinuationError =
  ## Inspect the selected reason without exposing a mutable discriminator.
  outcome.status

func value*[T](outcome: AccumulationContinuationResult[T]): T {.inline,
    requires: outcome.status == AccumulationContinuationError.None.} =
  ## Extract selected success under checked optimized contracts.
  outcome.completed

proc continuationInfo*(plan: PreparedAccumulationContinuation): AccumulationContinuationResult[
    AccumulationContinuationInfo] =
  ## Copy the retained prefix and recursive budget; mutating the copy cannot alter selection.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationResult[AccumulationContinuationInfo](
        status: AccumulationContinuationError.Uninitialized) # Defaults do not imply a successful stopped continuation.
  AccumulationContinuationResult[AccumulationContinuationInfo](
      status: AccumulationContinuationError.None, completed: data.info)

proc continuationSource*(plan: PreparedAccumulationContinuation): AccumulationContinuationResult[
    CompletedBlockAccumulation] =
  ## Retain the exact admitted completion independently of this plan's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationResult[CompletedBlockAccumulation](
        status: AccumulationContinuationError.Uninitialized) # No synthetic initial execution certificate.
  AccumulationContinuationResult[CompletedBlockAccumulation](
      status: AccumulationContinuationError.None, completed: data.source)

proc continuationTransfers*(plan: PreparedAccumulationContinuation):
    AccumulationContinuationResult[PreparedRoundAccumulationTransfers] =
  ## Retain this plan's exact completed-round outgoing owner; no substitute collection is accepted.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationResult[PreparedRoundAccumulationTransfers](
      status: AccumulationContinuationError.Uninitialized) # Default plans cannot provide a recursive transfer sequence.
  AccumulationContinuationResult[PreparedRoundAccumulationTransfers](
    status: AccumulationContinuationError.None, completed: data.transfers)

proc continuationPending*(plan: PreparedAccumulationContinuation): AccumulationContinuationResult[
    PreparedPendingTransfers] =
  ## Retain the actual initial pending owner whose producer usage and prior budget match this completion.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationResult[PreparedPendingTransfers](
        status: AccumulationContinuationError.Uninitialized) # No default pending source.
  AccumulationContinuationResult[PreparedPendingTransfers](
      status: AccumulationContinuationError.None, completed: data.pending)

proc continuationReportAt*(plan: PreparedAccumulationContinuation, index: ContinuationReportIndex):
    AccumulationContinuationResult[OwnedReport] =
  ## Retain one selected report at a local ordinal; completed-prefix reports cannot be readdressed through this accessor.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationResult[OwnedReport](
        status: AccumulationContinuationError.Uninitialized) # No default report owner.
  if uint64(index) >= uint64(data.info.prefix):
    return AccumulationContinuationResult[OwnedReport](
        status: AccumulationContinuationError.InvalidIndex) # Prove the full-width local ordinal before offset addition.
  # Construction proves completedPrefix + prefix <= original native queue count, so this addition fits.
  let position = uint64(data.info.completedPrefix) + uint64(index)
  AccumulationContinuationResult[OwnedReport](status: AccumulationContinuationError.None,
    completed: data.queue.accumulationAt(AccumulationIndex(position)).value)

proc planAccumulationContinuation*(source: CompletedBlockAccumulation,
    limits: AccumulationContinuationLimits):
    AccumulationContinuationResult[PreparedAccumulationContinuation] =
  ## Select the next affordable whole-report prefix using actual gas, reserved outgoing gas, the original queue suffix and no recurring allowances.
  ## Inspected rejected reports consume local work ceilings; preparation copies only bounded outgoing values and performs no hashing or publication.
  # Refuse without exposing an earlier selected prefix or partial recursive budget.
  template fail(reason: AccumulationContinuationError) =
    return AccumulationContinuationResult[PreparedAccumulationContinuation](status: reason)
  let completed = source.executionInfo
  if completed.error != AccumulationExecutionError.None:
    fail(AccumulationContinuationError.InvalidSource) # Default owners cannot authorize recursive scheduling.
  let facts = completed.value
  if uint64(facts.batch.executions) > uint64(limits.executions):
    fail(AccumulationContinuationError.LimitExceeded) # Bound even outcomes with no selected transfers.
  let transfers = prepareRoundAccumulationTransfers(source, AccumulationTransferCollectionLimits(
    sources: limits.executions, transfers: limits.transfers, memoBytes: limits.memoBytes))
  if transfers.error == AccumulationRoundTransferError.LimitExceeded:
    fail(AccumulationContinuationError.LimitExceeded) # Explicit transfer and memo policy bounds every retained outgoing record.
  if transfers.error != AccumulationRoundTransferError.None:
    fail(AccumulationContinuationError.InvalidSource) # No inconsistent completed owner can authorize recursive gas restoration.
  let outgoing = transfers.value.roundTransferInfo.value
  let pending = prepareInitialPendingTransfers(transfers.value.roundTransferCollection.value,
      facts.round.budget, PendingTransferLimits(sources: limits.executions,
          transfers: limits.transfers, memoBytes: limits.memoBytes))
  if pending.error == PendingTransferError.LimitExceeded:
    fail(AccumulationContinuationError.LimitExceeded) # Bound the additional owned pending capture too.
  if pending.error != PendingTransferError.None:
    fail(AccumulationContinuationError.InvalidSource) # A real completion must retain valid budget and producer usage.
  let pendingInfo = pending.value.pendingTransferInfo.value
  if uint64(pendingInfo.gasUsed) != uint64(facts.gasUsed) or uint64(pendingInfo.outgoingGas) !=
      uint64(outgoing.gas):
    fail(AccumulationContinuationError.InvalidSource) # Actual normalized producer totals must match the authenticated completion.
  let queue = source.executionRound.value.roundBlockQueue.value.accumulationProjection.value
  let count = queue.accumulationCount.value
  let start = uint64(facts.round.prefix)
  if start > uint64(count) or uint64(facts.gasUsed) > uint64(facts.round.budget):
    fail(AccumulationContinuationError.InvalidSource) # Prove suffix conversion and recursive budget subtraction.
  let reportBudget = uint64(pendingInfo.reportBudget)
  let budget = uint64(pendingInfo.budget)
  var remaining = reportBudget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  for index in int(start)..<count:
    # Completed-prefix reports are neither copied nor traversed again.
    if reports >= uint64(limits.reports):
      fail(AccumulationContinuationError.LimitExceeded)
    inc reports
    let report = queue.accumulationAt(AccumulationIndex(uint64(index))).value
    let length = ownedReportInfo(report).value.digestCount
    var candidate = remaining
    var fits = true
    for digest in 0..<length:
      # Subtraction proves affordability without wrapping a mathematical report gas sum.
      if digests >= uint64(limits.digests):
        fail(AccumulationContinuationError.LimitExceeded)
      inc digests
      let gas = uint64(ownedReportDigest(report, digest).value.accumulateGas)
      if gas > candidate:
        fits = false
        break # No later report may bypass this unaffordable whole report.
      candidate -= gas
    if not fits: break # None of this report's earlier digest reservations is committed.
    remaining = candidate
    inc prefix # Bounded by the original native queue's suffix length.
  AccumulationContinuationResult[PreparedAccumulationContinuation](
    status: AccumulationContinuationError.None,
    completed: PreparedAccumulationContinuation(data: ContinuationData(source: source, queue: queue,
      transfers: transfers.value, pending: pending.value,
      info: AccumulationContinuationInfo(completedPrefix: facts.round.prefix,
        pendingReports: count-int(start), prefix: AccumulationReportPrefix(prefix), budget: Gas(
            budget),
        transfers: outgoing.collection.transfers, transferGas: outgoing.gas,
        reportGas: Gas(reportBudget-remaining), dispatch: prefix != 0 or
            outgoing.collection.transfers != 0))))
