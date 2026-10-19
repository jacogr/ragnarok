# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Select and materialize report-only accseq reentry after a completed continuation, then apply its batch privately.
## Retains immutable original-queue provenance and actual full-map successor without publishing caller state.

import ../codec/[bounded, composite, header, work_digest, report_owned]
import ./[accumulation_continuation_execution, accumulation_continuation_inputs,
  accumulation_continuation, accumulation_execution, accumulation_round, accumulation_queue,
  accumulation_operands, accumulation_inputs, accumulation_batch, accumulation_outcome,
  accumulation_provisions, accumulation_service, report_admission, block_transition,
  block_admission, store]

type
  AccumulationReentryConfig* = object ## Selection work and input materialization have independent local ceilings.
    selection*: AccumulationContinuationLimits ## Inspected outcomes/reports/digests, including rejected reports.
    operands*: AccumulationOperandConfig ## Only newly selected report payloads count toward these limits.
    inputs*: AccumulationInputConfig ## Only report-derived groups; no recurring allowances or transfers.
  AccumulationReentryInfo* = object ## Copied next-entry facts retain cumulative progress without claiming later execution or final publication.
    completedPrefix*: AccumulationReportPrefix ## Total original reports processed by initial and completed later rounds.
    pendingReports*: int ## Original-queue reports remaining before this new selection.
    prefix*: AccumulationReportPrefix ## Newly selected whole reports after the cumulative completed offset.
    budget*: Gas         ## Retained recursive input budget minus verified actual gas of the just-completed round.
    reportGas*: Gas      ## Declared digest gas reserved by this newly selected report range.
    dispatch*: bool      ## True exactly when reentry selects reports; stopped sources cannot restart.
  AccumulationReentryError* {.pure.} = enum ## Refusals expose no earlier range, source, inputs or state candidate.
    Uninitialized,        ## Default result or preparation handle.
    None,                 ## Complete selected success permits guarded extraction.
    InvalidSource,        ## No genuine completed continuation or valid range/gas provenance.
    InvalidIndex,         ## Full-width selected-report ordinal is outside the retained range.
    LimitExceeded,        ## Independent selection inspection budget exhausted.
    UnsupportedTransfers, ## Outgoing transfers need transfer-aware recursion first.
    OperandFailure,       ## Inspect the selected range materialization reason.
    InputFailure,         ## Inspect the report-only service grouping reason.
    ServiceFailure,       ## Inspect the actual retained-state service resolution reason.
    BatchFailure          ## Inspect the actual failed private batch application's nested reasons.
  # Acyclic immutable storage retains exact completed source, original queue and complete prepared successor.
  ReentryData = ref object
    source: CompletedAccumulationContinuation
    queue: AccumulationQueuePlan
    info: AccumulationReentryInfo
    inputs: PreparedAccumulationInputs
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
    of BatchFailure:
      failed: AccumulationBatchResult[StateStoreSnapshot] # Invariant: genuinely failed, so no successful snapshot exists.
    else:
      discard      # Defaults, bounds, transfer and invalid-source reasons carry no payload.

func error*[T](outcome: AccumulationReentryResult[T]): AccumulationReentryError =
  ## Read the selected reason without permitting retagging.
  outcome.status
func value*[T](outcome: AccumulationReentryResult[T]): T {.inline,
    requires: outcome.status == AccumulationReentryError.None.} =
  ## Retain complete selected success only.
  outcome.completed
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
  ## Retain the exact completed later round independently of this preparation handle.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[CompletedAccumulationContinuation](
        status: AccumulationReentryError.Uninitialized) # No substitute completion.
  AccumulationReentryResult[CompletedAccumulationContinuation](
      status: AccumulationReentryError.None, completed: data.source)
proc reentryInputs*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    PreparedAccumulationInputs] =
  ## Retain only the newly selected report-only groups and their original queue range provenance.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[PreparedAccumulationInputs](
        status: AccumulationReentryError.Uninitialized) # No default initialized empty inputs.
  AccumulationReentryResult[PreparedAccumulationInputs](status: AccumulationReentryError.None,
      completed: data.inputs)
proc reentryState*(plan: PreparedAccumulationReentry): AccumulationReentryResult[
    StateStoreSnapshot] =
  ## Retain the actual complete successor after privately applying the just-completed later batch.
  let data = plan.data
  if data == nil:
    return AccumulationReentryResult[StateStoreSnapshot](
        status: AccumulationReentryError.Uninitialized) # No partial or default map.
  AccumulationReentryResult[StateStoreSnapshot](status: AccumulationReentryError.None,
      completed: data.state)
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
  ## Resolve only from this owner's exact report inputs and actual successor at the authenticated block slot.
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

proc prepareAccumulationReentry*(source: CompletedAccumulationContinuation,
    config: AccumulationReentryConfig): AccumulationReentryResult[PreparedAccumulationReentry] =
  ## Advance the original report range using actual gas, preflight report-only inputs, then apply only this completed batch privately.
  ## Borrow source during preparation and retain it only on complete success; caller state is never published.
  template fail(reason: AccumulationReentryError) =
    return AccumulationReentryResult[PreparedAccumulationReentry](status: reason)
  let completed = source.executionInfo
  if completed.error != AccumulationContinuationExecutionError.None:
    fail(AccumulationReentryError.InvalidSource) # Default completions cannot authorize reentry.
  let facts = completed.value
  if uint64(facts.batch.executions) > uint64(config.selection.executions):
    fail(AccumulationReentryError.LimitExceeded) # Bound even outcomes with no outgoing transfers.
  let batch = source.executionBatch.value
  for index in 0..<facts.batch.executions:
    let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    if outcome.outcomeInfo.value.transfers != 0:
      fail(AccumulationReentryError.UnsupportedTransfers) # Never discard outgoing destination/gas contributions.
  let context = source.executionContinuation.value
  let initial = context.continuationPlan.value.continuationSource.value
  let blockQueue = initial.executionRound.value.roundBlockQueue.value
  let queue = blockQueue.accumulationProjection.value
  let count = queue.accumulationCount.value
  let previous = uint64(facts.round.completedPrefix)
  if previous > uint64(count) or uint64(facts.round.prefix) > uint64(count) - previous or
      uint64(facts.gasUsed) > uint64(facts.round.budget):
    fail(AccumulationReentryError.InvalidSource) # Prove addition, native conversion and gas subtraction first.
  let start = previous + uint64(facts.round.prefix)
  let budget = uint64(facts.round.budget) - uint64(facts.gasUsed)
  var remaining = budget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  if facts.round.dispatch:
    for index in int(start)..<count:
      # n=0 is terminal in accseq; only an actually dispatched source can authorize further traversal.
      if reports >= uint64(config.selection.reports): fail(AccumulationReentryError.LimitExceeded)
      inc reports
      let report = queue.accumulationAt(AccumulationIndex(uint64(index))).value
      let length = ownedReportInfo(report).value.digestCount
      var candidate = remaining
      var fits = true
      for digest in 0..<length:
        # Every inspected digest consumes work, even when its report later fails affordability.
        if digests >= uint64(config.selection.digests): fail(AccumulationReentryError.LimitExceeded)
        inc digests
        let gas = uint64(ownedReportDigest(report, digest).value.accumulateGas)
        if gas > candidate:
          fits = false
          break # Neither earlier digest reservations nor later cheaper reports may bypass this report.
        candidate -= gas
      if not fits: break # Commit none of the rejected whole report.
      remaining = candidate
      inc prefix # Bounded by the original native queue length.
  let operands = prepareAccumulationOperandRange(queue, AccumulationReportStart(start),
    AccumulationReportPrefix(prefix), config.operands)
  if operands.error != AccumulationOperandError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
      status: AccumulationReentryError.OperandFailure,
      operandReason: operands.error) # No partial projection or state candidate survives refusal.
  let inputs = prepareAccumulationInputs(operands.value, [], [], config.inputs)
  if inputs.error != AccumulationInputError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
      status: AccumulationReentryError.InputFailure,
      inputReason: inputs.error) # No recurring free allowance or implicit transfer group is introduced.
  var working = forkStateStore(context.continuationState.value).value
  let applied = applyAccumulationBatch(working, batch)
  if applied.error != AccumulationBatchError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
      status: AccumulationReentryError.BatchFailure,
      failed: applied) # Retain only a genuinely failed parent; release private inputs/state candidates.
  let stage = blockQueue.accumulationAdmission.value.reportBlockStage.value.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  AccumulationReentryResult[PreparedAccumulationReentry](status: AccumulationReentryError.None,
    completed: PreparedAccumulationReentry(data: ReentryData(source: source, queue: queue,
      info: AccumulationReentryInfo(completedPrefix: AccumulationReportPrefix(start),
        pendingReports: count-int(start), prefix: AccumulationReportPrefix(prefix), budget: Gas(
            budget),
        reportGas: Gas(budget-remaining), dispatch: prefix != 0),
      inputs: inputs.value, state: applied.value, slot: slot)))
