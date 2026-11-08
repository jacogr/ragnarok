# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Qualify one genuinely computed report against its original execution and a fresh canonical inclusion view before signing.
## The private capability binds exact provenance, anchor window, GP policy/pipeline, TLS identity and actual assigned roster index.

import ./[work_submission, work_report, work_anchors, work_population, work_duty]
import ../chain/[provider, genesis, parameters]
import ../codec/[bounded, report_owned, owned, guarantees]
import ../codec/work/report
import ../codec/state/[safrole, consensus]
import ../state/store
import ../state/report/[policy, packages]
import ../state/computed/[report as computed_report, guarantee as computed_guarantee]
import ../crypto/guarantee

type
  WorkEligibilityLimits* = object ## Explicit independent child budgets cannot alter the selected chain's consensus gas or geometry.
    anchors*: WorkAnchorLimits
    population*: SafroleStateConfig
    duty*: WorkDutyLimits
    policy*: ReportPolicyConfig
    pipeline*: ReportPackageConfig
    reportBytes*: ByteLimit ## Total scratch wire plus retained raw-report wire; preflight precedes either copy.
  WorkEligibilityError* {.pure.} = enum ## Default/refused alternatives expose neither a signing capability nor an accepted prefix.
    Uninitialized, None, InvalidSource, InvalidPolicy, LimitExceeded, InvalidShards,
    AnchorFailure, PopulationFailure, DutyFailure, DecodeFailure, PolicyFailure, PipelineFailure
  WorkEligibilityInfo* = object ## Public fixed copies explain the source and credential; none can construct the private capability.
    head*: genesis.BlockHash
    inclusion*: StateTime
    slot*: GuaranteeSlot
    validator*: GuarantorIndex
    identity*: StateEdKey
    core*: CoreIndex
  EligibleWorkData = ref object ## Immutable acyclic ownership retains exactly the computed transcript and its decoded canonical report.
    transcript: ComputedGuaranteeTranscript
    report: OwnedReport
    info: WorkEligibilityInfo
    duty: WorkDuty
  EligibleWorkGuarantee* = object ## Only complete original/fresh-source qualification can produce a signing input.
    data: nil EligibleWorkData
  WorkEligibilityResult*[T] = object ## Selected failures preserve actual child causes; success alone carries qualified ownership.
    case status: WorkEligibilityError
    of None: completed: T
    of AnchorFailure: anchorReason: WorkAnchorResult[AnchoredWorkContext]
    of PopulationFailure: populationReason: WorkPopulationResult[WorkShardWindow]
    of DutyFailure: dutyReason: WorkDutyResult[WorkDuty]
    of DecodeFailure: decodeReason: OwnershipError
    of PolicyFailure: policyReason: ReportPolicyError
    of PipelineFailure: pipelineReason: ReportPackageError
    else: discard # Local refusals cannot synthesize a failed child or usable transcript.

func error*[T](outcome: WorkEligibilityResult[T]): WorkEligibilityError =
  ## Read a refusal without permitting discriminator mutation.
  outcome.status

func value*[T](outcome: WorkEligibilityResult[T]): T {.requires: outcome.status ==
    WorkEligibilityError.None.} =
  ## Extract only a fully qualified input or copied fact.
  outcome.completed

func anchorError*[T](outcome: WorkEligibilityResult[T]): WorkAnchorResult[
    AnchoredWorkContext] {.requires: outcome.status == WorkEligibilityError.AnchorFailure.} =
  ## Preserve the original exact context qualification failure.
  outcome.anchorReason

func populationError*[T](outcome: WorkEligibilityResult[T]): WorkPopulationResult[
    WorkShardWindow] {.requires: outcome.status == WorkEligibilityError.PopulationFailure.} =
  ## Preserve an unavailable or unestablished population window without guessing a roster.
  outcome.populationReason

func dutyError*[T](outcome: WorkEligibilityResult[T]): WorkDutyResult[
    WorkDuty] {.requires: outcome.status == WorkEligibilityError.DutyFailure.} =
  ## Preserve the genuine assignment/TLS-key refusal.
  outcome.dutyReason

func decodeError*[T](outcome: WorkEligibilityResult[
    T]): OwnershipError {.requires: outcome.status == WorkEligibilityError.DecodeFailure.} =
  ## Preserve only an actual canonical report decoder error.
  outcome.decodeReason

func policyError*[T](outcome: WorkEligibilityResult[
    T]): ReportPolicyError {.requires: outcome.status == WorkEligibilityError.PolicyFailure.} =
  ## GP service/gas/authorizer refusals remain distinct from context and package relations.
  outcome.policyReason

func pipelineError*[T](outcome: WorkEligibilityResult[
    T]): ReportPackageError {.requires: outcome.status == WorkEligibilityError.PipelineFailure.} =
  ## Preserve the actual state-backed uniqueness/dependency/root failure.
  outcome.pipelineReason

proc eligibilityInfo*(qualified: EligibleWorkGuarantee): WorkEligibilityResult[
    WorkEligibilityInfo] =
  ## Copy fixed checked facts only; defaults grant no all-zero credential identity.
  let data = qualified.data
  if data == nil: return WorkEligibilityResult[WorkEligibilityInfo](
      status: WorkEligibilityError.Uninitialized)
  WorkEligibilityResult[WorkEligibilityInfo](status: WorkEligibilityError.None,
      completed: data.info)

proc eligibleDuty*(qualified: EligibleWorkGuarantee): WorkEligibilityResult[WorkDuty] =
  ## The complete copied cohort belongs to the exact fresh-source qualification, not the older execution or packet claims.
  let data = qualified.data
  if data == nil: return default(WorkEligibilityResult[WorkDuty])
  WorkEligibilityResult[WorkDuty](status: WorkEligibilityError.None, completed: data.duty)

proc eligibleTranscript*(qualified: EligibleWorkGuarantee): WorkEligibilityResult[
    ComputedGuaranteeTranscript] =
  ## Retain the exact privately bound computed transcript; callers cannot replace any part of the capability.
  let data = qualified.data
  if data == nil: return WorkEligibilityResult[ComputedGuaranteeTranscript](
      status: WorkEligibilityError.Uninitialized)
  WorkEligibilityResult[ComputedGuaranteeTranscript](status: WorkEligibilityError.None,
      completed: data.transcript)

proc eligibleReport*(qualified: EligibleWorkGuarantee): WorkEligibilityResult[OwnedReport] =
  ## Share the immutable report decoded from that transcript, never a caller-supplied substitute.
  let data = qualified.data
  if data == nil: return WorkEligibilityResult[OwnedReport](
      status: WorkEligibilityError.Uninitialized)
  WorkEligibilityResult[OwnedReport](status: WorkEligibilityError.None, completed: data.report)

proc eligibleMessage*(qualified: EligibleWorkGuarantee): WorkEligibilityResult[GuaranteeMessage] =
  ## Copy only the GP transcript of the fully checked report for the private signer.
  let data = qualified.data
  if data == nil: return WorkEligibilityResult[GuaranteeMessage](
      status: WorkEligibilityError.Uninitialized)
  WorkEligibilityResult[GuaranteeMessage](status: WorkEligibilityError.None,
    completed: data.transcript.computedGuaranteeMessage.value)

proc qualifyWorkGuarantee*(transcript: ComputedGuaranteeTranscript,
    original: WorkSubmissionHeader, executionState: StateStoreSnapshot, view: ChainView,
    local: StateEdKey, now: StateTime, limits: WorkEligibilityLimits): WorkEligibilityResult[
        EligibleWorkGuarantee] =
  ## Execute entirely under one managed graph lease; the host supplies actual transport identity and clock observation.
  ## Original execution and fresh inclusion maps are intentionally separate; historical execution is deterministic under the GP.
  template fail(reason: WorkEligibilityError) =
    return WorkEligibilityResult[EligibleWorkGuarantee](status: reason)
  let head = view.bestBlock
  if head.error != GenesisError.None: fail(WorkEligibilityError.InvalidSource)
  let parameters = head.value.chainParameters
  if not transcript.workReportMatches(original, executionState, parameters):
    fail(WorkEligibilityError.InvalidSource)
  let cores = parameters.get(coreCount)
  let sameCorePolicy = uint64(limits.policy.pools.cores) == cores
  let sameQueuePolicy = uint64(limits.pipeline.queues.cores) == cores and
    uint64(limits.pipeline.queues.epochSlots) == parameters.get(epochPeriod)
  let sameGas = uint64(limits.policy.reportGas) == parameters.get(maxAccumulateGas) and
    uint64(limits.policy.refinementGas) == parameters.get(maxRefineGas)
  if not sameCorePolicy or not sameQueuePolicy or not sameGas:
    fail(WorkEligibilityError.InvalidPolicy)
  let anchored = captureWorkAnchors(original, view, now, limits.anchors)
  if anchored.error != WorkAnchorError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](status: WorkEligibilityError.AnchorFailure,
      anchorReason: anchored)
  let population = captureWorkPopulation(anchored.value, original, view, limits.population)
  if population.error != WorkPopulationError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](
      status: WorkEligibilityError.PopulationFailure,
      populationReason: population)
  let computed = transcript.computedGuaranteeReport.value
  let facts = computed.computedReportInfo.value
  if not population.value.accepts(facts.header.erasureShards, facts.core): fail(
      WorkEligibilityError.InvalidShards)
  let duty = captureWorkDuty(head.value.stateSnapshot, parameters, workRecipient(local, now),
    facts.core, limits.duty)
  if duty.error != WorkDutyError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](status: WorkEligibilityError.DutyFailure,
      dutyReason: duty)
  if facts.length > uint64(limits.reportBytes) div 2: fail(WorkEligibilityError.LimitExceeded)
  let wire = computed.computedReportBytes.value
  let decoded = decodeOwnedReport(wire, cores)
  if decoded.error != OwnershipError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](status: WorkEligibilityError.DecodeFailure,
      decodeReason: decoded.error)
  if decoded.value.ownedReportInfo.value.consumed != wire.len: fail(
      WorkEligibilityError.InvalidSource)
  let policy = inspectReportPolicy(decoded.value, head.value.stateSnapshot, limits.policy)
  if policy != ReportPolicyError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](status: WorkEligibilityError.PolicyFailure,
      policyReason: policy)
  let pipeline = inspectReportPipeline([decoded.value], head.value.stateSnapshot,
    anchored.value.workAnchorHistory.value, limits.pipeline)
  if pipeline != ReportPackageError.None:
    return WorkEligibilityResult[EligibleWorkGuarantee](
      status: WorkEligibilityError.PipelineFailure,
      pipelineReason: pipeline)
  WorkEligibilityResult[EligibleWorkGuarantee](status: WorkEligibilityError.None,
    completed: EligibleWorkGuarantee(data: EligibleWorkData(transcript: transcript,
      report: decoded.value, duty: duty.value,
      info: WorkEligibilityInfo(head: head.value.blockHash,
        inclusion: anchored.value.anchorInfo.value.inclusionSlot,
        slot: GuaranteeSlot(uint32(now)), validator: duty.value.validatorIndex,
        identity: duty.value.localIdentity, core: duty.value.core))))
