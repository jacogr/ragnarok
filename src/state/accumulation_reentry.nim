# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Own preparation and completion of bounded report-only accseq reentries, applying only the just-completed batch privately.
## Retains immutable original-queue provenance and actual full-map successor without publishing caller state.

import std/algorithm
import ../codec/[bounded, composite, header, work_digest, report_owned, state_safrole, state_layout, state_trie]
import ./[accumulation_continuation_execution, accumulation_continuation_inputs,
  accumulation_continuation, accumulation_execution, accumulation_round, accumulation_queue,
  accumulation_operands, accumulation_inputs, accumulation_batch, accumulation_outcome,
  accumulation_provisions, accumulation_service, report_admission, block_transition,
  block_admission, accumulation_dispatch, accumulation_skip, accumulation_effects,
  accumulation_context, accumulation_invocation, store]

type
  AccumulationReentryDepth* = distinct uint64 ## Retained reentry ordinal starts at one and is distinct from report counts or gas.
  AccumulationReentryDepthLimit* = distinct uint64 ## Explicit maximum retained history depth for repeated advance.
  AccumulationReentryConfig* = object ## Selection work and input materialization have independent local ceilings.
    selection*: AccumulationContinuationLimits ## Inspected outcomes/reports/digests, including rejected reports.
    operands*: AccumulationOperandConfig ## Only newly selected report payloads count toward these limits.
    inputs*: AccumulationInputConfig ## Only report-derived groups; no recurring allowances or transfers.
  AccumulationReentryInfo* = object ## Copied next-entry facts retain cumulative progress without claiming later execution or final publication.
    depth*: AccumulationReentryDepth ## First reentry is one; repeated advance increments only below its explicit cap.
    completedPrefix*: AccumulationReportPrefix ## Total original reports processed by initial and completed later rounds.
    pendingReports*: int ## Original-queue reports remaining before this new selection.
    prefix*: AccumulationReportPrefix ## Newly selected whole reports after the cumulative completed offset.
    budget*: Gas         ## Retained recursive input budget minus verified actual gas of the just-completed round.
    reportGas*: Gas      ## Declared digest gas reserved by this newly selected report range.
    dispatch*: bool      ## True exactly when reentry selects reports; stopped sources cannot restart.
  AccumulationReentryError* {.pure.} = enum ## Refusals expose no earlier range, source, inputs or state candidate.
    Uninitialized,        ## Default result or preparation handle.
    None,                 ## Complete selected success permits guarded extraction.
    NoPrevious,           ## First reentry has only the original continuation root, no prior completed reentry.
    Stopped,              ## A completed n=0 entry cannot authorize another advance.
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
    previous: nil ReentryExecutionData
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

proc prepareReentryStep(step: ReentryStep,
    config: AccumulationReentryConfig): AccumulationReentryResult[PreparedAccumulationReentry] =
  # Share bounded selection/materialization and exact-prior application for first and repeated entries.
  # Private step inputs retain actual certificates; no caller may substitute raw range, budget or state fields.
  template fail(reason: AccumulationReentryError) =
    return AccumulationReentryResult[PreparedAccumulationReentry](status: reason)
  if uint64(step.executions) > uint64(config.selection.executions):
    fail(AccumulationReentryError.LimitExceeded) # Bound even outcomes with no outgoing transfers.
  let batch = step.batch
  for index in 0..<step.executions:
    let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    if outcome.outcomeInfo.value.transfers != 0:
      fail(AccumulationReentryError.UnsupportedTransfers) # Never discard outgoing destination/gas contributions.
  let initial = step.root.executionContinuation.value.continuationPlan.value.continuationSource.value
  let blockQueue = initial.executionRound.value.roundBlockQueue.value
  let queue = blockQueue.accumulationProjection.value
  let count = queue.accumulationCount.value
  let previous = uint64(step.start)
  if previous > uint64(count) or uint64(step.processed) > uint64(count) - previous or
      uint64(step.gasUsed) > uint64(step.budget):
    fail(AccumulationReentryError.InvalidSource) # Prove addition, native conversion and gas subtraction first.
  let start = previous + uint64(step.processed)
  let budget = uint64(step.budget) - uint64(step.gasUsed)
  var remaining = budget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  if step.dispatch:
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
  var working = forkStateStore(step.prior).value
  let applied = applyAccumulationBatch(working, batch)
  if applied.error != AccumulationBatchError.None:
    return AccumulationReentryResult[PreparedAccumulationReentry](
      status: AccumulationReentryError.BatchFailure,
      failed: applied) # Retain only a genuinely failed parent; release private inputs/state candidates.
  let stage = blockQueue.accumulationAdmission.value.reportBlockStage.value.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  AccumulationReentryResult[PreparedAccumulationReentry](status: AccumulationReentryError.None,
    completed: PreparedAccumulationReentry(data: ReentryData(source: step.root,
      previous: step.previous, queue: queue,
      info: AccumulationReentryInfo(depth: step.depth, completedPrefix: AccumulationReportPrefix(
          start),
        pendingReports: count-int(start), prefix: AccumulationReportPrefix(prefix), budget: Gas(
            budget),
        reportGas: Gas(budget-remaining), dispatch: prefix != 0),
      inputs: inputs.value, state: applied.value, slot: slot)))

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
  prepareReentryStep(ReentryStep(root: current.source, previous: data, prior: current.state,
    batch: data.batch, start: current.info.completedPrefix, processed: current.info.prefix,
    budget: current.info.budget, gasUsed: data.gasUsed,
    executions: data.batch.batchInfo.value.executions,
    dispatch: current.info.dispatch, depth: AccumulationReentryDepth(uint64(current.info.depth)+1)), config)
