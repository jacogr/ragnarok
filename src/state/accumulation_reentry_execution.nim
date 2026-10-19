# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind complete later-round batches and actual service-indexed gas to a genuine reentry context.
## Retains genuine source/batch certificates without executing guests again or publishing state.

import std/algorithm
import ../codec/[bounded, composite, header, work_digest, state_safrole, state_layout, state_trie]
import ./[accumulation_round, accumulation_inputs, accumulation_queue, report_admission,
  block_transition, block_admission, accumulation_batch, accumulation_dispatch, accumulation_skip,
  accumulation_outcome, accumulation_provisions, accumulation_effects, accumulation_context,
  accumulation_invocation, accumulation_execution, accumulation_continuation,
  accumulation_continuation_inputs, accumulation_continuation_execution, accumulation_reentry, store]

type
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
  ExecutionData = ref object
    source: PreparedAccumulationReentry
    batch: PreparedAccumulationBatch
    usage: seq[AccumulationGasUsage]
    gasUsed: Gas
  CompletedAccumulationReentry* = object ## Only complete verified coverage of genuine reentry inputs constructs this owner.
    data: nil ExecutionData
  AccumulationReentryExecutionResult*[T] = object ## Failed batch alternatives retain only a genuinely refused parent's reason payload.
    case status: AccumulationReentryExecutionError
    of None:
      completed: T # Only complete selected success exposes a copied observation or immutable certificate.
    of BatchFailure:
      failed: AccumulationBatchResult[PreparedAccumulationBatch] # Invariant: error != None; no success owner exists.
    else:
      discard # Defaults and other failures carry just their reason.

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
    completed: CompletedAccumulationReentry(data: ExecutionData(source: source,
      batch: batch.value,
      usage: usage, gasUsed: Gas(total))))
