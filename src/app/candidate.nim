# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare finalized successors from owned blocks against the selected complete-map application head.
## Existing state/PVM stages retain authority; private prefixes never publish until a later handoff tick.

import ./[chain, handoff]
import ../chain/[genesis, provider, parameters]
import ../codec/[block_codec, header]
import ../state/[store, block_transition, report_transition, report_admission, accumulation_queue,
  accumulation_round, accumulation_runner, accumulation_driver, accumulation_finalization,
  accumulation_outputs, accumulation_completion, report_anchors]

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
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) != uint64(head.activeValidators) or
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
  let staged = advanceBlockState(working, candidate, head.header, config.admission,
    config.disputes, config.safrole, config.availability)
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
