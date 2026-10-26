# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run current explicit-input accumulation guests under one parameter/profile configuration, retaining exact provider coverage.
## Ready code executes; unavailable code and absent accounts keep distinct genuine no-execution proofs. No caller state is published.
import ../lib/logging

import ../chain/parameters
import ../codec/[bounded, composite, header, state_safrole]
import ../pvm/[initialize, machine, step, gas, host_fetch]
import ./[accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_context,
  accumulation_machine, accumulation_dispatch, accumulation_outcome, accumulation_skip,
  accumulation_absent, accumulation_annulment, accumulation_coverage, accumulation_effects, store]

type
  AccumulationGuestLimits* = object ## All fields bound actual guest work or retained proof preparation; no unused legacy publication policy.
    services*: ElementLimit ## Total independently resolved source services, including both non-executing alternatives.
    preimageBytes*: ByteLimit ## Local code-preimage copies, separate from the protocol code-size eligibility in Parameters.
    probes*: ServiceProbeLimit ## Initial and guest automatic allocation searches use one explicit local ceiling.
    initialization*: InitializationLimits    ## Envelope, program, jump and page capture before execution.
    contexts*: AccumulationContextConfig ## Explicit caller-authoritative chain shape plus bounded initial chapter copies.
    fetch*: FetchAccumulationLimits          ## Input capture independent of guest payload copies.
    copyBytes*: MemoryByteLimit              ## Maximum one host memory copy.
    logging*: LogWriter
    steps*: ExecutionStepLimit               ## Attempted instructions per ready guest.
    calls*: HostCallLimit                    ## Host dispatches per ready guest.
    cycles*: GasCycleLimit                   ## Bounded basic-block gas inspection.
    provisions*: AccumulationProvisionLimits ## Retained provide effects per guest.
    transfers*, accountWriteKeys*, createdAccounts*,
      deletedAccounts*: ElementLimit         ## Independent current/legacy effect-proof capacities.
    modifiedAccounts*, accountWriteFacts*: ElementLimit ## Ready guests require modified tracking; physical facts remain an explicit downstream opt-in.
    requestFacts*: ElementLimit ## Explicit bounded original request identities, including seeded new-account requests; zero disables capture.
    storageFacts*: AccumulationStorageFactLimits ## Explicit downstream raw identity capture; zero items preserves disabled behavior.
    annulment*: AccumulationAnnulmentLimits  ## Complete original source/modification/conflict inspection ceilings.
    coverage*: AccumulationCoverageLimits    ## Final provider families, row work and aggregate actual gas budget.
  AccumulationGuestError* {.pure.} = enum ## Refusal never exposes earlier successful guests or a partially completed cohort.
    Uninitialized, None, InvalidInputs, InvalidState, InvalidParameters, LimitExceeded,
    ModifiedAccountsDisabled,
    ServiceFailure, InvocationFailure, ContextFailure, MachineFailure, DispatchFailure,
      OutcomeFailure, SkipFailure, AbsentFailure, AnnulmentFailure, CoverageFailure
  AccumulationGuestResult* = object ## Only complete coverage succeeds; parent failures retain their actual reason or genuinely failed guarded result.
    case status: AccumulationGuestError
    of None:
      completed: PreparedAccumulationCoverage # No synthetic resolved service, execution or completed block owner.
    of ServiceFailure:
      serviceReason: AccumulationServiceError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of InvocationFailure:
      invocationReason: AccumulationInvocationError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of ContextFailure:
      contextReason: AccumulationContextError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of MachineFailure:
      machineReason: AccumulationMachineError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of DispatchFailure:
      dispatchReason: AccumulationDispatchResult # Invariant: this is the actual refused parent, never a successful earlier provider.
    of OutcomeFailure:
      outcomeReason: AccumulationOutcomeError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of SkipFailure:
      skipReason: AccumulationSkipError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of AbsentFailure:
      absentReason: AccumulationAbsentError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of AnnulmentFailure:
      annulmentReason: AccumulationAnnulmentError # Invariant: this is the actual refused parent, never a successful earlier provider.
    of CoverageFailure:
      coverageReason: AccumulationCoverageError # Invariant: this is the actual refused parent, never a successful earlier provider.
    else:
      discard # Default and preflight refusals carry no successful payload.

func error*(outcome: AccumulationGuestResult): AccumulationGuestError =
  ## Inspect the selected reason without granting retagging or mutable source access.
  outcome.status
func value*(outcome: AccumulationGuestResult): PreparedAccumulationCoverage {.inline,
    requires: outcome.status == AccumulationGuestError.None.} =
  ## Extract only completely covered original/non-executing providers under checked optimized contracts.
  outcome.completed
func serviceFailure*(outcome: AccumulationGuestResult): AccumulationServiceError {.inline,
    requires: outcome.status == AccumulationGuestError.ServiceFailure.} =
  ## Inspect only the actual refused service preparation; other variants expose no inactive reason payload.
  outcome.serviceReason
func invocationFailure*(outcome: AccumulationGuestResult): AccumulationInvocationError {.inline,
    requires: outcome.status == AccumulationGuestError.InvocationFailure.} =
  ## Inspect only the actual refused invocation bootstrap; other variants expose no inactive reason payload.
  outcome.invocationReason
func contextFailure*(outcome: AccumulationGuestResult): AccumulationContextError {.inline,
    requires: outcome.status == AccumulationGuestError.ContextFailure.} =
  ## Inspect only the actual refused initial context capture; other variants expose no inactive reason payload.
  outcome.contextReason
func machineFailure*(outcome: AccumulationGuestResult): AccumulationMachineError {.inline,
    requires: outcome.status == AccumulationGuestError.MachineFailure.} =
  ## Inspect only the actual refused machine initialization; other variants expose no inactive reason payload.
  outcome.machineReason
func dispatchFailure*(outcome: AccumulationGuestResult): AccumulationDispatchResult {.inline,
    requires: outcome.status == AccumulationGuestError.DispatchFailure.} =
  ## Inspect only the actual refused actual failed dispatch; other variants expose no inactive reason payload.
  outcome.dispatchReason
func outcomeFailure*(outcome: AccumulationGuestResult): AccumulationOutcomeError {.inline,
    requires: outcome.status == AccumulationGuestError.OutcomeFailure.} =
  ## Inspect only the actual refused terminal normalization; other variants expose no inactive reason payload.
  outcome.outcomeReason
func skipFailure*(outcome: AccumulationGuestResult): AccumulationSkipError {.inline,
    requires: outcome.status == AccumulationGuestError.SkipFailure.} =
  ## Inspect only the actual refused code-unavailable completion; other variants expose no inactive reason payload.
  outcome.skipReason
func absentFailure*(outcome: AccumulationGuestResult): AccumulationAbsentError {.inline,
    requires: outcome.status == AccumulationGuestError.AbsentFailure.} =
  ## Inspect only the actual refused absent-account completion; other variants expose no inactive reason payload.
  outcome.absentReason
func annulmentFailure*(outcome: AccumulationGuestResult): AccumulationAnnulmentError {.inline,
    requires: outcome.status == AccumulationGuestError.AnnulmentFailure.} =
  ## Inspect only the actual refused original conflict selection; other variants expose no inactive reason payload.
  outcome.annulmentReason
func coverageFailure*(outcome: AccumulationGuestResult): AccumulationCoverageError {.inline,
    requires: outcome.status == AccumulationGuestError.CoverageFailure.} =
  ## Inspect only the actual refused complete provider coverage; other variants expose no inactive reason payload.
  outcome.coverageReason

proc runAccumulationGuests*(inputs: PreparedAccumulationInputs, state: StateStoreSnapshot,
    slot: HeaderSlot, entropy: StateEntropyWord, parameters: Parameters,
    limits: AccumulationGuestLimits): AccumulationGuestResult =
  ## Execute each independent source service once and certify exact provider coverage; all inputs/state/profile choices are explicit caller authority.
  ## State credit and guest effects remain on private complete-map branches until a separate full selected publication path exists.
  let count = inputs.invocationServiceCount
  if count.error != AccumulationInputError.None:
    return AccumulationGuestResult(status: AccumulationGuestError.InvalidInputs) # Default is not an initialized empty cohort.
  if not sameStateSnapshot(state, state):
    return AccumulationGuestResult(status: AccumulationGuestError.InvalidState) # Owner identity comparison proves initialization without hashing or cloning.
  if not parameters.valid:
    return AccumulationGuestResult(status: AccumulationGuestError.InvalidParameters) # Never read fields from invalid parameter ownership, even for empty cohorts.
  let cores = parameters.get(coreCount)
  let population = uint64(limits.contexts.validators)
  if cores < 2 or cores > 341 or parameters.get(authQueueLen) != 80 or
      uint64(limits.contexts.queues.cores) != cores or uint64(limits.contexts.staging.cores) !=
          cores or
      uint64(limits.contexts.privileges.cores) != cores or population < 6 or population mod 3 !=
          0 or population div 3 > cores:
    return AccumulationGuestResult(status: AccumulationGuestError.InvalidParameters) # Match supported original profile shape without claiming authenticated block authority.
  let maxExecuted = high(int) div sizeof(AccumulationOutcome)
  let maxSkipped = high(int) div sizeof(SkippedAccumulation)
  let maxAbsent = high(int) div sizeof(AbsentAccumulation)
  if uint64(count.value) > uint64(limits.services) or count.value > maxExecuted or
      count.value > maxSkipped or count.value > maxAbsent:
    return AccumulationGuestResult(status: AccumulationGuestError.LimitExceeded) # Bound total work and each native provider array before resolution/allocation.
  let config = AccumulationServiceConfig(codeLimit: ServiceCodeLimit(parameters.get(
      maxServiceCodeSize)),
    preimageBytes: limits.preimageBytes)
  var outcomes: seq[AccumulationOutcome] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  var absent: seq[AbsentAccumulation] = @[]
  for index in 0..<count.value:
    let ordinal = InvocationServiceIndex(uint64(index))
    let service = prepareAccumulationService(inputs, ordinal, state, slot, config)
    if service.error == AccumulationServiceError.MissingAccount:
      let finished = finishAbsentAccumulation(inputs, ordinal, state, slot)
      if finished.error != AccumulationAbsentError.None:
        return AccumulationGuestResult(status: AccumulationGuestError.AbsentFailure,
            absentReason: finished.error) # Actual source absence is rechecked; no fabricated default service.
      absent.add(finished.value)
      continue # No incoming amount arithmetic, context capture or guest bootstrap for this first Psi_A branch.
    if service.error != AccumulationServiceError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.ServiceFailure,
          serviceReason: service.error) # Malformed accounts/resource/backend failures are never code-unavailable success.
    if service.value.serviceInfo.value.code != AccumulationCodeStatus.Ready:
      let finished = finishUninvokedAccumulation(service.value)
      if finished.error != AccumulationSkipError.None:
        return AccumulationGuestResult(status: AccumulationGuestError.SkipFailure,
            skipReason: finished.error) # Retain only a genuinely certified unavailable-code completion.
      skipped.add(finished.value)
      continue # Initial incoming credit survives without code execution.
    if uint64(limits.modifiedAccounts) == 0:
      return AccumulationGuestResult(status: AccumulationGuestError.ModifiedAccountsDisabled) # Ready guests must produce complete original modified sets for current annulment.
    let invocation = prepareAccumulationInvocation(service.value, entropy, limits.probes)
    if invocation.error != AccumulationInvocationError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.InvocationFailure,
          invocationReason: invocation.error) # No replacement seed, cursor or bootstrap after refusal.
    let initial = prepareAccumulationContexts(invocation.value, limits.contexts)
    if initial.error != AccumulationContextError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.ContextFailure,
          contextReason: initial.error) # Explicit shape/copy policy is validated before machine execution.
    let machine = initializeAccumulationMachine(invocation.value, limits.initialization)
    if machine.error != AccumulationMachineError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.MachineFailure,
          machineReason: machine.error) # Malformed programs remain typed local setup refusals, never fake skips or panic outcomes.
    let executed = executeAccumulationMachine(machine.value, parameters, limits.fetch,
      limits.copyBytes, limits.steps, limits.calls, limits.cycles, limits.contexts,
      limits.provisions,
      limits.probes, limits.transfers, limits.accountWriteKeys, limits.createdAccounts,
      limits.deletedAccounts, limits.modifiedAccounts, limits.accountWriteFacts,
      limits.storageFacts, limits.requestFacts, logging = limits.logging)
    if executed.error != AccumulationDispatchError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.DispatchFailure,
          dispatchReason: executed) # Preserve actual step/refusal detail; prior successful guests remain private and release.
    let normalized = normalizeAccumulationOutcome(executed)
    if normalized.error != AccumulationOutcomeError.None:
      return AccumulationGuestResult(status: AccumulationGuestError.OutcomeFailure,
          outcomeReason: normalized.error) # No caller-authored terminal result can fill coverage.
    outcomes.add(normalized.value) # Halt/panic/OOG are genuine completed outcomes with their original actual gas.
  let selected = prepareAccumulationAnnulment(inputs, state, outcomes, limits.annulment)
  if selected.error != AccumulationAnnulmentError.None:
    return AccumulationGuestResult(status: AccumulationGuestError.AnnulmentFailure,
        annulmentReason: selected.error) # No earlier provider collection escapes incomplete current conflict selection.
  let covered = prepareAccumulationCoverage(selected.value, skipped, absent, slot, limits.coverage)
  if covered.error != AccumulationCoverageError.None:
    return AccumulationGuestResult(status: AccumulationGuestError.CoverageFailure,
        coverageReason: covered.error) # Complete current coverage and original gas remain the final success boundary.
  AccumulationGuestResult(status: AccumulationGuestError.None, completed: covered.value)
