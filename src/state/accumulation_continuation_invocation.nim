# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind transfer/report continuation service bootstraps to actual posterior accounts and authenticated block entropy.
## Retains immutable source/projection certificates; execution and recursive completion remain separate.

import ../codec/composite as codec_composite
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_layout as codec_state_layout
import ./accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ./accumulation_continuation as state_accumulation_continuation
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./accumulation_inputs as state_accumulation_inputs
import ./accumulation_service as state_accumulation_service
import ./accumulation_invocation as state_accumulation_invocation
import ./store as state_store

type
  AccumulationContinuationInvocationError* {.pure.} = enum ## Refusals expose no service, bootstrap or partial source binding.
    Uninitialized,    ## Default result or invocation handle.
    None,             ## Complete selected success permits extraction.
    InvalidInputs,    ## No genuine prepared continuation context was supplied.
    ServiceFailure,   ## Inspect the actual service-resolution reason.
    InvocationFailure ## Inspect the actual entropy/bootstrap reason.
  # Acyclic immutable owner retains the exact continuation source beside its derived bootstrap.
  ContinuationInvocationData = ref object
    source: PreparedAccumulationContinuationInputs
    projection: PreparedAccumulationInvocation
  ContinuationAccumulationInvocation* = object ## Only genuine continuation inputs and derived block entropy construct this certificate.
    data: nil ContinuationInvocationData
  AccumulationContinuationInvocationResult*[T] = object ## Failed alternatives carry only selected reasons, never earlier source or service owners.
    case status: AccumulationContinuationInvocationError
    of None:
      completed: T # Extract only after selected success.
    of ServiceFailure:
      serviceReason: AccumulationServiceError
    of InvocationFailure:
      invocationReason: AccumulationInvocationError
    else:
      discard      # Default/invalid inputs have no payload.

func error*[T](outcome: AccumulationContinuationInvocationResult[
    T]): AccumulationContinuationInvocationError =
  ## Read the selected reason without permitting retagging.
  outcome.status

func value*[T](outcome: AccumulationContinuationInvocationResult[T]): T {.inline,
    requires: outcome.status == AccumulationContinuationInvocationError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed

func serviceError*[T](outcome: AccumulationContinuationInvocationResult[
    T]): AccumulationServiceError {.inline,

requires: outcome.status == AccumulationContinuationInvocationError.ServiceFailure.} =
  ## Inspect only the actual service-resolution refusal.
  outcome.serviceReason

func invocationError*[T](outcome: AccumulationContinuationInvocationResult[
    T]): AccumulationInvocationError {.inline,

requires: outcome.status == AccumulationContinuationInvocationError.InvocationFailure.} =
  ## Inspect only the actual posterior-entropy or bootstrap refusal.
  outcome.invocationReason

proc bootstrapContinuation*(plan: ContinuationAccumulationInvocation): AccumulationContinuationInvocationResult[
    PreparedAccumulationContinuationInputs] =
  ## Retain the exact continuation context independently of this invocation handle's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationInvocationResult[PreparedAccumulationContinuationInputs](
      status: AccumulationContinuationInvocationError.Uninitialized) # No fabricated posterior source.
  AccumulationContinuationInvocationResult[PreparedAccumulationContinuationInputs](
    status: AccumulationContinuationInvocationError.None, completed: data.source)

proc bootstrapProjection*(plan: ContinuationAccumulationInvocation): AccumulationContinuationInvocationResult[
    PreparedAccumulationInvocation] =
  ## Retain the derived bootstrap for existing bounded machine initialization without replacement inputs.
  let data = plan.data
  if data == nil:
    return AccumulationContinuationInvocationResult[PreparedAccumulationInvocation](
      status: AccumulationContinuationInvocationError.Uninitialized) # No default entropy or executable projection.
  AccumulationContinuationInvocationResult[PreparedAccumulationInvocation](
    status: AccumulationContinuationInvocationError.None, completed: data.projection)

proc prepareContinuationAccumulationInvocation*(source: PreparedAccumulationContinuationInputs,
    index: InvocationServiceIndex, config: AccumulationServiceConfig,
    limit: ServiceProbeLimit): AccumulationContinuationInvocationResult[
        ContinuationAccumulationInvocation] =
  ## Resolve the selected posterior service and derive exact C(6) entropy from its original admitted block stage.
  ## Borrow source during preparation, retain it only on complete success; no identifiers or state are reserved.
  template failInvocation(reason: AccumulationInvocationError) =
    return AccumulationContinuationInvocationResult[ContinuationAccumulationInvocation](
      status: AccumulationContinuationInvocationError.InvocationFailure, invocationReason: reason)
  let plan = source.continuationPlan
  if plan.error != AccumulationContinuationInputError.None:
    return AccumulationContinuationInvocationResult[ContinuationAccumulationInvocation](
      status: AccumulationContinuationInvocationError.InvalidInputs) # Defaults cannot authorize service or entropy lookup.
  let service = prepareContinuationAccumulationService(source, index, config)
  if service.error != AccumulationContinuationInputError.None:
    return AccumulationContinuationInvocationResult[ContinuationAccumulationInvocation](
      status: AccumulationContinuationInvocationError.ServiceFailure,
      serviceReason: service.serviceError) # Genuine source leaves only the actual ServiceFailure alternative here.
  let round = plan.value.continuationSource.value.executionRound.value
  let stage = round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let found = stage.snapshot.lookup(chapterKey(StateChapter(6)))
  if found.error == StateStoreError.MissingKey:
    failInvocation(AccumulationInvocationError.MissingState) # No parent or zero-entropy fallback.
  if found.error != StateStoreError.None:
    failInvocation(AccumulationInvocationError.InvalidState) # Only the authenticated complete stage supplies entropy.
  if found.value.byteLength != 128:
    failInvocation(AccumulationInvocationError.MalformedState) # Prove exact fixed chapter width before copying.
  let decoded = decodeStateEntropy(found.value.bytes)
  if decoded.error != StateComponentError.None:
    failInvocation(AccumulationInvocationError.MalformedState) # Never use partial decoded entropy.
  let prepared = prepareAccumulationInvocation(service.value, decoded.value.value[0], limit)
  if prepared.error != AccumulationInvocationError.None:
    failInvocation(prepared.error) # Code eligibility, hash failure and probe exhaustion preserve exact reasons.
  AccumulationContinuationInvocationResult[ContinuationAccumulationInvocation](
    status: AccumulationContinuationInvocationError.None,
    completed: ContinuationAccumulationInvocation(data: ContinuationInvocationData(source: source,
      projection: prepared.value)))
