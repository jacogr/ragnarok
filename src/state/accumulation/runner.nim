# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute independent source-bound initial-round services and certify one complete supported batch.
## Exposes explicit local ceilings and guarded completion/reasons; never mutates a caller store.

import ../../lib/logging

import ../../chain/parameters
import ../../codec/[bounded, c2_records]
import ../../pvm/[initialize, machine, step]
import ../../pvm/gas/gas
import ../../pvm/host/fetch as host_fetch
import ./[round as accumulation_round, inputs as accumulation_inputs, queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import ./[service as accumulation_service, invocation as accumulation_invocation,
    context as accumulation_context, machine as accumulation_machine,
    dispatch as accumulation_dispatch, skip as accumulation_skip,
    execution as accumulation_execution, effects as accumulation_effects]

type
  AccumulationRunnerLimits* = object ## Service count bounds total work; all guest ceilings apply independently per service.
    completion*: AccumulationExecutionLimits ## Complete batch, gas rows and terminal union policy.
    preimageBytes*: ByteLimit ## Local code-preimage copy ceiling, independent of protocol eligibility.
    probes*: ServiceProbeLimit               ## Bounded invocation successor search and guest automatic ID search.
    initialization*: InitializationLimits    ## Envelope/program/jump/page capture ceilings.
    contexts*: AccumulationContextConfig     ## Exact block population plus bounded initial chapter copies.
    fetch*: FetchAccumulationLimits          ## Input capture independent of host memory copies.
    copyBytes*: MemoryByteLimit              ## One host payload copy ceiling.
    logging*: LogWriter
    steps*: ExecutionStepLimit               ## Attempted instructions per guest, independent of protocol gas.
    calls*: HostCallLimit                    ## Host dispatches per guest.
    backend*: PvmBackend                     ## One immutable selection governs every invocation in this policy.
    cycles*: GasCycleLimit                   ## Gas analysis work per basic block.
    provisions*: AccumulationProvisionLimits ## Retained provide effects per guest.
    transfers*, accountWriteKeys*, createdAccounts*, deletedAccounts*: ElementLimit
      ## Independent effect-proof ceilings; zero preserves existing support gates.
  AccumulationRunnerError* {.pure.} = enum ## No refusal exposes earlier successful services or a partial completed round.
    Uninitialized, None, InvalidRound, InvalidParameters, LimitExceeded, ServiceFailure,
    InvocationFailure, ContextFailure, MachineFailure, SkipFailure, DispatchFailure, CompletionFailure
  AccumulationRunnerResult* = object ## Private alternatives preserve reasons alone until the complete round succeeds.
    case status: AccumulationRunnerError
    of None:
      completed: CompletedBlockAccumulation
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
      dispatchReason: AccumulationDispatchResult # Invariant: failed; preserves the guarded engine reason.
    of CompletionFailure:
      completionReason: AccumulationExecutionResult[
          CompletedBlockAccumulation] # Invariant: failed; preserves batch reasons.
    else:
      discard                         # Default and preflight refusals contain no owner.

func error*(outcome: AccumulationRunnerResult): AccumulationRunnerError =
  ## Inspect the selected alternative without permitting retagging.
  outcome.status

func value*(outcome: AccumulationRunnerResult): CompletedBlockAccumulation {.inline,
    requires: outcome.status == AccumulationRunnerError.None.} =
  ## Retain the complete existing execution owner only after selected success.
  outcome.completed

func serviceError*(outcome: AccumulationRunnerResult): AccumulationServiceError {.inline,
    requires: outcome.status == AccumulationRunnerError.ServiceFailure.} =
  ## Inspect the exact service resolution refusal.
  outcome.serviceReason

func invocationError*(outcome: AccumulationRunnerResult): AccumulationInvocationError {.inline,
    requires: outcome.status == AccumulationRunnerError.InvocationFailure.} =
  ## Inspect the exact bound bootstrap refusal.
  outcome.invocationReason

func contextError*(outcome: AccumulationRunnerResult): AccumulationContextError {.inline,
    requires: outcome.status == AccumulationRunnerError.ContextFailure.} =
  ## Inspect the exact bound population/chapter refusal.
  outcome.contextReason

func machineError*(outcome: AccumulationRunnerResult): AccumulationMachineError {.inline,
    requires: outcome.status == AccumulationRunnerError.MachineFailure.} =
  ## Inspect the exact initialization refusal without a partial CPU.
  outcome.machineReason

func skipError*(outcome: AccumulationRunnerResult): AccumulationSkipError {.inline,
    requires: outcome.status == AccumulationRunnerError.SkipFailure.} =
  ## Inspect the certified skip constructor's refusal.
  outcome.skipReason

func dispatchFailure*(outcome: AccumulationRunnerResult): AccumulationDispatchResult {.inline,
    requires: outcome.status == AccumulationRunnerError.DispatchFailure.} =
  ## Retain only the failed dispatcher result and its existing guarded nested engine reason.
  outcome.dispatchReason

func completionFailure*(outcome: AccumulationRunnerResult):
    AccumulationExecutionResult[CompletedBlockAccumulation] {.inline,
    requires: outcome.status == AccumulationRunnerError.CompletionFailure.} =
  ## Retain only the refused completion result, including its nested complete-batch reasons.
  outcome.completionReason

proc runBlockAccumulation*(round: BlockAccumulationRound, parameters: Parameters,
    limits: AccumulationRunnerLimits): AccumulationRunnerResult =
  ## Resolve every source service, execute ready code and complete once; source state/slot/entropy cannot be replaced.
  ## Each independent service starts at the admitted parent. All successful intermediates remain local until completion.
  let queue = round.roundBlockQueue
  if queue.error != AccumulationRoundError.None:
    return AccumulationRunnerResult(status: AccumulationRunnerError.InvalidRound) # No default/pure source.
  let profile = queue.value.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  let contexts = limits.contexts
  if not parameters.valid or parameters.get(coreCount) != uint64(profile.cores) or
      parameters.get(epochPeriod) != uint64(profile.epochSlots) or parameters.get(authQueueLen) !=
          80 or
      uint64(contexts.validators) != uint64(profile.validators) or
      uint64(contexts.queues.cores) != uint64(profile.cores) or
      uint64(contexts.staging.cores) != uint64(profile.cores) or
      uint64(contexts.privileges.cores) != uint64(profile.cores):
    return AccumulationRunnerResult(status: AccumulationRunnerError.InvalidParameters) # Preflight even empty rounds.
  let count = round.roundProjection.value.roundInputs.value.invocationServiceCount.value
  if uint64(count) > uint64(limits.completion.services) or
      count > high(int) div sizeof(AccumulationDispatchResult) or
      count > high(int) div sizeof(SkippedAccumulation):
    return AccumulationRunnerResult(status: AccumulationRunnerError.LimitExceeded) # Prove extents before allocation/work.
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  # Canonical input-service enumeration also bounds guest work by the checked complete count.
  for index in 0..<count:
    let service = prepareBlockAccumulationService(round, InvocationServiceIndex(uint64(index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(parameters.get(maxServiceCodeSize)),
        preimageBytes: limits.preimageBytes))
    if service.error != AccumulationServiceError.None:
      return AccumulationRunnerResult(status: AccumulationRunnerError.ServiceFailure,
        serviceReason: service.error) # Do not turn local lookup/copy refusal into a protocol skip.
    if service.value.serviceProjection.value.serviceInfo.value.code != AccumulationCodeStatus.Ready:
      # Unavailable/oversized code uses the certified zero-gas alternative, without constructing a CPU.
      let finished = finishBlockUninvokedAccumulation(service.value)
      if finished.error != AccumulationSkipError.None:
        return AccumulationRunnerResult(status: AccumulationRunnerError.SkipFailure,
          skipReason: finished.error) # No forged successful empty effects.
      skipped.add(finished.value.skipProjection.value)
    else:
      # Bound invocation derives posterior entropy and header slot from this exact admitted graph.
      let invocation = prepareBlockAccumulationInvocation(service.value, limits.probes)
      if invocation.error != AccumulationInvocationError.None:
        return AccumulationRunnerResult(status: AccumulationRunnerError.InvocationFailure,
          invocationReason: invocation.error)
      let initial = prepareBlockAccumulationContexts(invocation.value, contexts)
      if initial.error != AccumulationContextError.None:
        return AccumulationRunnerResult(status: AccumulationRunnerError.ContextFailure,
          contextReason: initial.error) # Bind the dispatch policy to the authenticated profile before execution.
      let machine = initializeAccumulationMachine(invocation.value.bootstrapProjection.value,
        limits.initialization)
      if machine.error != AccumulationMachineError.None:
        return AccumulationRunnerResult(status: AccumulationRunnerError.MachineFailure,
          machineReason: machine.error) # Malformed envelopes remain local setup refusals.
      let executed = executeAccumulationMachine(machine.value, parameters, limits.fetch,
        limits.copyBytes, limits.steps, limits.calls, limits.cycles, contexts, limits.provisions,
        limits.probes, limits.transfers, limits.accountWriteKeys, limits.createdAccounts,
        limits.deletedAccounts, logging = limits.logging, backend = limits.backend)
      if executed.error != AccumulationDispatchError.None:
        return AccumulationRunnerResult(status: AccumulationRunnerError.DispatchFailure,
          dispatchReason: executed) # Preserve StepError; prior successes die locally.
      executions.add(executed) # Guest halt/panic/OOG are genuine complete dispatch outcomes.
  let finished = completeBlockAccumulation(round, executions, skipped, limits.completion)
  if finished.error != AccumulationExecutionError.None:
    return AccumulationRunnerResult(status: AccumulationRunnerError.CompletionFailure,
      completionReason: finished) # Existing coverage/account/provision checks remain authoritative.
  AccumulationRunnerResult(status: AccumulationRunnerError.None, completed: finished.value)
