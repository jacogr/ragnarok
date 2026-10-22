# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated current accumulation sequence ownership and bounded continuation input planning.
## Flat per-entry facts avoid recursive certificate ownership; selected successor state governs pending partitioning.
import ../codec/[bounded, composite, work_digest, report_owned, c2_records]
import ./[accumulation_current_round, accumulation_block_guests, accumulation_round,
  accumulation_queue, accumulation_coverage, accumulation_global_stage, accumulation_global_phase,
  accumulation_annulled_outputs, accumulation_pending_transfers, accumulation_transfer_partition,
  accumulation_operands, accumulation_inputs, store]

type
  CurrentSequenceEntryIndex* = distinct uint64 ## A historical sequence entry cannot substitute an input service or report ordinal.
  CurrentPlanReportIndex* = distinct uint64 ## A selected next-report ordinal belongs only to its own continuation plan.
  CurrentContinuationLimits* = object ## Queue inspection, report materialization, grouping and partition work retain independent local ceilings.
    reports*, digests*: ElementLimit
    operands*: AccumulationOperandConfig
    inputs*: AccumulationInputConfig
    partition*: TransferPartitionLimits
  CurrentSequenceInfo* = object ## Latest budget/progress observations are separate from terminal whole-block publication.
    entries*, pending*: int
    processedReports*: AccumulationReportPrefix
    budget*: Gas
  CurrentContinuationInfo* = object ## Whole selected reports and accepted transfers alone create next guest inputs; initial free allowances never recur.
    start*: AccumulationReportStart
    prefix*: AccumulationReportPrefix
    pendingReports*, accepted*, queued*, services*: int
    budget*, reportGas*: Gas
    dispatch*: bool
  CurrentSequenceError* {.pure.} = enum ## No refusal exposes a selected report prefix or partial invocation inputs.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded,
    OperandFailure, InputFailure, PartitionFailure
  SequenceFact = object # Every fixed row retains genuine entry proofs without retaining a predecessor sequence owner.
    coverage: PreparedAccumulationCoverage
    globals: PreparedAccumulationGlobalPhase
    outputs: PreparedAnnulmentOutputs
    pending: PreparedPendingTransfers
    processed: AccumulationReportPrefix
  SequenceData = ref object # Immutable flat history shares only acyclic proof/state graphs, not a linked chain of sequence certificates.
    initial: PreparedCurrentAccumulationRound
    facts: seq[SequenceFact]
  CurrentAccumulationSequence* = object ## Only genuine current completion and later checked execution can construct sequence ownership.
    data: nil SequenceData
  CurrentPlanData = ref object # An immutable plan binds exact source history, original queue, selected inputs and transfer classification.
    source: CurrentAccumulationSequence
    queue: AccumulationQueuePlan
    inputs: PreparedAccumulationInputs
    partition: PreparedTransferPartition
    info: CurrentContinuationInfo
  PreparedCurrentContinuation* = object ## Only affordable original-queue suffix selection and current-state partitioning constructs this plan.
    data: nil CurrentPlanData
  CurrentSequenceResult*[T] = object ## Private successful owners and actual child refusals occupy disjoint alternatives.
    case status: CurrentSequenceError
    of None:
      completed: T
    of OperandFailure:
      operandReason: AccumulationOperandError
    of InputFailure:
      inputReason: AccumulationInputError
    of PartitionFailure:
      partitionReason: TransferPartitionError
    else:
      discard # Defaults and extent/source/index refusals grant no initialized plan or sequence.

func error*[T](outcome: CurrentSequenceResult[T]): CurrentSequenceError =
  ## Inspect only the selected reason without granting mutation.
  outcome.status
func value*[T](outcome: CurrentSequenceResult[T]): T {.inline,
    requires: outcome.status == CurrentSequenceError.None.} =
  ## Extract complete source-bound ownership only after success.
  outcome.completed
func operandFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationOperandError {.inline,
    requires: outcome.status == CurrentSequenceError.OperandFailure.} =
  ## Preserve the actual selected-range capture refusal.
  outcome.operandReason
func inputFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationInputError {.inline,
    requires: outcome.status == CurrentSequenceError.InputFailure.} =
  ## Preserve the actual report-only/final grouping refusal.
  outcome.inputReason
func partitionFailure*[T](outcome: CurrentSequenceResult[T]): TransferPartitionError {.inline,
    requires: outcome.status == CurrentSequenceError.PartitionFailure.} =
  ## Preserve the actual selected-state transfer classification refusal.
  outcome.partitionReason
proc startCurrentAccumulationSequence*(initial: PreparedCurrentAccumulationRound): CurrentSequenceResult[
    CurrentAccumulationSequence] =
  ## Capture exactly one completed authenticated initial round; pure/default phase owners cannot provide an anchor.
  let guests = initial.currentRoundGuests
  if guests.error != CurrentAccumulationRoundError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.InvalidSource)
  let processed = guests.value.guestRound.value.roundProjection.value.roundInfo.value.prefix
  let globals = initial.currentRoundGlobals.value.globalStagePhase.value
  let first = SequenceFact(coverage: guests.value.guestCoverage.value, globals: globals,
    outputs: initial.currentRoundOutputs.value, pending: initial.currentRoundPending.value,
    processed: processed)
  CurrentSequenceResult[CurrentAccumulationSequence](status: CurrentSequenceError.None,
    completed: CurrentAccumulationSequence(data: SequenceData(initial: initial, facts: @[first])))
proc currentSequenceInfo*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    CurrentSequenceInfo] =
  ## Copy latest progress/budget without allowing a caller to replace historical rows or their source proofs.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[CurrentSequenceInfo](status: CurrentSequenceError.Uninitialized)
  let latest = data.facts[data.facts.len-1] # Private constructors retain at least one completely prepared entry.
  let pending = latest.pending.pendingTransferInfo.value
  CurrentSequenceResult[CurrentSequenceInfo](status: CurrentSequenceError.None,
    completed: CurrentSequenceInfo(entries: data.facts.len, pending: pending.transfers,
      processedReports: latest.processed, budget: pending.budget))
proc currentSequenceInitial*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    PreparedCurrentAccumulationRound] =
  ## Retain the genuine initial block/guest anchor independently of the caller's original handle lifetime.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedCurrentAccumulationRound](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedCurrentAccumulationRound](status: CurrentSequenceError.None,
      completed: data.initial)
proc planCurrentAccumulationContinuation*(sequence: CurrentAccumulationSequence,
    limits: CurrentContinuationLimits): CurrentSequenceResult[PreparedCurrentContinuation] =
  ## Select the next affordable whole reports, partition pending transfers against latest selected state, and group only accepted inputs without free allowances.
  template fail(reason: CurrentSequenceError) =
    return CurrentSequenceResult[PreparedCurrentContinuation](status: reason)
  let data = sequence.data
  if data == nil:
    fail(CurrentSequenceError.InvalidSource) # No default/partial history can supply an admitted queue or private successor state.
  let latest = data.facts[data.facts.len-1]
  let round = data.initial.currentRoundGuests.value.guestRound.value
  let queue = round.roundBlockQueue.value.accumulationProjection.value
  let count = queue.accumulationCount.value
  let start = uint64(latest.processed)
  if start > uint64(count):
    fail(CurrentSequenceError.InvalidSource) # Prove source-owned suffix conversion before indexing or subtracting its length.
  let pendingInfo = latest.pending.pendingTransferInfo.value
  let reportBudget = uint64(pendingInfo.reportBudget)
  var remaining = reportBudget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  for ordinal in int(start)..<count:
    if reports >= uint64(limits.reports):
      fail(CurrentSequenceError.LimitExceeded) # Charge the first rejected report too, before retrieving it.
    inc reports
    let report = queue.accumulationAt(AccumulationIndex(uint64(ordinal))).value
    let length = ownedReportInfo(report).value.digestCount
    var candidate = remaining
    var fits = true
    for digest in 0..<length:
      if digests >= uint64(limits.digests):
        fail(CurrentSequenceError.LimitExceeded) # Every inspected gas word consumes explicit work, including an unaffordable suffix.
      inc digests
      let gas = uint64(ownedReportDigest(report, digest).value.accumulateGas)
      if gas > candidate:
        fits = false
        break # No later report bypasses an unaffordable whole report.
      candidate -= gas # Proven subtraction prevents mathematical gas sums from wrapping.
    if not fits: break # Discard every tentative reservation in the rejected report.
    remaining = candidate
    inc prefix # The bounded original queue suffix proves this increment and later range.
  let operands = prepareAccumulationOperandRange(queue, AccumulationReportStart(start),
    AccumulationReportPrefix(prefix), limits.operands)
  if operands.error != AccumulationOperandError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.OperandFailure, operandReason: operands.error)
  let activeInputs = prepareAccumulationInputs(operands.value, [], [], limits.inputs)
  if activeInputs.error != AccumulationInputError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure, inputReason: activeInputs.error)
  let serviceCount = if pendingInfo.transfers == 0: 0 else: activeInputs.value.invocationServiceCount.value
  if uint64(pendingInfo.transfers) > uint64(limits.partition.transfers) or
      uint64(pendingInfo.transfers) > uint64(limits.partition.checks) or
      uint64(serviceCount) > uint64(limits.partition.services) or serviceCount > high(
          int) div sizeof(ServiceIndex):
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.PartitionFailure,
        partitionReason: TransferPartitionError.LimitExceeded) # Bound pending capture, minimum predicates and active allocation before work.
  var active = newSeq[ServiceIndex](serviceCount)
  for ordinal in 0..<serviceCount:
    active[ordinal] = activeInputs.value.invocationServiceAt(InvocationServiceIndex(uint64(
        ordinal))).value.service # Report services alone are active before transfer credit partitioning.
  let state = latest.globals.globalPhaseSnapshot.value
  let partition = latest.pending.partitionPendingTransfers(state, active, limits.partition)
  if partition.error == PendingTransferError.PartitionFailure:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.PartitionFailure,
        partitionReason: partition.partitionError) # Preserve the actual nested classification refusal.
  if partition.error != PendingTransferError.None:
    fail(CurrentSequenceError.InvalidSource) # Only initialized source-owned pending records may authorize classification.
  let accepted = partition.value.partitionCount(TransferPartitionKind.Accepted).value
  if uint64(accepted) > uint64(limits.inputs.inputs) or accepted > high(int) div sizeof(DeferredTransfer):
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure,
        inputReason: AccumulationInputError.LimitExceeded) # Bound every accepted record before temporary capture.
  var transfers = newSeq[DeferredTransfer](accepted)
  for ordinal in 0..<accepted:
    transfers[ordinal] = partition.value.partitionTransferAt(TransferPartitionKind.Accepted,
      TransferPartitionIndex(uint64(ordinal))).value # Preserve stable accepted order before destination grouping.
  let inputs = prepareAccumulationInputs(operands.value, transfers, [], limits.inputs)
  if inputs.error != AccumulationInputError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure, inputReason: inputs.error)
  let info = CurrentContinuationInfo(start: AccumulationReportStart(start),
      prefix: AccumulationReportPrefix(prefix),
    pendingReports: count-int(start), accepted: accepted,
    queued: partition.value.partitionCount(TransferPartitionKind.Queued).value,
    services: inputs.value.invocationServiceCount.value, budget: pendingInfo.budget,
    reportGas: Gas(reportBudget-remaining), dispatch: prefix != 0 or pendingInfo.transfers != 0)
  CurrentSequenceResult[PreparedCurrentContinuation](status: CurrentSequenceError.None,
    completed: PreparedCurrentContinuation(data: CurrentPlanData(source: sequence, queue: queue,
      inputs: inputs.value, partition: partition.value, info: info)))

proc currentSequenceCoverageAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[PreparedAccumulationCoverage] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedAccumulationCoverage](
        status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[PreparedAccumulationCoverage](
        status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[PreparedAccumulationCoverage](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].coverage)

proc currentSequenceOutputsAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[PreparedAnnulmentOutputs] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedAnnulmentOutputs](
        status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[PreparedAnnulmentOutputs](
        status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[PreparedAnnulmentOutputs](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].outputs)

proc currentSequenceStateAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[StateStoreSnapshot] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].globals.globalPhaseSnapshot.value)

proc currentSequenceLatestState*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    StateStoreSnapshot] =
  ## Retain the complete latest projection, never a fabricated default/empty sequence.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.facts[data.facts.len-1].globals.globalPhaseSnapshot.value)

proc currentSequencePending*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    PreparedPendingTransfers] =
  ## Retain the complete latest projection, never a fabricated default/empty sequence.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedPendingTransfers](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedPendingTransfers](status: CurrentSequenceError.None,
      completed: data.facts[data.facts.len-1].pending)

proc currentContinuationInfo*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    CurrentContinuationInfo] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[CurrentContinuationInfo](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[CurrentContinuationInfo](status: CurrentSequenceError.None,
      completed: data.info)

proc currentContinuationSource*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    CurrentAccumulationSequence] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[CurrentAccumulationSequence](status: CurrentSequenceError.None,
      completed: data.source)

proc currentContinuationInputs*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    PreparedAccumulationInputs] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[PreparedAccumulationInputs](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedAccumulationInputs](status: CurrentSequenceError.None,
      completed: data.inputs)

proc currentContinuationPartition*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    PreparedTransferPartition] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[PreparedTransferPartition](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedTransferPartition](status: CurrentSequenceError.None,
      completed: data.partition)

proc currentContinuationState*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    StateStoreSnapshot] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.source.currentSequenceLatestState.value)

proc currentContinuationReportAt*(plan: PreparedCurrentContinuation,
    index: CurrentPlanReportIndex): CurrentSequenceResult[OwnedReport] =
  ## Address only this plan's selected original-queue suffix, with upper bits checked before conversion/addition.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.info.prefix):
    return CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.InvalidIndex)
  let absolute = uint64(data.info.start)+uint64(index) # Factory bounds the complete selected range by the genuine native queue count.
  CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.None,
      completed: data.queue.accumulationAt(AccumulationIndex(absolute)).value)
