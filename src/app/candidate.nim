# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare finalized successors from owned blocks against the selected complete-map application head.
## Existing state/PVM stages retain authority; private prefixes never publish until a later handoff tick.

import ./[chain, handoff]
import ../chain/[genesis, provider]
import ../codec/[block_codec, header]
import ../state/[store, block_transition, report_transition, report_admission, accumulation_queue,
  accumulation_round, accumulation_runner, accumulation_driver, accumulation_finalization,
  accumulation_outputs, accumulation_completion]

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
    FinalizationFailure, EnqueueFailure
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

proc prepareCandidate*(chain: ApplicationChain, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits): ApplicationCandidateResult =
  ## Execute existing implemented stages privately with parent/header/parameters selected from this exact canonical head.
  ## Preparation is synchronous and belongs outside transport callbacks; only later adoption is dispatched.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.MissingHead) # No implicit empty parent.
  let head = selected.value
  let frame = limits.reporting.admission.frame
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) != uint64(head.activeValidators) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return ApplicationCandidateResult(status: ApplicationCandidateError.ProfileMismatch) # Reject unrelated chain domains before native work.
  let current = chain.stateSnapshot
  if current.error != StateStoreError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.StateFailure,
        stateReason: current.error)
  let forked = forkStateStore(current.value)
  if forked.error != StateStoreError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.StateFailure,
        stateReason: forked.error)
  var working = forked.value
  let config = limits.reporting
  let staged = advanceBlockState(working, candidate, head.header, config.admission,
    config.disputes, config.safrole, config.availability)
  if staged.error != BlockTransitionError.None:
    return ApplicationCandidateResult(status: ApplicationCandidateError.BlockFailure,
      blockReason: staged) # Prefix publication affects only the private fork.
  let reports = planBlockReports(staged, ancestors, config.reports)
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
  let parameters = head.chainParameters
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
