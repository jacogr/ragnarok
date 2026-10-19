# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind supported complete initial batches and actual service-indexed gas to an admitted round.
## Retains genuine source/batch certificates without executing guests again or publishing state.

import std/algorithm
import ../codec/[bounded, composite, header, work_digest, state_safrole, state_layout, state_trie]
import ./[accumulation_round, accumulation_inputs, accumulation_queue, report_admission,
  block_transition, block_admission, accumulation_batch, accumulation_dispatch, accumulation_skip,
  accumulation_outcome, accumulation_provisions, accumulation_effects, accumulation_context,
  accumulation_invocation, store]

type
  AccumulationExecutionLimits* = object ## Independent gas-row work and complete batch preparation ceilings.
    services*: ElementLimit         ## Maximum gas rows, including certified skipped services.
    batch*: AccumulationBatchLimits ## Existing account and terminal union ceilings.
  AccumulationGasUsage* = object ## Copied actual consumption for one service in numeric input-service order.
    service*: ServiceIndex ## Service identity from the verified execution or skip source.
    gasUsed*: Gas          ## Actual terminal consumption; certified skips consume zero.
  AccumulationExecutionInfo* = object ## Declared initial reservations remain separate from actual terminal gas.
    round*: AccumulationRoundInfo ## Original budget, prefix and declared gas reservations.
    batch*: AccumulationBatchInfo ## Complete input coverage and selected provision accounting.
    services*: int                ## Number of retained service-indexed gas rows.
    gasUsed*: Gas                 ## Checked sum of actual gas, never above the initial round budget.
  AccumulationExecutionError* {.pure.} = enum ## Refusals expose no completed round, gas sequence or usable batch.
    Uninitialized,   ## Default result or certificate without initialized ownership.
    None,            ## Complete selected success permits guarded extraction.
    InvalidEntropy,  ## The stage has no exact decodable posterior entropy chapter.
    EntropyMismatch, ## An execution bootstrapped from a different posterior entropy word.
    InvalidRound,    ## The caller supplied no genuine admitted initial round.
    InvalidIndex,    ## The full-width gas ordinal is outside this round's service set.
    LimitExceeded,   ## Gas-row count or descriptor extent exceeds local bounds.
    GasExceeded,     ## Actual consumption exceeds the retained round's remaining budget.
    BatchFailure     ## Inspect the failed complete-batch result, including its guarded nested reasons.
  # Acyclic immutable storage keeps admitted source, private batch and copied gas accounting together.
  ExecutionData = ref object
    round: BlockAccumulationRound
    batch: PreparedAccumulationBatch
    usage: seq[AccumulationGasUsage]
    gasUsed: Gas
  CompletedBlockAccumulation* = object ## Only verified complete execution/skip coverage of a genuine round constructs this owner.
    data: nil ExecutionData
  AccumulationExecutionResult*[T] = object ## Failed batch alternatives retain only a genuinely refused parent's reason payload.
    case status: AccumulationExecutionError
    of None:
      completed: T # Only complete selected success exposes a copied observation or immutable certificate.
    of BatchFailure:
      failed: AccumulationBatchResult[PreparedAccumulationBatch] # Invariant: error != None; no success owner exists.
    else:
      discard # Defaults and other failures carry just their reason.

func error*[T](outcome: AccumulationExecutionResult[T]): AccumulationExecutionError =
  ## Inspect the selected reason without allowing retagging.
  outcome.status

func value*[T](outcome: AccumulationExecutionResult[T]): T {.inline,
    requires: outcome.status == AccumulationExecutionError.None.} =
  ## Extract selected success under checked optimized contracts.
  outcome.completed

func batchFailure*[T](outcome: AccumulationExecutionResult[T]):
    AccumulationBatchResult[PreparedAccumulationBatch] {.inline,
    requires: outcome.status == AccumulationExecutionError.BatchFailure.} =
  ## Inspect the actual refused parent result; its existing nested reason contracts remain enforced.
  outcome.failed

# Canonical gas sequence ordering is numeric service order, independent of caller execution order.
func compareUsage(left, right: AccumulationGasUsage): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc executionInfo*(plan: CompletedBlockAccumulation):
    AccumulationExecutionResult[AccumulationExecutionInfo] =
  ## Copy actual usage and declared round reservations without exposing the owned row sequence.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationExecutionResult[AccumulationExecutionInfo](
        status: AccumulationExecutionError.Uninitialized)
  AccumulationExecutionResult[AccumulationExecutionInfo](status: AccumulationExecutionError.None,
    completed: AccumulationExecutionInfo(round: data.round.roundProjection.value.roundInfo.value,
      batch: data.batch.batchInfo.value, services: data.usage.len, gasUsed: data.gasUsed))

proc executionGasAt*(plan: CompletedBlockAccumulation, index: InvocationServiceIndex):
    AccumulationExecutionResult[AccumulationGasUsage] =
  ## Copy the gas row at this round's sorted input-service ordinal; full-width invalid indices refuse before narrowing.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationExecutionResult[AccumulationGasUsage](
        status: AccumulationExecutionError.Uninitialized)
  if uint64(index) >= uint64(data.usage.len):
    return AccumulationExecutionResult[AccumulationGasUsage](
        status: AccumulationExecutionError.InvalidIndex)
  AccumulationExecutionResult[AccumulationGasUsage](status: AccumulationExecutionError.None,
    completed: data.usage[int(uint64(index))])

proc executionRound*(plan: CompletedBlockAccumulation):
    AccumulationExecutionResult[BlockAccumulationRound] =
  ## Retain the original admitted round, independently of this completion's lifetime.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationExecutionResult[BlockAccumulationRound](
        status: AccumulationExecutionError.Uninitialized)
  AccumulationExecutionResult[BlockAccumulationRound](status: AccumulationExecutionError.None,
    completed: data.round)

proc executionBatch*(plan: CompletedBlockAccumulation):
    AccumulationExecutionResult[PreparedAccumulationBatch] =
  ## Retain the complete batch for existing atomic publication against its exact admitted-parent snapshot.
  let data = plan.data
  # A default owner cannot supply copied observations or retained source/publication certificates.
  if data == nil:
    return AccumulationExecutionResult[PreparedAccumulationBatch](
        status: AccumulationExecutionError.Uninitialized)
  AccumulationExecutionResult[PreparedAccumulationBatch](status: AccumulationExecutionError.None,
    completed: data.batch)

proc completeBlockAccumulation*(round: BlockAccumulationRound,
    executions: openArray[AccumulationDispatchResult], skipped: openArray[SkippedAccumulation],
    limits: AccumulationExecutionLimits): AccumulationExecutionResult[CompletedBlockAccumulation] =
  ## Bind complete coverage and actual gas to the round's exact inputs, admitted parent, slot and posterior entropy.
  ## Borrowed arrays remain stable during the call; terminal selection/union preparation occurs once in the batch adapter.
  # Refuse without publishing an earlier batch or a partial gas sequence.
  template fail(reason: AccumulationExecutionError) =
    return AccumulationExecutionResult[CompletedBlockAccumulation](status: reason)
  let queue = round.roundBlockQueue
  if queue.error != AccumulationRoundError.None:
    fail(AccumulationExecutionError.InvalidRound) # No pure plan or default can substitute admitted provenance.
  let projection = round.roundProjection.value
  let inputs = projection.roundInputs.value
  let count = inputs.invocationServiceCount.value
  if uint64(count) > uint64(limits.services) or count > high(int) div sizeof(AccumulationGasUsage):
    fail(AccumulationExecutionError.LimitExceeded) # Prove the complete row extent before batch hashing/allocation.
  let stage = queue.value.accumulationAdmission.value.reportBlockStage.value.value
  let parent = stage.admitted.admittedState
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  if executions.len > 0 and executions.len <= count:
    # Prove the bootstrap seed against posterior C(6), not caller-supplied or admitted-parent entropy.
    # Count bounds cap this preflight; invalid dispatches are left for the batch adapter's typed refusal.
    let found = stage.snapshot.lookup(chapterKey(StateChapter(6)))
    if found.error != StateStoreError.None:
      fail(AccumulationExecutionError.InvalidEntropy)
    if found.value.byteLength != 128:
      fail(AccumulationExecutionError.InvalidEntropy)
    let entropy = decodeStateEntropy(found.value.bytes)
    if entropy.error != StateComponentError.None:
      fail(AccumulationExecutionError.InvalidEntropy)
    let expected = array[32, byte](entropy.value.value[0])
    for execution in executions:
      if execution.error == AccumulationDispatchError.None:
        let source = execution.effects.effectsSource.value.initialContext(
            AccumulationDimension.Regular).value
        let invocation = source.contextInvocation.value.bootstrapInfo.value
        if array[32, byte](invocation.entropy) != expected:
          fail(AccumulationExecutionError.EntropyMismatch) # Refuse before any provision union hashing.
  let batch = prepareCompleteAccumulationBatch(inputs, parent, executions, skipped, slot, limits.batch)
  if batch.error != AccumulationBatchError.None:
    return AccumulationExecutionResult[CompletedBlockAccumulation](
      status: AccumulationExecutionError.BatchFailure,
      failed: batch) # Only a failed parent result is retained, preserving all nested reason alternatives.
  let budget = uint64(projection.roundInfo.value.budget)
  var total = 0'u64
  var usage = newSeq[AccumulationGasUsage](count)
  for index in 0..<executions.len:
    # Normalized actual consumption includes gas spent before a rolled-back checkpoint or panic.
    let info = batch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(
        index))).value.outcomeInfo.value
    let consumed = uint64(info.gasUsed)
    if consumed > budget - total:
      fail(AccumulationExecutionError.GasExceeded) # Subtraction proves both budget compliance and sum representability.
    total += consumed
    usage[index] = AccumulationGasUsage(service: info.service, gasUsed: info.gasUsed)
  for index, outcome in skipped:
    # The complete batch already verified each genuine skip's owner, slot, membership and uniqueness.
    usage[executions.len + index] = AccumulationGasUsage(service: outcome.skipInfo.value.service,
        gasUsed: Gas(0))
  usage.sort(compareUsage)
  AccumulationExecutionResult[CompletedBlockAccumulation](status: AccumulationExecutionError.None,
    completed: CompletedBlockAccumulation(data: ExecutionData(round: round, batch: batch.value,
      usage: usage, gasUsed: Gas(total))))
