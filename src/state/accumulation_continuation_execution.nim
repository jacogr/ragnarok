# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind complete later-round batches and actual service-indexed gas to a genuine continuation context.
## Retains genuine source/batch certificates without executing guests again or publishing state.

import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/header as codec_header
import ../codec/work_digest as codec_work_digest
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ./accumulation_round as state_accumulation_round
import ./accumulation_inputs as state_accumulation_inputs
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./accumulation_batch as state_accumulation_batch
import ./accumulation_dispatch as state_accumulation_dispatch
import ./accumulation_skip as state_accumulation_skip
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_provisions as state_accumulation_provisions
import ./accumulation_effects as state_accumulation_effects
import ./accumulation_context as state_accumulation_context
import ./accumulation_invocation as state_accumulation_invocation
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_continuation as state_accumulation_continuation
import ./accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ./store as state_store

type
  AccumulationContinuationExecutionInfo* = object ## Declared continuation reservations remain separate from actual terminal gas.
    round*: AccumulationContinuationInfo ## Retained selected suffix and recursive budget; allowances do not recur.
    batch*: AccumulationBatchInfo ## Complete input coverage and selected provision accounting.
    services*: int                ## Number of retained service-indexed gas rows.
    gasUsed*: Gas                 ## Checked sum of actual gas, never above the continuation budget.
  AccumulationContinuationExecutionError* {.pure.} = enum ## Refusals expose no completed round, gas sequence or usable batch.
    Uninitialized,   ## Default result or certificate without initialized ownership.
    None,            ## Complete selected success permits guarded extraction.
    InvalidEntropy,  ## The stage has no exact decodable posterior entropy chapter.
    EntropyMismatch, ## An execution bootstrapped from a different posterior entropy word.
    InvalidInputs,   ## No genuine prepared continuation context was supplied.
    InvalidIndex,    ## The full-width gas ordinal is outside this round's service set.
    LimitExceeded,   ## Gas-row count or descriptor extent exceeds local bounds.
    GasExceeded,     ## Actual consumption exceeds the retained continuation's remaining budget.
    BatchFailure     ## Inspect the failed complete-batch result, including its guarded nested reasons.
  # Acyclic immutable storage keeps admitted source, private batch and copied gas accounting together.
  ExecutionData = ref object
    source: PreparedAccumulationContinuationInputs
    batch: PreparedAccumulationBatch
    usage: seq[AccumulationGasUsage]
    gasUsed: Gas
  CompletedAccumulationContinuation* = object ## Only complete verified coverage of genuine continuation inputs constructs this owner.
    data: nil ExecutionData
  AccumulationContinuationExecutionResult*[T] = object ## Failed batch alternatives retain only a genuinely refused parent's reason payload.
    case status: AccumulationContinuationExecutionError
    of None:
      completed: T # Only complete selected success exposes a copied observation or immutable certificate.
    of BatchFailure:
      failed: AccumulationBatchResult[PreparedAccumulationBatch] # Invariant: error != None; no success owner exists.
    else:
      discard # Defaults and other failures carry just their reason.

func error*[T](outcome: AccumulationContinuationExecutionResult[
    T]): AccumulationContinuationExecutionError =
  ## Inspect the selected reason without allowing retagging.
  outcome.status

func value*[T](outcome: AccumulationContinuationExecutionResult[T]): T {.inline,
    requires: outcome.status == AccumulationContinuationExecutionError.None.} =
  ## Extract selected success under checked optimized contracts.
  outcome.completed

func batchFailure*[T](outcome: AccumulationContinuationExecutionResult[T]):
    AccumulationBatchResult[PreparedAccumulationBatch] {.inline,
    requires: outcome.status == AccumulationContinuationExecutionError.BatchFailure.} =
  ## Inspect the actual refused parent result; its existing nested reason contracts remain enforced.
  outcome.failed

# Canonical gas sequence ordering is numeric service order, independent of caller execution order.
func compareUsage(left, right: AccumulationGasUsage): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc executionInfo*(plan: CompletedAccumulationContinuation):
    AccumulationContinuationExecutionResult[AccumulationContinuationExecutionInfo] =
  ## Copy actual usage and declared round reservations without exposing the owned row sequence.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationContinuationExecutionResult[AccumulationContinuationExecutionInfo](
        status: AccumulationContinuationExecutionError.Uninitialized)
  AccumulationContinuationExecutionResult[AccumulationContinuationExecutionInfo](
    status: AccumulationContinuationExecutionError.None,
    completed: AccumulationContinuationExecutionInfo(
      round: data.source.continuationPlan.value.continuationInfo.value,
      batch: data.batch.batchInfo.value, services: data.usage.len, gasUsed: data.gasUsed))

proc executionGasAt*(plan: CompletedAccumulationContinuation, index: InvocationServiceIndex):
    AccumulationContinuationExecutionResult[AccumulationGasUsage] =
  ## Copy the gas row at this round's sorted input-service ordinal; full-width invalid indices refuse before narrowing.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationContinuationExecutionResult[AccumulationGasUsage](
        status: AccumulationContinuationExecutionError.Uninitialized)
  if uint64(index) >= uint64(data.usage.len):
    return AccumulationContinuationExecutionResult[AccumulationGasUsage](
        status: AccumulationContinuationExecutionError.InvalidIndex)
  AccumulationContinuationExecutionResult[AccumulationGasUsage](
    status: AccumulationContinuationExecutionError.None,
    completed: data.usage[int(uint64(index))])

proc executionContinuation*(plan: CompletedAccumulationContinuation):
    AccumulationContinuationExecutionResult[PreparedAccumulationContinuationInputs] =
  ## Retain the exact prepared inputs and posterior state independently of this completion's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationExecutionResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationExecutionError.Uninitialized) # No fabricated continuation source.
  AccumulationContinuationExecutionResult[PreparedAccumulationContinuationInputs](
    status: AccumulationContinuationExecutionError.None, completed: data.source)

proc executionBatch*(plan: CompletedAccumulationContinuation):
    AccumulationContinuationExecutionResult[PreparedAccumulationBatch] =
  ## Retain the complete batch for existing atomic publication against its exact continuation posterior snapshot.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationContinuationExecutionResult[PreparedAccumulationBatch](
        status: AccumulationContinuationExecutionError.Uninitialized)
  AccumulationContinuationExecutionResult[PreparedAccumulationBatch](
    status: AccumulationContinuationExecutionError.None,
    completed: data.batch)

proc completeAccumulationContinuation*(source: PreparedAccumulationContinuationInputs,
    executions: openArray[AccumulationDispatchResult], skipped: openArray[SkippedAccumulation],
    limits: AccumulationExecutionLimits): AccumulationContinuationExecutionResult[
        CompletedAccumulationContinuation] =
  ## Bind complete coverage and actual gas to the round's exact inputs, actual posterior state, slot and posterior entropy.
  ## Borrowed arrays remain stable during the call; terminal selection/union preparation occurs once in the batch adapter.
  # Refuse without publishing an earlier batch or a partial gas sequence.
  template fail(reason: AccumulationContinuationExecutionError) =
    return AccumulationContinuationExecutionResult[CompletedAccumulationContinuation](status: reason)
  let selected = source.continuationPlan
  if selected.error != AccumulationContinuationInputError.None:
    fail(AccumulationContinuationExecutionError.InvalidInputs) # Defaults cannot authorize a completed later round.
  let facts = selected.value.continuationInfo.value
  let inputs = source.continuationInputs.value
  let count = inputs.invocationServiceCount.value
  if uint64(count) > uint64(limits.services) or count > high(int) div sizeof(AccumulationGasUsage):
    fail(AccumulationContinuationExecutionError.LimitExceeded) # Bound complete gas rows before batch hashing/allocation.
  let round = selected.value.continuationSource.value.executionRound.value
  let stage = round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let parent = source.continuationState.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  if executions.len > 0 and executions.len <= count:
    # Prove the bootstrap seed against posterior C(6), not caller-supplied or admitted-parent entropy.
    # Count bounds cap this preflight; invalid dispatches are left for the batch adapter's typed refusal.
    let found = stage.snapshot.lookup(chapterKey(StateChapter(6)))
    if found.error != StateStoreError.None:
      fail(AccumulationContinuationExecutionError.InvalidEntropy)
    if found.value.byteLength != 128:
      fail(AccumulationContinuationExecutionError.InvalidEntropy)
    let entropy = decodeStateEntropy(found.value.bytes)
    if entropy.error != StateComponentError.None:
      fail(AccumulationContinuationExecutionError.InvalidEntropy)
    let expected = array[32, byte](entropy.value.value[0])
    for execution in executions:
      if execution.error == AccumulationDispatchError.None:
        let source = execution.effects.effectsSource.value.initialContext(
            AccumulationDimension.Regular).value
        let invocation = source.contextInvocation.value.bootstrapInfo.value
        if array[32, byte](invocation.entropy) != expected:
          fail(AccumulationContinuationExecutionError.EntropyMismatch) # Refuse before any provision union hashing.
  let batch = prepareCompleteAccumulationBatch(inputs, parent, executions, skipped, slot, limits.batch)
  if batch.error != AccumulationBatchError.None:
    return AccumulationContinuationExecutionResult[CompletedAccumulationContinuation](
      status: AccumulationContinuationExecutionError.BatchFailure,
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
      fail(AccumulationContinuationExecutionError.GasExceeded) # Subtraction proves both budget compliance and sum representability.
    total += consumed
    usage[index] = AccumulationGasUsage(service: info.service, gasUsed: info.gasUsed)
  for index, outcome in skipped:
    # The complete batch already verified each genuine skip's owner, slot, membership and uniqueness.
    usage[executions.len + index] = AccumulationGasUsage(service: outcome.skipInfo.value.service,
        gasUsed: Gas(0))
  usage.sort(compareUsage)
  AccumulationContinuationExecutionResult[CompletedAccumulationContinuation](
    status: AccumulationContinuationExecutionError.None,
    completed: CompletedAccumulationContinuation(data: ExecutionData(source: source,
      batch: batch.value,
      usage: usage, gasUsed: Gas(total))))
