# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare finalized successors from owned blocks against the selected complete-map application head.
## Existing state/PVM stages retain authority; private prefixes never publish until a later handoff tick.

import ./[chain, handoff]
import ../chain/[genesis, provider, parameters]
import ../codec/[block_codec, header, bounded]
import ../state/[fuzz_ancestry, store, block_transition, report_transition, report_admission,
  accumulation_queue,
  accumulation_round, accumulation_runner, accumulation_driver, accumulation_finalization,
  accumulation_outputs, accumulation_completion, report_anchors, accumulation_current_completion,
  accumulation_current_update, accumulation_storage_history, service_identity_history, request_identity_history]

type
  ApplicationCandidateLimits* = object ## Caller-owned bounded stage policies, including explicit trusted round gas configuration.
    reporting*: BlockReportConfig
    queue*: AccumulationQueueConfig
    round*: AccumulationRoundConfig
    execution*: AccumulationRunnerLimits
    driver*: AccumulationDriverLimits
    finalization*: AccumulationOutputHistoryLimits
  ApplicationCandidateError* {.pure.} = enum ## Defaults and failures never expose an earlier successfully prepared prefix.
    Uninitialized, None, Busy, MissingHead, ProfileMismatch, StateFailure, BlockFailure,
    ReportFailure, QueueFailure, RoundFailure, RunnerFailure, DriverFailure,
    FinalizationFailure, EnqueueFailure, StateChanged
  ApplicationCandidateResult* = object ## Only complete finalized success retains a usable execution certificate.
    case status: ApplicationCandidateError
    of None:
      completed: PreparedFinalAccumulation
    of StateFailure:
      stateReason: StateStoreError
    of BlockFailure:
      blockReason: BlockTransitionResult
    of ReportFailure:
      reportReason: ReportAdmissionResult[AdmittedReports]
    of QueueFailure:
      queueReason: AccumulationQueueError
    of RoundFailure:
      roundReason: AccumulationRoundError
    of RunnerFailure:
      runnerReason: AccumulationRunnerResult
    of DriverFailure:
      driverReason: AccumulationDriverResult
    of FinalizationFailure:
      finalReason: AccumulationFinalizationResult[PreparedFinalAccumulation]
    of EnqueueFailure:
      enqueueReason: AccumulationEnqueueError
    else:
      discard # Defaults, Busy, missing heads and profile refusal retain no candidate data.

  CandidateReportData = ref object ## Immutable exact-parent block/report preparation waits without running accumulation guests.
    original: ChainView
    parameters: Parameters
    reports: PreparedReportAdmission
    limits: ApplicationCandidateLimits
  PreparedCandidateReports* = object ## A successful prefix is distinct from a finalized/adoptable execution certificate.
    data: nil CandidateReportData
  CandidateReportPreparation* = object ## Complete preparation or original typed pipeline refusal, never a failed partial owner.
    case successful: bool
    of true:
      prepared: PreparedCandidateReports
    else:
      refusal: ApplicationCandidateResult

func error*(outcome: ApplicationCandidateResult): ApplicationCandidateError =
  ## Inspect selected preparation/admission status without exposing its mutable discriminator.
  outcome.status

func value*(outcome: ApplicationCandidateResult): PreparedFinalAccumulation {.inline,
    requires: outcome.status == ApplicationCandidateError.None.} =
  ## Extract only a fully finalized execution successor; adoption remains a separate dispatcher step.
  outcome.completed

func stateError*(outcome: ApplicationCandidateResult): StateStoreError {.inline,
    requires: outcome.status == ApplicationCandidateError.StateFailure.} =
  ## Inspect only the actual selected StateFailure cause, without earlier successful owners.
  outcome.stateReason

func blockFailure*(outcome: ApplicationCandidateResult): BlockTransitionResult {.inline,
    requires: outcome.status == ApplicationCandidateError.BlockFailure.} =
  ## Inspect only the actual selected BlockFailure cause, without earlier successful owners.
  outcome.blockReason

func reportFailure*(outcome: ApplicationCandidateResult): ReportAdmissionResult[
    AdmittedReports] {.inline,

requires: outcome.status == ApplicationCandidateError.ReportFailure.} =
  ## Inspect only the actual selected ReportFailure cause, without earlier successful owners.
  outcome.reportReason

func queueError*(outcome: ApplicationCandidateResult): AccumulationQueueError {.inline,
    requires: outcome.status == ApplicationCandidateError.QueueFailure.} =
  ## Inspect only the actual selected QueueFailure cause, without earlier successful owners.
  outcome.queueReason

func roundError*(outcome: ApplicationCandidateResult): AccumulationRoundError {.inline,
    requires: outcome.status == ApplicationCandidateError.RoundFailure.} =
  ## Inspect only the actual selected RoundFailure cause, without earlier successful owners.
  outcome.roundReason

func runnerFailure*(outcome: ApplicationCandidateResult): AccumulationRunnerResult {.inline,
    requires: outcome.status == ApplicationCandidateError.RunnerFailure.} =
  ## Inspect only the actual selected RunnerFailure cause, without earlier successful owners.
  outcome.runnerReason

func driverFailure*(outcome: ApplicationCandidateResult): AccumulationDriverResult {.inline,
    requires: outcome.status == ApplicationCandidateError.DriverFailure.} =
  ## Inspect only the actual selected DriverFailure cause, without earlier successful owners.
  outcome.driverReason

func finalizationFailure*(outcome: ApplicationCandidateResult): AccumulationFinalizationResult[
    PreparedFinalAccumulation] {.inline,

requires: outcome.status == ApplicationCandidateError.FinalizationFailure.} =
  ## Inspect only the actual selected FinalizationFailure cause, without earlier successful owners.
  outcome.finalReason

func enqueueError*(outcome: ApplicationCandidateResult): AccumulationEnqueueError {.inline,
    requires: outcome.status == ApplicationCandidateError.EnqueueFailure.} =
  ## Inspect only the actual selected EnqueueFailure cause, without earlier successful owners.
  outcome.enqueueReason


func valid*(prepared: PreparedCandidateReports): bool =
  ## Distinguish a successful opaque prefix from an uninitialized owner.
  prepared.data != nil

func error*(outcome: CandidateReportPreparation): ApplicationCandidateError =
  ## Preparation success grants only the report-prefix owner; error retains the original selected stage reason.
  if outcome.successful: ApplicationCandidateError.None
  else: outcome.refusal.error # Default refusal stays Uninitialized.
func value*(outcome: CandidateReportPreparation): PreparedCandidateReports {.inline,
    requires: outcome.successful.} =
  ## Retain only a genuinely prepared original block context.
  outcome.prepared
func failure*(outcome: CandidateReportPreparation): ApplicationCandidateResult {.inline,
    requires: not outcome.successful.} =
  ## Preserve the exact existing pipeline failure without converting a prefix into final success.
  outcome.refusal
proc refusedReportPreparation(reason: ApplicationCandidateResult): CandidateReportPreparation =
  ## Internal bridge retains only a failed existing pipeline alternative.
  CandidateReportPreparation(successful: false, refusal: reason)

proc candidateLookupDemand*(prepared: PreparedCandidateReports,
    ancestors: openArray[OwnedHeader]): ReportAdmissionResult[ReportLookupDemand] =
  ## Discover only against the original block-bound report owner; no canonical access or guest execution occurs.
  let data = prepared.data
  if data == nil:
    return planPreparedReportLookupDemand(default(PreparedReportAdmission), ancestors)
  planPreparedReportLookupDemand(data.reports, ancestors)
proc prepareCandidateReports*(chain: ApplicationChain, candidate: OwnedBlock,
    limits: ApplicationCandidateLimits): CandidateReportPreparation =
  ## Execute existing implemented stages privately with parent/header/parameters selected from this exact canonical head.
  ## Preparation is synchronous and belongs outside transport callbacks; only later adoption is dispatched.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None:
    return refusedReportPreparation(ApplicationCandidateResult(
        status: ApplicationCandidateError.MissingHead)) # No implicit empty parent.
  let head = selected.value
  let frame = limits.reporting.admission.frame
  # GP valcount permits independent roster sizes; the decoder ceiling covers the head up to three validators per core.
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) < uint64(head.activeValidators) or
      uint64(frame.validators) mod 3 != 0 or
      uint64(frame.validators) div 3 > uint64(head.cores) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return refusedReportPreparation(ApplicationCandidateResult(
        status: ApplicationCandidateError.ProfileMismatch)) # Reject unrelated chain domains before native work.
  let current = chain.stateSnapshot
  if current.error != StateStoreError.None:
    return refusedReportPreparation(ApplicationCandidateResult(
        status: ApplicationCandidateError.StateFailure, stateReason: current.error))
  let forked = forkStateStore(current.value)
  if forked.error != StateStoreError.None:
    return refusedReportPreparation(ApplicationCandidateResult(
        status: ApplicationCandidateError.StateFailure, stateReason: forked.error))
  var working = forked.value
  let config = limits.reporting
  let staged = if chain.chainView.fuzzOnly and head.fuzzSeedOnly:
    advanceFuzzSeedState(working, candidate, head.header, config.admission,
      config.disputes, config.safrole, config.availability)
  else:
    advanceBlockState(working, candidate, head.header, config.admission,
      config.disputes, config.safrole, config.availability) # Only the immutable marked fuzz seed grants genesis-like pairing.
  if staged.error != BlockTransitionError.None:
    return refusedReportPreparation(ApplicationCandidateResult(
      status: ApplicationCandidateError.BlockFailure,
      blockReason: staged)) # Prefix publication affects only the private fork.
  let reports = prepareBlockReports(staged, config.reports)
  if reports.error != ReportAdmissionError.None:
    return refusedReportPreparation(ApplicationCandidateResult(
      status: ApplicationCandidateError.ReportFailure,
      reportReason: reportPreparationFailure(reports)))
  CandidateReportPreparation(successful: true, prepared: PreparedCandidateReports(data:
    CandidateReportData(original: chain.chainView, parameters: head.chainParameters,
      reports: reports.value, limits: limits)))

proc completeCandidateReports*(chain: ApplicationChain, prepared: PreparedCandidateReports,
    ancestors: openArray[OwnedHeader]): ApplicationCandidateResult =
  ## Recheck exact canonical ownership before completing the original reports and executing accumulation once.
  let data = prepared.data
  if data == nil:
    return ApplicationCandidateResult(status: ApplicationCandidateError.Uninitialized)
  if not sameChainView(data.original, chain.chainView):
    return ApplicationCandidateResult(status: ApplicationCandidateError.StateChanged)
  let limits = data.limits
  let reports = completeBlockReports(data.reports, ancestors)
  if reports.error != ReportAdmissionError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.ReportFailure,
        reportReason: reports)
  let queue = planBlockAccumulationQueue(reports.value, limits.queue)
  if queue.error != AccumulationQueueError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.QueueFailure,
        queueReason: queue.error)
  let round = planBlockInitialAccumulation(queue.value, limits.round)
  if round.error != AccumulationRoundError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.RoundFailure,
        roundReason: round.error)
  let parameters = data.parameters
  let executed = runBlockAccumulation(round.value, parameters, limits.execution)
  if executed.error != AccumulationRunnerError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.RunnerFailure,
        runnerReason: executed)
  let stopped = driveAccumulation(executed.value, parameters, limits.driver)
  if stopped.error != AccumulationDriverError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.DriverFailure,
        driverReason: stopped)
  let finalized = prepareFinalAccumulation(stopped.value, limits.finalization)
  if finalized.error != AccumulationFinalizationError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.FinalizationFailure,
        finalReason: finalized)
  ApplicationCandidateResult(status: ApplicationCandidateError.None, completed: finalized.value)

proc prepareCandidate*(chain: ApplicationChain, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits): ApplicationCandidateResult =
  ## One-shot callers use the same original report preparation and exact-parent completion without requesting acquisition.
  let prepared = prepareCandidateReports(chain, candidate, limits)
  if prepared.error != ApplicationCandidateError.None: return prepared.failure
  completeCandidateReports(chain, prepared.value, ancestors)

proc enqueueCandidate*(handoff: var AccumulationHandoff, chain: ApplicationChain,
    candidate: OwnedBlock, ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits,
    composition: AccumulationCompositionLimits): ApplicationCandidateResult =
  ## Backpressure precedes expensive preparation; enqueue only the actual finalized result without publishing it.
  if handoff.stage != AccumulationHandoffStage.Idle:
    return ApplicationCandidateResult(status: ApplicationCandidateError.Busy) # Pending/finished work is never replaced.
  let prepared = prepareCandidate(chain, candidate, ancestors, limits)
  if prepared.error != ApplicationCandidateError.None: return prepared # Failed prefixes leave the slot idle.
  let admitted = handoff.enqueue(chain, prepared.value, composition)
  if admitted != AccumulationEnqueueError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.EnqueueFailure,
        enqueueReason: admitted)
  prepared

type
  CurrentCandidateLimits* = object ## Freeze admission, queue/round, current completion and header capture ceilings at report preparation.
    reporting*: BlockReportConfig   ## Existing authenticated block/report prefix policy.
    queue*: AccumulationQueueConfig ## Existing original queue planning policy.
    round*: AccumulationRoundConfig ## Trusted initial gas configuration and local input ceilings.
    completion*: CurrentAccumulationCompletionLimits ## Current execution and complete state policies.
    serviceIdentities*: ServiceIdentityHistoryLimits ## Explicit selected creation/ejection retention; zero entries disables capture.
    requests*: RequestIdentityHistoryLimits ## Explicit selected producer request history; zero entries disables capture.
    storage*: StorageHistoryLimits ## Explicit producer raw-storage history retention; zero entries disables capture.
    headerBytes*: ByteLimit         ## Exact sealed child capture ceiling.
  CurrentCandidateError* {.pure.} = enum ## Every refusal preserves only the selected actual stage cause.
    Uninitialized, None, StateChanged, PrefixFailure, ReportFailure, QueueFailure, RoundFailure,
    CompletionFailure, PreparationFailure
  CurrentCandidateResult* = object ## Only complete execution/state/capture success returns a prepared current update.
    case status: CurrentCandidateError
    of None: completed: PreparedCurrentChainUpdate
    of PrefixFailure: prefixReason: ApplicationCandidateResult
    of ReportFailure: reportReason: ReportAdmissionResult[AdmittedReports]
    of QueueFailure: queueReason: AccumulationQueueError
    of RoundFailure: roundReason: AccumulationRoundError
    of CompletionFailure: completionReason: CurrentAccumulationCompletionResult
    of PreparationFailure: preparationReason: CurrentChainPreparationResult
    else: discard # Defaults and stale ownership expose no successful report or state prefix.
  PreparedCurrentCandidateReports* = object ## Current policy and genuine shared report prefix are private immutable owned copies.
    prefix: PreparedCandidateReports
    limits: CurrentCandidateLimits
  CurrentCandidatePreparation* = object ## Preparation alone grants report lookup, never execution or adoption authority.
    case successful: bool
    of true: prepared: PreparedCurrentCandidateReports
    else: refusal: CurrentCandidateResult
func error*(outcome: CurrentCandidateResult): CurrentCandidateError =
  ## Inspect the selected complete-candidate stage without mutable discriminator access.
  outcome.status
func value*(outcome: CurrentCandidateResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == CurrentCandidateError.None.} =
  ## Extract only the exact captured current update after every state phase succeeds.
  outcome.completed
func prefixFailure*(outcome: CurrentCandidateResult): ApplicationCandidateResult {.inline,
    requires: outcome.status == CurrentCandidateError.PrefixFailure.} =
  ## Preserve only the actual common admission failure; legacy execution is never invoked.
  outcome.prefixReason
func reportFailure*(outcome: CurrentCandidateResult): ReportAdmissionResult[
    AdmittedReports] {.inline, requires: outcome.status == CurrentCandidateError.ReportFailure.} =
  ## Inspect only an actual report/ancestor completion refusal.
  outcome.reportReason
func queueError*(outcome: CurrentCandidateResult): AccumulationQueueError {.inline,
    requires: outcome.status == CurrentCandidateError.QueueFailure.} =
  ## Inspect only an actual original queue planning refusal.
  outcome.queueReason
func roundError*(outcome: CurrentCandidateResult): AccumulationRoundError {.inline,
    requires: outcome.status == CurrentCandidateError.RoundFailure.} =
  ## Inspect only an actual initial round planning refusal.
  outcome.roundReason
func completionFailure*(outcome: CurrentCandidateResult): CurrentAccumulationCompletionResult {.inline,
    requires: outcome.status == CurrentCandidateError.CompletionFailure.} =
  ## Preserve the actual failed current sequence/state builder, without any successful prefix.
  outcome.completionReason
func preparationFailure*(outcome: CurrentCandidateResult): CurrentChainPreparationResult {.inline,
    requires: outcome.status == CurrentCandidateError.PreparationFailure.} =
  ## Preserve the actual current state/header capture refusal.
  outcome.preparationReason
func ready*(prepared: PreparedCurrentCandidateReports): bool =
  ## Default current report prefixes grant no report or execution authority.
  prepared.prefix.valid
func error*(outcome: CurrentCandidatePreparation): CurrentCandidateError =
  ## Success grants a prefix only; default preparation remains an uninitialized refusal.
  if outcome.successful: CurrentCandidateError.None
  else: outcome.refusal.error # A failed preparation retains its original selected stage.
func value*(outcome: CurrentCandidatePreparation): PreparedCurrentCandidateReports {.inline,
    requires: outcome.successful.} =
  ## Extract only a genuinely prepared current report prefix and its frozen local policies.
  outcome.prepared
func failure*(outcome: CurrentCandidatePreparation): CurrentCandidateResult {.inline,
    requires: not outcome.successful.} =
  ## Inspect only a genuinely refused prefix preparation.
  outcome.refusal
proc prepareCurrentCandidateReports*(chain: ApplicationChain, candidate: OwnedBlock,
    limits: CurrentCandidateLimits): CurrentCandidatePreparation =
  ## Reuse authenticated block/report preparation without invoking the legacy execution/composition path.
  let shared = prepareCandidateReports(chain, candidate, ApplicationCandidateLimits(
      reporting: limits.reporting))
  if shared.error != ApplicationCandidateError.None:
    return CurrentCandidatePreparation(successful: false, refusal: CurrentCandidateResult(
      status: CurrentCandidateError.PrefixFailure, prefixReason: shared.failure))
  CurrentCandidatePreparation(successful: true, prepared: PreparedCurrentCandidateReports(
    prefix: shared.value, limits: limits))
proc currentCandidateLookupDemand*(prepared: PreparedCurrentCandidateReports,
    ancestors: openArray[OwnedHeader]): ReportAdmissionResult[ReportLookupDemand] =
  ## Original authenticated prefix supports bounded ancestor discovery without running current guests.
  candidateLookupDemand(prepared.prefix, ancestors)
proc completeCurrentReports(chain: ApplicationChain,
    prepared: PreparedCurrentCandidateReports,

reports: ReportAdmissionResult[AdmittedReports]): CurrentCandidateResult =
  ## Recheck exact original history before current sequence execution, full state composition and one private capture.
  let data = prepared.prefix.data
  if data == nil: return default(CurrentCandidateResult) # A default prefix has no original map/profile authority.
  if not sameChainView(data.original, chain.chainView):
    return CurrentCandidateResult(status: CurrentCandidateError.StateChanged)
  let limits = prepared.limits
  if reports.error != ReportAdmissionError.None:
    return CurrentCandidateResult(status: CurrentCandidateError.ReportFailure,
        reportReason: reports)
  let queue = planBlockAccumulationQueue(reports.value, limits.queue)
  if queue.error != AccumulationQueueError.None:
    return CurrentCandidateResult(status: CurrentCandidateError.QueueFailure,
        queueReason: queue.error)
  let round = planBlockInitialAccumulation(queue.value, limits.round)
  if round.error != AccumulationRoundError.None:
    return CurrentCandidateResult(status: CurrentCandidateError.RoundFailure,
        roundReason: round.error)
  let composed = runCurrentAccumulationCompletion(round.value, data.parameters, limits.completion)
  if composed.error != CurrentAccumulationCompletionError.None:
    return CurrentCandidateResult(status: CurrentCandidateError.CompletionFailure,
        completionReason: composed)
  let update = chain.prepareAccumulation(composed.value, limits.headerBytes, limits.storage,
      limits.requests, limits.serviceIdentities)
  if update.error != CurrentChainPreparationError.None:
    return CurrentCandidateResult(status: CurrentCandidateError.PreparationFailure,
        preparationReason: update)
  CurrentCandidateResult(status: CurrentCandidateError.None, completed: update.value)
proc completeCurrentCandidateReports*(chain: ApplicationChain,
    prepared: PreparedCurrentCandidateReports, ancestors: openArray[
        OwnedHeader]): CurrentCandidateResult =
  ## Keep ordinary full-header completion on its original authenticated preparation.
  let data = prepared.prefix.data
  if data == nil: return default(CurrentCandidateResult)
  if not sameChainView(data.original, chain.chainView):
    return CurrentCandidateResult(status: CurrentCandidateError.StateChanged) # Preserve stale-prefix failure ordering.
  completeCurrentReports(chain, prepared, completeBlockReports(data.reports, ancestors))
proc prepareFuzzCurrentCandidate*(chain: ApplicationChain, candidate: OwnedBlock,
    context: FuzzAncestry, limits: CurrentCandidateLimits): CurrentCandidateResult =
  ## A fuzz-only view and retained origin are both mandatory; all GP checks and current execution remain active.
  if not chain.chainView.fuzzOnly:
    return CurrentCandidateResult(status: CurrentCandidateError.StateChanged)
  let prepared = prepareCurrentCandidateReports(chain, candidate, limits)
  if prepared.error != CurrentCandidateError.None: return prepared.failure
  let data = prepared.value.prefix.data
  if data == nil: return default(CurrentCandidateResult) # Only the actual successful prefix can complete.
  completeCurrentReports(chain, prepared.value, completeFuzzBlockReports(data.reports, context))
proc prepareCurrentCandidate*(chain: ApplicationChain, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: CurrentCandidateLimits): CurrentCandidateResult =
  ## One-shot consumers use the same original prefix and current-only completion without publishing any head.
  let prepared = prepareCurrentCandidateReports(chain, candidate, limits)
  if prepared.error != CurrentCandidateError.None: return prepared.failure
  completeCurrentCandidateReports(chain, prepared.value, ancestors)
