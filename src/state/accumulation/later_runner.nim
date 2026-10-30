# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute one genuine report-only continuation or reentry from its actual posterior state.
## Reuses explicit initial-runner policies and existing completion certificates; no recursion or publication.

import ../../chain/parameters
import ../../codec/bounded
import ./[runner as accumulation_runner, round as accumulation_round, inputs as accumulation_inputs,
    queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import ./[execution as accumulation_execution, service as accumulation_service,
    invocation as accumulation_invocation, context as accumulation_context,
    machine as accumulation_machine, dispatch as accumulation_dispatch, skip as accumulation_skip,
    continuation as accumulation_continuation]
import ./continuation/[inputs as accumulation_continuation_inputs,
    invocation as accumulation_continuation_invocation,
    execution as accumulation_continuation_execution]
import ./reentry as accumulation_reentry
import ./reentry/invocation as accumulation_reentry_invocation

type
  AccumulationLaterRunnerError* {.pure.} = enum ## Refusals contain no successful earlier guest or partially certified round.
    Uninitialized, None, InvalidSource, InvalidParameters, LimitExceeded, ServiceFailure,
    InvocationFailure, ContextFailure, MachineFailure, SkipFailure, DispatchFailure,
    ContinuationFailure, ReentryFailure
  # A failed branch has only reasons; copying it between result instantiations cannot retain a success owner.
  LaterFailure = object
    case status: AccumulationLaterRunnerError
    of ServiceFailure:
      serviceReason: AccumulationServiceError
    of InvocationFailure:
      invocationReason: AccumulationInvocationError
    of ContextFailure:
      contextReason: AccumulationContextError
    of MachineFailure:
      machineReason: AccumulationMachineError
    of SkipFailure:
      skipReason: AccumulationSkipError
    of DispatchFailure:
      dispatchReason: AccumulationDispatchResult # Invariant: failed; includes guarded StepError where selected.
    of ContinuationFailure:
      continuationReason: AccumulationContinuationExecutionResult[CompletedAccumulationContinuation]
        # Invariant: failed; preserves nested batch/terminal/provision/store reasons.
    of ReentryFailure:
      reentryReason: AccumulationReentryExecutionResult[CompletedAccumulationReentry]
        # Invariant: failed; preserves nested batch/terminal/provision/store reasons.
    else:
      discard # Defaults and preflight refusals own no partial work.
  AccumulationLaterRunnerResult*[T] = object ## Private success tag and reason-only failure permit no external retagging or payload access.
    case succeeded: bool
    of true:
      completed: T
    of false:
      refusal: LaterFailure
  LaterSourceKind {.pure.} = enum ## Closed private dispatch preserves concrete source families in the shared loop.
    Continuation, Reentry
  LaterSource = object ## Only public adapters construct this private source after validating its genuine certificate.
    case kind: LaterSourceKind
    of Continuation:
      continuation: PreparedAccumulationContinuationInputs
    of Reentry:
      reentry: PreparedAccumulationReentry
  GuestBatch = object ## Private intermediate arrays never escape a refused public execution call.
    executions: seq[AccumulationDispatchResult]
    skipped: seq[SkippedAccumulation]

func error*[T](outcome: AccumulationLaterRunnerResult[T]): AccumulationLaterRunnerError =
  ## Read a selected reason; a default result is Uninitialized, never an empty successful round.
  if outcome.succeeded: AccumulationLaterRunnerError.None
  else: outcome.refusal.status

func value*[T](outcome: AccumulationLaterRunnerResult[T]): T {.inline,
    requires: outcome.succeeded.} =
  ## Retain only explicitly selected complete success under optimized contracts.
  outcome.completed

func serviceError*[T](outcome: AccumulationLaterRunnerResult[T]): AccumulationServiceError {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.ServiceFailure.} =
  ## Inspect only an actual service-resolution refusal.
  outcome.refusal.serviceReason

func invocationError*[T](outcome: AccumulationLaterRunnerResult[
    T]): AccumulationInvocationError {.inline,

requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.InvocationFailure.} =
  ## Inspect only an actual entropy/bootstrap refusal.
  outcome.refusal.invocationReason

func contextError*[T](outcome: AccumulationLaterRunnerResult[T]): AccumulationContextError {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.ContextFailure.} =
  ## Inspect only an actual context preparation refusal.
  outcome.refusal.contextReason

func machineError*[T](outcome: AccumulationLaterRunnerResult[T]): AccumulationMachineError {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.MachineFailure.} =
  ## Inspect only an actual machine initialization refusal.
  outcome.refusal.machineReason

func skipError*[T](outcome: AccumulationLaterRunnerResult[T]): AccumulationSkipError {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.SkipFailure.} =
  ## Inspect only the certified skip constructor's refusal.
  outcome.refusal.skipReason

func dispatchFailure*[T](outcome: AccumulationLaterRunnerResult[
    T]): AccumulationDispatchResult {.inline,

requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.DispatchFailure.} =
  ## Retain the genuinely failed dispatcher result, including its selected engine reason.
  outcome.refusal.dispatchReason

func continuationFailure*[T](outcome: AccumulationLaterRunnerResult[T]):
    AccumulationContinuationExecutionResult[CompletedAccumulationContinuation] {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.ContinuationFailure.} =
  ## Retain the failed continuation completion result and its guarded nested reasons.
  outcome.refusal.continuationReason

func reentryFailure*[T](outcome: AccumulationLaterRunnerResult[T]):
    AccumulationReentryExecutionResult[CompletedAccumulationReentry] {.inline,
    requires: not outcome.succeeded and outcome.refusal.status ==
        AccumulationLaterRunnerError.ReentryFailure.} =
  ## Retain the failed reentry completion result and its guarded nested reasons.
  outcome.refusal.reentryReason

proc serviceFor(source: PreparedAccumulationContinuationInputs, index: InvocationServiceIndex,
    config: AccumulationServiceConfig): AccumulationLaterRunnerResult[PreparedAccumulationService] =
  ## Normalize the continuation adapter's reasons without exposing a partial service.
  let prepared = prepareContinuationAccumulationService(source, index, config)
  case prepared.error
  of AccumulationContinuationInputError.None:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: true,
        completed: prepared.value)
  of AccumulationContinuationInputError.ServiceFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ServiceFailure, serviceReason: prepared.serviceError))
  else:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # No default source can authorize private work.

proc invocationFor(source: PreparedAccumulationContinuationInputs, index: InvocationServiceIndex,
    config: AccumulationServiceConfig, probes: ServiceProbeLimit):
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation] =
  ## Retain only this continuation source's successful bound bootstrap or selected refusal.
  let prepared = prepareContinuationAccumulationInvocation(source, index, config, probes)
  case prepared.error
  of AccumulationContinuationInvocationError.None:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: true,
      completed: prepared.value.bootstrapProjection.value)
  of AccumulationContinuationInvocationError.ServiceFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ServiceFailure, serviceReason: prepared.serviceError))
  of AccumulationContinuationInvocationError.InvocationFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvocationFailure,
      invocationReason: prepared.invocationError))
  else:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # Unexpected invalid ownership remains a typed refusal.

proc serviceFor(source: PreparedAccumulationReentry, index: InvocationServiceIndex,
    config: AccumulationServiceConfig): AccumulationLaterRunnerResult[PreparedAccumulationService] =
  ## Normalize the reentry adapter's reasons without exposing a partial service.
  let prepared = prepareReentryAccumulationService(source, index, config)
  case prepared.error
  of AccumulationReentryError.None:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: true,
        completed: prepared.value)
  of AccumulationReentryError.ServiceFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ServiceFailure, serviceReason: prepared.serviceError))
  else:
    AccumulationLaterRunnerResult[PreparedAccumulationService](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # No default source can authorize private work.

proc invocationFor(source: PreparedAccumulationReentry, index: InvocationServiceIndex,
    config: AccumulationServiceConfig, probes: ServiceProbeLimit):
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation] =
  ## Retain only this reentry source's successful bound bootstrap or selected refusal.
  let prepared = prepareReentryAccumulationInvocation(source, index, config, probes)
  case prepared.error
  of AccumulationReentryInvocationError.None:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: true,
      completed: prepared.value.bootstrapProjection.value)
  of AccumulationReentryInvocationError.ServiceFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ServiceFailure, serviceReason: prepared.serviceError))
  of AccumulationReentryInvocationError.InvocationFailure:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvocationFailure,
      invocationReason: prepared.invocationError))
  else:
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # Unexpected invalid ownership remains a typed refusal.

proc serviceFor(source: LaterSource, index: InvocationServiceIndex,
    config: AccumulationServiceConfig): AccumulationLaterRunnerResult[PreparedAccumulationService] =
  ## Dispatch only over the two concrete private source alternatives; no generic overload escape is needed.
  case source.kind
  of LaterSourceKind.Continuation:
    serviceFor(source.continuation, index, config) # Preserve exact continuation inputs/prior.
  of LaterSourceKind.Reentry:
    serviceFor(source.reentry, index, config) # Preserve exact current-depth inputs/prior.

proc invocationFor(source: LaterSource, index: InvocationServiceIndex,
    config: AccumulationServiceConfig, probes: ServiceProbeLimit):
    AccumulationLaterRunnerResult[PreparedAccumulationInvocation] =
  ## Choose the existing bound invocation adapter using the private genuine source family.
  case source.kind
  of LaterSourceKind.Continuation:
    invocationFor(source.continuation, index, config,
        probes) # Original block entropy and slot are derived by the adapter.
  of LaterSourceKind.Reentry:
    invocationFor(source.reentry, index, config, probes) # Repeated depths retain direct original-block provenance.

proc runServices(source: LaterSource, round: BlockAccumulationRound,
    inputs: PreparedAccumulationInputs, parameters: Parameters,
    limits: AccumulationRunnerLimits): AccumulationLaterRunnerResult[GuestBatch] =
  ## Private callers already proved source ownership; neither root nor inputs are public substitution points.
  ## Both source families use the same bounded service/CPU loop and retain their own invocation adapters.
  let profile = round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  let contexts = limits.contexts
  if not parameters.valid or parameters.get(coreCount) != uint64(profile.cores) or
      parameters.get(epochPeriod) != uint64(profile.epochSlots) or parameters.get(authQueueLen) !=
          80 or
      uint64(contexts.validators) != uint64(profile.validators) or
      uint64(contexts.queues.cores) != uint64(profile.cores) or
      uint64(contexts.staging.cores) != uint64(profile.cores) or
      uint64(contexts.privileges.cores) != uint64(profile.cores):
    return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
        status: AccumulationLaterRunnerError.InvalidParameters)) # Check the original block's profile even for stopped sources.
  let count = inputs.invocationServiceCount.value
  if uint64(count) > uint64(limits.completion.services) or
      count > high(int) div sizeof(AccumulationDispatchResult) or
      count > high(int) div sizeof(SkippedAccumulation):
    return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
        status: AccumulationLaterRunnerError.LimitExceeded)) # Bound descriptor extents and total per-service work before allocation.
  let config = AccumulationServiceConfig(codeLimit: ServiceCodeLimit(parameters.get(
      maxServiceCodeSize)),
    preimageBytes: limits.preimageBytes)
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  for index in 0..<count:
    # Resolve from this round's complete actual posterior map, independently for each numeric input ordinal.
    let service = serviceFor(source, InvocationServiceIndex(uint64(index)), config)
    if service.error != AccumulationLaterRunnerError.None:
      return AccumulationLaterRunnerResult[GuestBatch](succeeded: false,
          refusal: service.refusal) # Copy selected failure reasons alone.
    if service.value.serviceInfo.value.code != AccumulationCodeStatus.Ready:
      # Only a real unavailable/oversized service certificate authorizes this zero-gas outcome.
      let finished = finishUninvokedAccumulation(service.value)
      if finished.error != AccumulationSkipError.None:
        return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
          status: AccumulationLaterRunnerError.SkipFailure, skipReason: finished.error))
      skipped.add(finished.value)
    else:
      # Existing bound adapters derive the original block slot and posterior entropy; no free seed/state input exists.
      let invocation = invocationFor(source, InvocationServiceIndex(uint64(index)), config, limits.probes)
      if invocation.error != AccumulationLaterRunnerError.None:
        return AccumulationLaterRunnerResult[GuestBatch](succeeded: false,
            refusal: invocation.refusal) # No success bootstrap accompanies failure.
      let bootstrap = invocation.value
      let initial = prepareAccumulationContexts(bootstrap, contexts)
      if initial.error != AccumulationContextError.None:
        return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
          status: AccumulationLaterRunnerError.ContextFailure, contextReason: initial.error))
      let machine = initializeAccumulationMachine(bootstrap, limits.initialization)
      if machine.error != AccumulationMachineError.None:
        return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
          status: AccumulationLaterRunnerError.MachineFailure, machineReason: machine.error))
      let executed = executeAccumulationMachine(machine.value, parameters, limits.fetch,
        limits.copyBytes, limits.steps, limits.calls, limits.cycles, contexts, limits.provisions,
        limits.probes, limits.transfers, limits.accountWriteKeys, limits.createdAccounts,
        limits.deletedAccounts, logging = limits.logging, backend = limits.backend)
      if executed.error != AccumulationDispatchError.None:
        return AccumulationLaterRunnerResult[GuestBatch](succeeded: false, refusal: LaterFailure(
          status: AccumulationLaterRunnerError.DispatchFailure,
          dispatchReason: executed)) # Retain exact engine/host reasons.
      executions.add(executed) # Guest panic/OOG are successful dispatcher outcomes, not local failures.
  AccumulationLaterRunnerResult[GuestBatch](succeeded: true,
    completed: GuestBatch(executions: executions, skipped: skipped))

proc runAccumulationContinuation*(source: PreparedAccumulationContinuationInputs,
    parameters: Parameters, limits: AccumulationRunnerLimits):
    AccumulationLaterRunnerResult[CompletedAccumulationContinuation] =
  ## Execute all selected continuation services against their actual post-initial-batch map; certify completion once.
  let plan = source.continuationPlan
  if plan.error != AccumulationContinuationInputError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationContinuation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # Defaults do not authorize a synthetic stopped round.
  let round = plan.value.continuationSource.value.executionRound.value
  let guests = runServices(LaterSource(kind: LaterSourceKind.Continuation, continuation: source),
      round, source.continuationInputs.value, parameters, limits)
  if guests.error != AccumulationLaterRunnerError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationContinuation](succeeded: false,
        refusal: guests.refusal) # Copy reasons alone.
  let finished = completeAccumulationContinuation(source, guests.value.executions,
      guests.value.skipped, limits.completion)
  if finished.error != AccumulationContinuationExecutionError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationContinuation](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ContinuationFailure,
      continuationReason: finished)) # Preserve failed batch reasons.
  AccumulationLaterRunnerResult[CompletedAccumulationContinuation](succeeded: true,
      completed: finished.value)

proc runAccumulationReentry*(source: PreparedAccumulationReentry,
    parameters: Parameters, limits: AccumulationRunnerLimits):
    AccumulationLaterRunnerResult[CompletedAccumulationReentry] =
  ## Execute one genuine reentry at any prepared depth, with direct original-block provenance and exact posterior state.
  if source.reentryInfo.error != AccumulationReentryError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationReentry](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.InvalidSource)) # No default/pure source or caller-authored outcome arrays.
  let round = source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value.executionRound.value
  let guests = runServices(LaterSource(kind: LaterSourceKind.Reentry, reentry: source), round,
      source.reentryInputs.value, parameters, limits)
  if guests.error != AccumulationLaterRunnerError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationReentry](succeeded: false,
        refusal: guests.refusal) # No successful intermediates retained.
  let finished = completeAccumulationReentry(source, guests.value.executions, guests.value.skipped,
      limits.completion)
  if finished.error != AccumulationReentryExecutionError.None:
    return AccumulationLaterRunnerResult[CompletedAccumulationReentry](succeeded: false,
      refusal: LaterFailure(
      status: AccumulationLaterRunnerError.ReentryFailure,
      reentryReason: finished)) # Preserve all nested completion reasons.
  AccumulationLaterRunnerResult[CompletedAccumulationReentry](succeeded: true,
      completed: finished.value)
