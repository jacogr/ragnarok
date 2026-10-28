# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind transfer/report reentry service bootstraps to actual posterior accounts and authenticated block entropy.
## Retains immutable source/projection certificates; execution and recursive completion remain separate.

import ../codec/composite as codec_composite
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_layout as codec_state_layout
import ./accumulation_reentry as state_accumulation_reentry
import ./accumulation_continuation_execution as state_accumulation_continuation_execution
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
  AccumulationReentryInvocationError* {.pure.} = enum ## Refusals expose no service, bootstrap or partial source binding.
    Uninitialized,    ## Default result or invocation handle.
    None,             ## Complete selected success permits extraction.
    InvalidInputs,    ## No genuine prepared reentry context was supplied.
    ServiceFailure,   ## Inspect the actual service-resolution reason.
    InvocationFailure ## Inspect the actual entropy/bootstrap reason.
  # Acyclic immutable owner retains the exact reentry source beside its derived bootstrap.
  ReentryInvocationData = ref object
    source: PreparedAccumulationReentry
    projection: PreparedAccumulationInvocation
  ReentryAccumulationInvocation* = object ## Only genuine reentry inputs and derived block entropy construct this certificate.
    data: nil ReentryInvocationData
  AccumulationReentryInvocationResult*[T] = object ## Failed alternatives carry only selected reasons, never earlier source or service owners.
    case status: AccumulationReentryInvocationError
    of None:
      completed: T # Extract only after selected success.
    of ServiceFailure:
      serviceReason: AccumulationServiceError
    of InvocationFailure:
      invocationReason: AccumulationInvocationError
    else:
      discard      # Default/invalid inputs have no payload.

func error*[T](outcome: AccumulationReentryInvocationResult[
    T]): AccumulationReentryInvocationError =
  ## Read the selected reason without permitting retagging.
  outcome.status

func value*[T](outcome: AccumulationReentryInvocationResult[T]): T {.inline,
    requires: outcome.status == AccumulationReentryInvocationError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed

func serviceError*[T](outcome: AccumulationReentryInvocationResult[
    T]): AccumulationServiceError {.inline,

requires: outcome.status == AccumulationReentryInvocationError.ServiceFailure.} =
  ## Inspect only the actual service-resolution refusal.
  outcome.serviceReason

func invocationError*[T](outcome: AccumulationReentryInvocationResult[
    T]): AccumulationInvocationError {.inline,

requires: outcome.status == AccumulationReentryInvocationError.InvocationFailure.} =
  ## Inspect only the actual posterior-entropy or bootstrap refusal.
  outcome.invocationReason

proc bootstrapReentry*(plan: ReentryAccumulationInvocation): AccumulationReentryInvocationResult[
    PreparedAccumulationReentry] =
  ## Retain the exact reentry context independently of this invocation handle's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationReentryInvocationResult[PreparedAccumulationReentry](
      status: AccumulationReentryInvocationError.Uninitialized) # No fabricated posterior source.
  AccumulationReentryInvocationResult[PreparedAccumulationReentry](
    status: AccumulationReentryInvocationError.None, completed: data.source)

proc bootstrapProjection*(plan: ReentryAccumulationInvocation): AccumulationReentryInvocationResult[
    PreparedAccumulationInvocation] =
  ## Retain the derived bootstrap for existing bounded machine initialization without replacement inputs.
  let data = plan.data
  if data == nil:
    return AccumulationReentryInvocationResult[PreparedAccumulationInvocation](
      status: AccumulationReentryInvocationError.Uninitialized) # No default entropy or executable projection.
  AccumulationReentryInvocationResult[PreparedAccumulationInvocation](
    status: AccumulationReentryInvocationError.None, completed: data.projection)

proc prepareReentryAccumulationInvocation*(source: PreparedAccumulationReentry,
    index: InvocationServiceIndex, config: AccumulationServiceConfig,
    limit: ServiceProbeLimit): AccumulationReentryInvocationResult[
        ReentryAccumulationInvocation] =
  ## Resolve the selected posterior service and derive exact C(6) entropy from its original admitted block stage.
  ## Borrow source during preparation, retain it only on complete success; no identifiers or state are reserved.
  template failInvocation(reason: AccumulationInvocationError) =
    return AccumulationReentryInvocationResult[ReentryAccumulationInvocation](
      status: AccumulationReentryInvocationError.InvocationFailure, invocationReason: reason)
  let plan = source.reentryInfo
  if plan.error != AccumulationReentryError.None:
    return AccumulationReentryInvocationResult[ReentryAccumulationInvocation](
      status: AccumulationReentryInvocationError.InvalidInputs) # Defaults cannot authorize service or entropy lookup.
  let service = prepareReentryAccumulationService(source, index, config)
  if service.error != AccumulationReentryError.None:
    return AccumulationReentryInvocationResult[ReentryAccumulationInvocation](
      status: AccumulationReentryInvocationError.ServiceFailure,
      serviceReason: service.serviceError) # Genuine source leaves only the actual ServiceFailure alternative here.
  let round = source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value.executionRound.value
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
  AccumulationReentryInvocationResult[ReentryAccumulationInvocation](
    status: AccumulationReentryInvocationError.None,
    completed: ReentryAccumulationInvocation(data: ReentryInvocationData(source: source,
      projection: prepared.value)))
