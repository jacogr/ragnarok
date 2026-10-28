# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Own preparation and completion of bounded transfer-aware accseq reentries, applying only the just-completed batch privately.
## Retains immutable original-queue provenance and actual full-map successor without publishing caller state.

import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/header as codec_header
import ../codec/work_digest as codec_work_digest
import ../codec/report_owned as codec_report_owned
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../codec/c2_records as codec_c2_records
import ./accumulation_continuation_execution as state_accumulation_continuation_execution
import ./accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ./accumulation_continuation as state_accumulation_continuation
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./accumulation_operands as state_accumulation_operands
import ./accumulation_inputs as state_accumulation_inputs
import ./accumulation_batch as state_accumulation_batch
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_provisions as state_accumulation_provisions
import ./accumulation_transfers as state_accumulation_transfers
import ./accumulation_service as state_accumulation_service
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./accumulation_dispatch as state_accumulation_dispatch
import ./accumulation_skip as state_accumulation_skip
import ./accumulation_effects as state_accumulation_effects
import ./accumulation_context as state_accumulation_context
import ./accumulation_invocation as state_accumulation_invocation
import ./accumulation_pending_transfers as state_accumulation_pending_transfers
import ./accumulation_transfer_partition as state_accumulation_transfer_partition
import ./store as state_store

type
  AccumulationReentryDepth* = distinct uint64 ## Retained reentry ordinal starts at one and is distinct from report counts or gas.
  AccumulationReentryDepthLimit* = distinct uint64 ## Explicit maximum retained history depth for repeated advance.
  AccumulationReentryConfig* = object ## Selection work and input materialization have independent local ceilings.
    selection*: AccumulationContinuationLimits ## Inspected outcomes/transfers/memos/reports/digests, including rejected reports.
    operands*: AccumulationOperandConfig ## Only newly selected report payloads count toward these limits.
    inputs*: AccumulationInputConfig ## Combined transfer/report groups; no recurring allowances.
    partition*: TransferPartitionLimits ## Explicit pending-record/active-service/predicate limits; zero allows only empty transfer work.
  AccumulationReentryInfo* = object ## Copied next-entry facts retain cumulative progress without claiming later execution or final publication.
    depth*: AccumulationReentryDepth ## First reentry is one; repeated advance increments only below its explicit cap.
    completedPrefix*: AccumulationReportPrefix ## Total original reports processed by initial and completed later rounds.
    pendingReports*: int ## Original-queue reports remaining before this new selection.
    prefix*: AccumulationReportPrefix ## Newly selected whole reports after the cumulative completed offset.
    budget*: Gas         ## Prior budget minus actual gas plus paid selected outgoing gas.
    transfers*: int      ## Selected outgoing records, including zero-gas transfers.
    transferGas*: Gas    ## Paid gas restored and reserved before selecting reports.
    reportGas*: Gas      ## Declared digest gas reserved by this newly selected report range.
    dispatch*: bool      ## True exactly when reentry selects reports or transfers; stopped sources cannot restart.
  AccumulationReentryError* {.pure.} = enum ## Refusals expose no earlier range, source, inputs or state candidate.
    Uninitialized,   ## Default result or preparation handle.
    None,            ## Complete selected success permits guarded extraction.
    NoPrevious,      ## First reentry has only the original continuation root, no prior completed reentry.
    Stopped,         ## A completed n=0 entry cannot authorize another advance.
    InvalidSource,   ## No genuine completed continuation or valid range/gas provenance.
    InvalidIndex,    ## Full-width selected-report ordinal is outside the retained range.
    LimitExceeded,   ## Independent selection inspection budget exhausted.
    UnsupportedTransfers, ## Reserved historical refusal; transfer support now requires explicit count/memo policy.
    OperandFailure,  ## Inspect the selected range materialization reason.
    InputFailure,    ## Inspect the combined transfer/report grouping reason.
    ServiceFailure,  ## Inspect the actual retained-state service resolution reason.
    BatchFailure,    ## Inspect the actual failed private batch application's nested reasons.
    PartitionFailure ## Current post-batch supervision partition refused; inspect partitionError.
  # Acyclic immutable storage retains exact completed source, original queue and complete prepared successor.
  ReentryData = ref object
    source: CompletedAccumulationContinuation
    previous: nil ReentryExecutionData
    queue: AccumulationQueuePlan
    info: AccumulationReentryInfo
    inputs: PreparedAccumulationInputs
    transfers: PreparedAccumulationTransfers
    pending: PreparedPendingTransfers
    partition: PreparedTransferPartition
    state: StateStoreSnapshot
    slot: HeaderSlot
  PreparedAccumulationReentry* = object ## Reentry preparation is not later execution, final recursion or block publication.
    data: nil ReentryData
  AccumulationReentryResult*[T] = object ## Only complete success carries owners; all failed alternatives retain reasons alone.
    case status: AccumulationReentryError
    of None:
      completed: T # Guard extraction under checked optimized contracts.
    of OperandFailure:
      operandReason: AccumulationOperandError
    of InputFailure:
      inputReason: AccumulationInputError
    of ServiceFailure:
      serviceReason: AccumulationServiceError
    of PartitionFailure:
      partitionReason: TransferPartitionError
    of BatchFailure:
      failed: AccumulationBatchResult[StateStoreSnapshot] # Invariant: genuinely failed, so no successful snapshot exists.
    else:
      discard      # Defaults, bounds, transfer and invalid-source reasons carry no payload.

  AccumulationReentryExecutionInfo* = object ## Declared reentry reservations remain separate from actual terminal gas.
    round*: AccumulationReentryInfo ## Retained selected suffix and recursive budget; allowances do not recur.
    batch*: AccumulationBatchInfo ## Complete input coverage and selected provision accounting.
    services*: int                ## Number of retained service-indexed gas rows.
    gasUsed*: Gas                 ## Checked sum of actual gas, never above the reentry budget.
  AccumulationReentryExecutionError* {.pure.} = enum ## Refusals expose no completed round, gas sequence or usable batch.
    Uninitialized,   ## Default result or certificate without initialized ownership.
    None,            ## Complete selected success permits guarded extraction.
    InvalidEntropy,  ## The stage has no exact decodable posterior entropy chapter.
    EntropyMismatch, ## An execution bootstrapped from a different posterior entropy word.
    InvalidInputs,   ## No genuine prepared reentry context was supplied.
    InvalidIndex,    ## The full-width gas ordinal is outside this round's service set.
    LimitExceeded,   ## Gas-row count or descriptor extent exceeds local bounds.
    GasExceeded,     ## Actual consumption exceeds the retained reentry's remaining budget.
    BatchFailure     ## Inspect the failed complete-batch result, including its guarded nested reasons.
  # Acyclic immutable storage keeps admitted source, private batch and copied gas accounting together.
  ReentryExecutionData = ref object
    source: PreparedAccumulationReentry
    batch: PreparedAccumulationBatch
    usage: seq[AccumulationGasUsage]
    gasUsed: Gas
  CompletedAccumulationReentry* = object ## Only complete verified coverage of genuine reentry inputs constructs this owner.
    data: nil ReentryExecutionData
  AccumulationReentryExecutionResult*[T] = object ## Failed batch alternatives retain only a genuinely refused parent's reason payload.
    case status: AccumulationReentryExecutionError
    of None:
      completed: T # Only complete selected success exposes a copied observation or immutable certificate.
    of BatchFailure:
      failed: AccumulationBatchResult[PreparedAccumulationBatch] # Invariant: error != None; no success owner exists.
    else:
      discard # Defaults and other failures carry just their reason.

              # Explicit private phase inputs come only from genuine completion certificates.
  ReentryStep = object
    root: CompletedAccumulationContinuation
    previous: nil ReentryExecutionData
    prior: StateStoreSnapshot
    previousPartition: PreparedTransferPartition
    batch: PreparedAccumulationBatch
    start, processed: AccumulationReportPrefix
    budget, gasUsed: Gas
    executions: int
    dispatch: bool
    depth: AccumulationReentryDepth

func error*[T](outcome: AccumulationReentryResult[T]): AccumulationReentryError =
  ## Read the selected reason without permitting retagging.
  outcome.status
func value*[T](outcome: AccumulationReentryResult[T]): T {.inline,
    requires: outcome.status == AccumulationReentryError.None.} =
  ## Retain complete selected success only.
  outcome.completed
func partitionError*[T](outcome: AccumulationReentryResult[T]): TransferPartitionError {.inline,
    requires: outcome.status == AccumulationReentryError.PartitionFailure.} =
  ## Inspect only an actual current-state transfer-partition refusal.
  outcome.partitionReason

func operandError*[T](outcome: AccumulationReentryResult[T]): AccumulationOperandError {.inline,
    requires: outcome.status == AccumulationReentryError.OperandFailure.} =
  ## Inspect only the actual selected-range refusal.
  outcome.operandReason
func inputError*[T](outcome: AccumulationReentryResult[T]): AccumulationInputError {.inline,
    requires: outcome.status == AccumulationReentryError.InputFailure.} =
  ## Inspect only the actual service-input grouping refusal.
  outcome.inputReason
func serviceError*[T](outcome: AccumulationReentryResult[T]): AccumulationServiceError {.inline,
    requires: outcome.status == AccumulationReentryError.ServiceFailure.} =
  ## Inspect only the actual service resolution refusal.
  outcome.serviceReason
func batchFailure*[T](outcome: AccumulationReentryResult[T]): AccumulationBatchResult[
    StateStoreSnapshot] {.inline,

requires: outcome.status == AccumulationReentryError.BatchFailure.} =
  ## Preserve every nested reason from the actually failed private batch application.
  outcome.failed

proc reentryInfo*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    AccumulationReentryInfo] =
  ## Copy cumulative completed offset and next selected range/budget without exposing mutable storage.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[AccumulationReentryInfo](
        status: AccumulationReentryError.Uninitialized) # No fabricated empty/stopped plan.
  AccumulationReentryResult[AccumulationReentryInfo](status: AccumulationReentryError.None,
      completed: data.info)
proc reentrySource*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    CompletedAccumulationContinuation] =
  ## Retain the original completed continuation root in constant time, independently of reentry depth.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[CompletedAccumulationContinuation](
        status: AccumulationReentryError.Uninitialized) # No substitute completion.
  AccumulationReentryResult[CompletedAccumulationContinuation](
      status: AccumulationReentryError.None, completed: data.source)
proc reentryInputs*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    PreparedAccumulationInputs] =
  ## Retain only the newly selected transfer/report groups and their original queue range provenance.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedAccumulationInputs](
        status: AccumulationReentryError.Uninitialized) # No default initialized empty inputs.
  AccumulationReentryResult[PreparedAccumulationInputs](status: AccumulationReentryError.None,
      completed: data.inputs)
proc reentryTransfers*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    PreparedAccumulationTransfers] =
  ## Retain the canonical transfers of the exact just-completed source, independently of this preparation's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedAccumulationTransfers](status:
      AccumulationReentryError.Uninitialized) # A default reentry owns no selected outgoing collection.
  AccumulationReentryResult[PreparedAccumulationTransfers](status:
    AccumulationReentryError.None, completed: data.transfers)
proc reentryState*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    StateStoreSnapshot] =
  ## Retain the actual complete successor after privately applying the just-completed later batch.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[StateStoreSnapshot](
        status: AccumulationReentryError.Uninitialized) # No partial or default map.
  AccumulationReentryResult[StateStoreSnapshot](status: AccumulationReentryError.None,
      completed: data.state)
proc reentryPending*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    PreparedPendingTransfers] =
  ## Retain queued-old/new producer ownership and proven reservation arithmetic for this exact entry.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedPendingTransfers](
        status: AccumulationReentryError.Uninitialized) # No default pending source.
  AccumulationReentryResult[PreparedPendingTransfers](status: AccumulationReentryError.None,
      completed: data.pending)
proc reentryTransferPartition*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    PreparedTransferPartition] =
  ## Retain the exact accepted inputs and held subsequence used for the following carry.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedTransferPartition](
        status: AccumulationReentryError.Uninitialized) # No fabricated input partition.
  AccumulationReentryResult[PreparedTransferPartition](status: AccumulationReentryError.None,
      completed: data.partition)

proc reentryReportAt*(plan: PreparedAccumulationReentry,
    index: ContinuationReportIndex): AccumulationReentryResult[OwnedReport] =
  ## Retain the selected report at its nominal local ordinal; earlier processed reports remain inaccessible here.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[OwnedReport](
        status: AccumulationReentryError.Uninitialized) # No fabricated report.
  if uint64(index) >= uint64(data.info.prefix):
    return AccumulationReentryResult[OwnedReport](
        status: AccumulationReentryError.InvalidIndex) # Check full width before offset addition.
  let position = uint64(data.info.completedPrefix) + uint64(
      index) # Construction proves this is inside the original native queue.
  AccumulationReentryResult[OwnedReport](status: AccumulationReentryError.None,
    completed: data.queue.accumulationAt(AccumulationIndex(position)).value)

proc prepareReentryAccumulationService*(plan: PreparedAccumulationReentry,
    index: InvocationServiceIndex, config: AccumulationServiceConfig): AccumulationReentryResult[
        PreparedAccumulationService] =
  ## Resolve only from this owner's exact transfer/report inputs and actual successor at the authenticated block slot.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedAccumulationService](
        status: AccumulationReentryError.Uninitialized) # No fabricated service source.
  let service = prepareAccumulationService(data.inputs, index, data.state, data.slot, config)
  if service.error != AccumulationServiceError.None:
    return AccumulationReentryResult[PreparedAccumulationService](
      status: AccumulationReentryError.ServiceFailure,
      serviceReason: service.error) # Preserve the actual reason without constructing a foreign private result.
  AccumulationReentryResult[PreparedAccumulationService](status: AccumulationReentryError.None,
      completed: service.value)

proc prepareReentryStep(step: ReentryStep,
    config: AccumulationReentryConfig): AccumulationReentryResult[PreparedAccumulationReentry] =
  ## Select reports with old gas still reserved, apply the actual preceding batch and classify old-before-new pending records.
  template fail(reason: AccumulationReentryError) =
    return AccumulationReentryResult[PreparedAccumulationReentry](status: reason)
  if uint64(step.executions) > uint64(config.selection.executions):
    fail(AccumulationReentryError.LimitExceeded) # Bound even producers with no selected outgoing transfers.
  let batch = step.batch
  let collected = prepareBatchAccumulationTransfers(batch, AccumulationTransferCollectionLimits(
      sources: config.selection.executions, transfers: config.selection.transfers,
      memoBytes: config.selection.memoBytes))
  if collected.error == AccumulationBatchError.LimitExceeded:
    fail(AccumulationReentryError.LimitExceeded) # Canonical source/memo capture is independently bounded.
  if collected.error != AccumulationBatchError.None:
    fail(AccumulationReentryError.InvalidSource) # Only this genuine completion may supply newly emitted values.
  let transfers = collected.value
  let transferCount = transfers.transferCollectionInfo.value.transfers
  let pending = prepareCarriedPendingTransfers(step.previousPartition, transfers, step.budget,
      PendingTransferLimits(sources: config.selection.executions,
          transfers: config.selection.transfers, memoBytes: config.selection.memoBytes))
  if pending.error == PendingTransferError.LimitExceeded:
    fail(AccumulationReentryError.LimitExceeded) # Bound old queued plus new records and their actual producer traversal.
  if pending.error != PendingTransferError.None:
    fail(AccumulationReentryError.InvalidSource) # A valid completed predecessor preserves its old gas reservation.
  let pendingInfo = pending.value.pendingTransferInfo.value
  if uint64(pendingInfo.gasUsed) != uint64(step.gasUsed) or (not step.dispatch and
      pendingInfo.transfers != 0):
    fail(AccumulationReentryError.InvalidSource) # Actual producer use matches the completion; stopped entries cannot restart.
  let initial = step.root.executionContinuation.value.continuationPlan.value.continuationSource.value
  let blockQueue = initial.executionRound.value.roundBlockQueue.value
  let queue = blockQueue.accumulationProjection.value
  let count = queue.accumulationCount.value
  let previous = uint64(step.start)
  if previous > uint64(count) or uint64(step.processed) > uint64(count)-previous:
    fail(AccumulationReentryError.InvalidSource) # Prove cumulative queue offset conversion before addition.
  let start = previous+uint64(step.processed)
  let reportBudget = uint64(pendingInfo.reportBudget)
  let budget = pendingInfo.budget
  var remaining = reportBudget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  if step.dispatch:
    for index in int(start)..<count:
      if reports >= uint64(config.selection.reports): fail(AccumulationReentryError.LimitExceeded)
      inc reports # Inspected rejected reports count too.
      let report = queue.accumulationAt(AccumulationIndex(uint64(index))).value
      let length = ownedReportInfo(report).value.digestCount
      var candidate = remaining
      var fits = true
      for digest in 0..<length:
        if digests >= uint64(config.selection.digests): fail(AccumulationReentryError.LimitExceeded)
        inc digests
        let gas = uint64(ownedReportDigest(report, digest).value.accumulateGas)
        if gas > candidate:
          fits = false
          break # No later report may bypass this unaffordable whole report.
        candidate -= gas
      if not fits: break # Commit neither this report's prefix nor its partial gas reservation.
      remaining = candidate
      inc prefix
  let operands = prepareAccumulationOperandRange(queue, AccumulationReportStart(start),
      AccumulationReportPrefix(prefix), config.operands)
  if operands.error != AccumulationOperandError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.OperandFailure,

operandReason: operands.error) # Bounded selected-range capture precedes private state application.
  let activeInputs = prepareAccumulationInputs(operands.value, [], [], config.inputs)
  if activeInputs.error != AccumulationInputError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InputFailure,

inputReason: activeInputs.error) # Report-only grouping must fit independently of transfer classification.
  let serviceCount = if pendingInfo.transfers == 0: 0 else: activeInputs.value.invocationServiceCount.value
  let transferOverflow = uint64(pendingInfo.transfers) > uint64(config.partition.transfers)
  let serviceOverflow = uint64(serviceCount) > uint64(config.partition.services)
  let workOverflow = uint64(pendingInfo.transfers) > uint64(config.partition.checks)
  let extentOverflow = serviceCount > high(int) div sizeof(ServiceIndex)
  if transferOverflow or serviceOverflow or workOverflow or extentOverflow:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.PartitionFailure,

partitionReason: TransferPartitionError.LimitExceeded) # Bound obvious source/minimum work before state hashing.
  var active = newSeq[ServiceIndex](serviceCount)
  for index in 0..<serviceCount:
    active[index] = activeInputs.value.invocationServiceAt(InvocationServiceIndex(uint64(
        index))).value.service # No always allowance recurs in accseq.
  var working = forkStateStore(step.prior).value
  let applied = applyAccumulationBatch(working, batch)
  if applied.error != AccumulationBatchError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.BatchFailure,

failed: applied) # Refusal discards the entire private successor.
  let partition = pending.value.partitionPendingTransfers(applied.value, active, config.partition)
  if partition.error == PendingTransferError.PartitionFailure:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.PartitionFailure,

partitionReason: partition.partitionError) # Actual post-state metadata and work refusals remain visible.
  if partition.error != PendingTransferError.None:
    fail(AccumulationReentryError.InvalidSource) # A genuine pending owner always reaches the kernel.
  let accepted = partition.value.partitionCount(TransferPartitionKind.Accepted).value
  if uint64(accepted) > uint64(config.inputs.inputs):
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InputFailure,

inputReason: AccumulationInputError.LimitExceeded) # Bound accepted descriptors before copying them.
  var values = newSeq[DeferredTransfer](accepted)
  for index in 0..<accepted:
    values[index] = partition.value.partitionTransferAt(TransferPartitionKind.Accepted,
        TransferPartitionIndex(uint64(index))).value # Stable accepted order precedes destination grouping.
  let inputs = prepareAccumulationInputs(operands.value, values, [], config.inputs)
  if inputs.error != AccumulationInputError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InputFailure,

inputReason: inputs.error) # Queued records do not become invocation descriptors in this entry.
  let stage = blockQueue.accumulationAdmission.value.reportBlockStage.value.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  AccumulationReentryResult[PreparedAccumulationReentry](status: AccumulationReentryError.None,
      completed: PreparedAccumulationReentry(data: ReentryData(source: step.root,
          previous: step.previous, queue: queue,
          info: AccumulationReentryInfo(depth: step.depth,
              completedPrefix: AccumulationReportPrefix(start), pendingReports: count-int(start),
                  prefix: AccumulationReportPrefix(prefix), budget: budget,
              transfers: transferCount, transferGas: pendingInfo.outgoingGas,
              reportGas: Gas(reportBudget-remaining), dispatch: prefix != 0 or accepted != 0),
          inputs: inputs.value, transfers: transfers, pending: pending.value,
              partition: partition.value,
          state: applied.value, slot: slot)))

proc reentryPrevious*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    CompletedAccumulationReentry] =
  ## Retain only the immediate genuine predecessor; first entry reports NoPrevious rather than fabricating a completion.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[CompletedAccumulationReentry](
        status: AccumulationReentryError.Uninitialized) # Defaults supply no history.
  if data.previous == nil:
    return AccumulationReentryResult[CompletedAccumulationReentry](
        status: AccumulationReentryError.NoPrevious) # The original continuation remains available through reentrySource.
  AccumulationReentryResult[CompletedAccumulationReentry](status: AccumulationReentryError.None,
    completed: CompletedAccumulationReentry(data: data.previous))

proc prepareAccumulationReentry*(source: CompletedAccumulationContinuation,
    config: AccumulationReentryConfig): AccumulationReentryResult[PreparedAccumulationReentry] =
  ## Prepare the first reentry from a genuine completed continuation, preserving the existing bounded contract.
  let completed = source.executionInfo
  if completed.error != AccumulationContinuationExecutionError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InvalidSource) # No default completion authorizes first entry.
  let facts = completed.value
  prepareReentryStep(ReentryStep(root: source, previous: nil,
    previousPartition: source.executionContinuation.value.continuationTransferPartition.value,
    prior: source.executionContinuation.value.continuationState.value,
    batch: source.executionBatch.value,
    start: facts.round.completedPrefix, processed: facts.round.prefix, budget: facts.round.budget,
    gasUsed: facts.gasUsed, executions: facts.batch.executions, dispatch: facts.round.dispatch,
    depth: AccumulationReentryDepth(1)), config)

func error*[T](outcome: AccumulationReentryExecutionResult[
    T]): AccumulationReentryExecutionError =
  ## Inspect the selected reason without allowing retagging.
  outcome.status

func value*[T](outcome: AccumulationReentryExecutionResult[T]): T {.inline,
    requires: outcome.status == AccumulationReentryExecutionError.None.} =
  ## Extract selected success under checked optimized contracts.
  outcome.completed

func batchFailure*[T](outcome: AccumulationReentryExecutionResult[T]):
    AccumulationBatchResult[PreparedAccumulationBatch] {.inline,
    requires: outcome.status == AccumulationReentryExecutionError.BatchFailure.} =
  ## Inspect the actual refused parent result; its existing nested reason contracts remain enforced.
  outcome.failed

# Canonical gas sequence ordering is numeric service order, independent of caller execution order.
func compareUsage(left, right: AccumulationGasUsage): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc executionInfo*(plan: CompletedAccumulationReentry):
    AccumulationReentryExecutionResult[AccumulationReentryExecutionInfo] =
  ## Copy actual usage and declared round reservations without exposing the owned row sequence.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationReentryExecutionResult[AccumulationReentryExecutionInfo](
        status: AccumulationReentryExecutionError.Uninitialized)
  AccumulationReentryExecutionResult[AccumulationReentryExecutionInfo](
    status: AccumulationReentryExecutionError.None,
    completed: AccumulationReentryExecutionInfo(
      round: data.source.reentryInfo.value,
      batch: data.batch.batchInfo.value, services: data.usage.len, gasUsed: data.gasUsed))

proc executionGasAt*(plan: CompletedAccumulationReentry, index: InvocationServiceIndex):
    AccumulationReentryExecutionResult[AccumulationGasUsage] =
  ## Copy the gas row at this round's sorted input-service ordinal; full-width invalid indices refuse before narrowing.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationReentryExecutionResult[AccumulationGasUsage](
        status: AccumulationReentryExecutionError.Uninitialized)
  if uint64(index) >= uint64(data.usage.len):
    return AccumulationReentryExecutionResult[AccumulationGasUsage](
        status: AccumulationReentryExecutionError.InvalidIndex)
  AccumulationReentryExecutionResult[AccumulationGasUsage](
    status: AccumulationReentryExecutionError.None,
    completed: data.usage[int(uint64(index))])

proc executionReentry*(plan: CompletedAccumulationReentry):
    AccumulationReentryExecutionResult[PreparedAccumulationReentry] =
  ## Retain the exact prepared inputs and posterior state independently of this completion's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationReentryExecutionResult[PreparedAccumulationReentry](
      status: AccumulationReentryExecutionError.Uninitialized) # No fabricated reentry source.
  AccumulationReentryExecutionResult[PreparedAccumulationReentry](
    status: AccumulationReentryExecutionError.None, completed: data.source)

proc executionBatch*(plan: CompletedAccumulationReentry):
    AccumulationReentryExecutionResult[PreparedAccumulationBatch] =
  ## Retain the complete batch for existing atomic publication against its exact reentry posterior snapshot.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationReentryExecutionResult[PreparedAccumulationBatch](
        status: AccumulationReentryExecutionError.Uninitialized)
  AccumulationReentryExecutionResult[PreparedAccumulationBatch](
    status: AccumulationReentryExecutionError.None,
    completed: data.batch)

proc completeAccumulationReentry*(source: PreparedAccumulationReentry,
    executions: openArray[AccumulationDispatchResult], skipped: openArray[SkippedAccumulation],
    limits: AccumulationExecutionLimits): AccumulationReentryExecutionResult[
        CompletedAccumulationReentry] =
  ## Bind complete coverage and actual gas to the round's exact inputs, actual posterior state, slot and posterior entropy.
  ## Borrowed arrays remain stable during the call; terminal selection/union preparation occurs once in the batch adapter.
  # Refuse without publishing an earlier batch or a partial gas sequence.
  template fail(reason: AccumulationReentryExecutionError) =
    return AccumulationReentryExecutionResult[CompletedAccumulationReentry](status: reason)
  let selected = source.reentryInfo
  if selected.error != AccumulationReentryError.None:
    fail(AccumulationReentryExecutionError.InvalidInputs) # Defaults cannot authorize a completed later round.
  let facts = selected.value
  let inputs = source.reentryInputs.value
  let count = inputs.invocationServiceCount.value
  if uint64(count) > uint64(limits.services) or count > high(int) div sizeof(AccumulationGasUsage):
    fail(AccumulationReentryExecutionError.LimitExceeded) # Bound complete gas rows before batch hashing/allocation.
  let round = source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value.executionRound.value
  let stage = round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let parent = source.reentryState.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  if executions.len > 0 and executions.len <= count:
    # Prove the bootstrap seed against posterior C(6), not caller-supplied or admitted-parent entropy.
    # Count bounds cap this preflight; invalid dispatches are left for the batch adapter's typed refusal.
    let found = stage.snapshot.lookup(chapterKey(StateChapter(6)))
    if found.error != StateStoreError.None:
      fail(AccumulationReentryExecutionError.InvalidEntropy)
    if found.value.byteLength != 128:
      fail(AccumulationReentryExecutionError.InvalidEntropy)
    let entropy = decodeStateEntropy(found.value.bytes)
    if entropy.error != StateComponentError.None:
      fail(AccumulationReentryExecutionError.InvalidEntropy)
    let expected = array[32, byte](entropy.value.value[0])
    for execution in executions:
      if execution.error == AccumulationDispatchError.None:
        let source = execution.effects.effectsSource.value.initialContext(
            AccumulationDimension.Regular).value
        let invocation = source.contextInvocation.value.bootstrapInfo.value
        if array[32, byte](invocation.entropy) != expected:
          fail(AccumulationReentryExecutionError.EntropyMismatch) # Refuse before any provision union hashing.
  let batch = prepareCompleteAccumulationBatch(inputs, parent, executions, skipped, slot, limits.batch)
  if batch.error != AccumulationBatchError.None:
    return AccumulationReentryExecutionResult[CompletedAccumulationReentry](
      status: AccumulationReentryExecutionError.BatchFailure,
      failed: batch) # Only a failed parent result is retained, preserving all nested reason alternatives.
  let budget = uint64(facts.budget)
  var total = 0'u64
  var usage = newSeq[AccumulationGasUsage](count)
  for index in 0..<executions.len:
    # Normalized actual consumption includes gas spent before a rolled-back checkpoint or panic.
    let info = batch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(
        index))).value.outcomeInfo.value
    let consumed = uint64(info.gasUsed)
    if consumed > budget - total:
      fail(AccumulationReentryExecutionError.GasExceeded) # Subtraction proves both budget compliance and sum representability.
    total += consumed
    usage[index] = AccumulationGasUsage(service: info.service, gasUsed: info.gasUsed)
  for index, outcome in skipped:
    # The complete batch already verified each genuine skip's owner, slot, membership and uniqueness.
    usage[executions.len + index] = AccumulationGasUsage(service: outcome.skipInfo.value.service,
        gasUsed: Gas(0))
  usage.sort(compareUsage)
  AccumulationReentryExecutionResult[CompletedAccumulationReentry](
    status: AccumulationReentryExecutionError.None,
    completed: CompletedAccumulationReentry(data: ReentryExecutionData(source: source,
      batch: batch.value,
      usage: usage, gasUsed: Gas(total))))

proc prepareAccumulationReentry*(source: CompletedAccumulationReentry,
    config: AccumulationReentryConfig, depth: AccumulationReentryDepthLimit): AccumulationReentryResult[
        PreparedAccumulationReentry] =
  ## Advance only a genuine dispatched completion, under an explicit maximum retained depth; apply only its batch privately.
  ## Source, queue, budget and prior map cannot be replaced; no caller store is published on success or refusal.
  let data = source.data
  if data == nil:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InvalidSource) # No fabricated completion enters the shared step.
  let current = data.source.data
  if current == nil:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.InvalidSource) # Defensive owner invariant, never a default successful source.
  if not current.info.dispatch:
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.Stopped) # n=0 is terminal; no history or suffix rescan occurs.
  if uint64(current.info.depth) >= uint64(depth):
    return AccumulationReentryResult[PreparedAccumulationReentry](
        status: AccumulationReentryError.LimitExceeded) # Prove increment representability and cap compliance before any step work.
  prepareReentryStep(ReentryStep(root: current.source, previous: data,
    previousPartition: current.partition, prior: current.state,
    batch: data.batch, start: current.info.completedPrefix, processed: current.info.prefix,
    budget: current.info.budget, gasUsed: data.gasUsed,
    executions: data.batch.batchInfo.value.executions,
    dispatch: current.info.dispatch, depth: AccumulationReentryDepth(uint64(current.info.depth)+1)), config)
