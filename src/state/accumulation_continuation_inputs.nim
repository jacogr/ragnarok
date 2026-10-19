# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind selected continuation range inputs to the actual privately applied initial batch state.
## Retains immutable source/input/full-map owners; never accepts replacement provenance or publishes caller state.

import ../codec/[bounded, c2_records, header]
import ./[accumulation_continuation, accumulation_execution, accumulation_round, accumulation_queue,
  accumulation_operands, accumulation_inputs, accumulation_batch, accumulation_service,
  accumulation_round_transfers, accumulation_transfers, report_admission, block_transition,
  block_admission, store]

type
  AccumulationContinuationInputConfig* = object ## Independent selected-range C.2 and service-input materialization budgets.
    operands*: AccumulationOperandConfig ## Bounds apply only to selected continuation reports and their payloads.
    inputs*: AccumulationInputConfig ## Bounds combined transfer/report groups; no recurring allowances are supplied.
  AccumulationContinuationInputError* {.pure.} = enum ## Refusals expose no partially prepared inputs, state or source plan.
    Uninitialized,  ## Default result or owner without initialized preparation.
    None,           ## Complete selected success permits guarded extraction.
    InvalidPlan,    ## No genuine prepared continuation was supplied.
    OperandFailure, ## Selected range materialization refused; inspect operandError.
    InputFailure,   ## Transfer/report service grouping refused; inspect inputError.
    ServiceFailure, ## Service resolution refused; inspect serviceError.
    BatchFailure    ## Actual private batch application refused; inspect the failed parent's guarded reasons.
  # Private acyclic owner retains only complete range inputs and the actual initial-batch successor.
  ContinuationInputData = ref object
    plan: PreparedAccumulationContinuation
    inputs: PreparedAccumulationInputs
    state: StateStoreSnapshot
    slot: HeaderSlot
  PreparedAccumulationContinuationInputs* = object ## Only genuine continuation selection plus successful private batch application constructs this owner.
    data: nil ContinuationInputData
  AccumulationContinuationInputResult*[T] = object ## Failed parents retain reason alternatives alone, never a successful state payload.
    case status: AccumulationContinuationInputError
    of None:
      completed: T # Only complete selected success exposes immutable certificates or copied observations.
    of OperandFailure:
      operandReason: AccumulationOperandError
    of InputFailure:
      inputReason: AccumulationInputError
    of ServiceFailure:
      serviceReason: AccumulationServiceError
    of BatchFailure:
      failed: AccumulationBatchResult[StateStoreSnapshot] # Invariant: the retained parent is refused, so no snapshot payload exists.
    else:
      discard # Default/invalid source alternatives carry only their reason.

func error*[T](outcome: AccumulationContinuationInputResult[
    T]): AccumulationContinuationInputError =
  ## Inspect the selected reason without permitting retagging.
  outcome.status
func value*[T](outcome: AccumulationContinuationInputResult[T]): T {.inline,
    requires: outcome.status == AccumulationContinuationInputError.None.} =
  ## Extract complete selected success under checked optimized contracts.
  outcome.completed
func operandError*[T](outcome: AccumulationContinuationInputResult[
    T]): AccumulationOperandError {.inline,

requires: outcome.status == AccumulationContinuationInputError.OperandFailure.} =
  ## Inspect only an actual selected-range materialization refusal.
  outcome.operandReason
func inputError*[T](outcome: AccumulationContinuationInputResult[
    T]): AccumulationInputError {.inline,

requires: outcome.status == AccumulationContinuationInputError.InputFailure.} =
  ## Inspect only an actual service-input grouping refusal.
  outcome.inputReason
func serviceError*[T](outcome: AccumulationContinuationInputResult[
    T]): AccumulationServiceError {.inline,

requires: outcome.status == AccumulationContinuationInputError.ServiceFailure.} =
  ## Inspect only the selected service-resolution refusal.
  outcome.serviceReason
func batchFailure*[T](outcome: AccumulationContinuationInputResult[T]): AccumulationBatchResult[
    StateStoreSnapshot] {.inline,

requires: outcome.status == AccumulationContinuationInputError.BatchFailure.} =
  ## Inspect the actually refused batch result, preserving every nested terminal/provision/store reason contract.
  outcome.failed

proc continuationInputs*(owner: PreparedAccumulationContinuationInputs): AccumulationContinuationInputResult[
    PreparedAccumulationInputs] =
  ## Retain transfer/report inputs independently of the preparation handle's lifetime.
  let data = owner.data
  if data == nil:
    return AccumulationContinuationInputResult[PreparedAccumulationInputs](
        status: AccumulationContinuationInputError.Uninitialized) # Defaults are not initialized empty input sets.
  AccumulationContinuationInputResult[PreparedAccumulationInputs](
      status: AccumulationContinuationInputError.None, completed: data.inputs)
proc continuationState*(owner: PreparedAccumulationContinuationInputs): AccumulationContinuationInputResult[
    StateStoreSnapshot] =
  ## Retain the actual complete post-batch map; no root is recomputed from a partial service view.
  let data = owner.data
  if data == nil:
    return AccumulationContinuationInputResult[StateStoreSnapshot](
        status: AccumulationContinuationInputError.Uninitialized) # No default snapshot authorizes a continuation.
  AccumulationContinuationInputResult[StateStoreSnapshot](
      status: AccumulationContinuationInputError.None, completed: data.state)
proc continuationPlan*(owner: PreparedAccumulationContinuationInputs): AccumulationContinuationInputResult[
    PreparedAccumulationContinuation] =
  ## Retain the exact selected-range plan and its admitted completed source.
  let data = owner.data
  if data == nil:
    return AccumulationContinuationInputResult[PreparedAccumulationContinuation](
        status: AccumulationContinuationInputError.Uninitialized) # No substitute plan can be extracted.
  AccumulationContinuationInputResult[PreparedAccumulationContinuation](
      status: AccumulationContinuationInputError.None, completed: data.plan)

proc prepareContinuationAccumulationService*(owner: PreparedAccumulationContinuationInputs,
    index: InvocationServiceIndex, config: AccumulationServiceConfig): AccumulationContinuationInputResult[
        PreparedAccumulationService] =
  ## Resolve a service from the retained inputs and actual posterior map at the authenticated slot.
  let data = owner.data
  if data == nil:
    return AccumulationContinuationInputResult[PreparedAccumulationService](
        status: AccumulationContinuationInputError.Uninitialized) # No default continuation supplies a service source.
  let service = prepareAccumulationService(data.inputs, index, data.state, data.slot, config)
  if service.error != AccumulationServiceError.None:
    return AccumulationContinuationInputResult[PreparedAccumulationService](
      status: AccumulationContinuationInputError.ServiceFailure,
      serviceReason: service.error) # Retain the real failed reason without constructing another module's private result.
  AccumulationContinuationInputResult[PreparedAccumulationService](
    status: AccumulationContinuationInputError.None,
    completed: service.value)

proc prepareAccumulationContinuationInputs*(plan: PreparedAccumulationContinuation,
    config: AccumulationContinuationInputConfig): AccumulationContinuationInputResult[
        PreparedAccumulationContinuationInputs] =
  ## Materialize the selected range and bound outgoing transfers with empty allowances, then apply the actual initial batch privately.
  ## Preserve inherited store ceilings and publish an owner only after all input and state phases succeed.
  let selected = plan.continuationInfo
  if selected.error != AccumulationContinuationError.None:
    return AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
        status: AccumulationContinuationInputError.InvalidPlan) # Default plans cannot authorize state application.
  let source = plan.continuationSource.value
  let round = source.executionRound.value
  let queue = round.roundBlockQueue.value
  let operands = prepareAccumulationOperandRange(queue.accumulationProjection.value,
    AccumulationReportStart(uint64(selected.value.completedPrefix)), selected.value.prefix,
        config.operands)
  if operands.error != AccumulationOperandError.None:
    return AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationInputError.OperandFailure,
      operandReason: operands.error) # No earlier projection escapes before state work.
  let count = selected.value.transfers
  if uint64(count) > uint64(config.inputs.inputs):
    return AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationInputError.InputFailure,
      inputReason: AccumulationInputError.LimitExceeded) # Refuse transfer descriptors before allocating their temporary copy.
  let collected = plan.continuationTransfers.value.roundTransferCollection.value
  # The same retained collection proved this fixed-record native extent before copying; no caller count is accepted.
  var transfers = newSeq[DeferredTransfer](count)
  for index in 0..<count:
    transfers[index] = collected.collectedTransferAt(CollectedTransferIndex(uint64(
        index))).value # Preserve canonical source/append order before destination grouping.
  let inputs = prepareAccumulationInputs(operands.value, transfers, [], config.inputs)
  if inputs.error != AccumulationInputError.None:
    return AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationInputError.InputFailure,
      inputReason: inputs.error) # No recurring allowances or earlier input owner accompanies refusal.
  let stage = queue.accumulationAdmission.value.reportBlockStage.value.value
  var working = forkStateStore(stage.admitted.admittedState).value
  let applied = applyAccumulationBatch(working, source.executionBatch.value)
  if applied.error != AccumulationBatchError.None:
    return AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationInputError.BatchFailure,
      failed: applied) # Only failed enum alternatives survive; the private candidate and inputs are released.
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs](
    status: AccumulationContinuationInputError.None,
    completed: PreparedAccumulationContinuationInputs(data: ContinuationInputData(plan: plan,
      inputs: inputs.value, state: applied.value, slot: slot)))
