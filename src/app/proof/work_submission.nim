# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed work-submission and guarantee-exchange CPU jobs retain original provenance under the shared graph lease.
## All aliases, including completed authorization and refinement, remain untouched until exact collection or joined stop.
import ../../jamnp-s/work_submission
import ../../jamnp-s/work_duty
import ../../jamnp-s/work_report
import ../../jamnp-s/[work_signer, work_eligibility, work_sharing, sharing_wire, work_guarantee]
import ../../jamnp-s/assurance_distribution
import ../../jamnp-s/assurance_fetch
import ../../jamnp-s/assurance_schedule
import ../../jamnp-s/[audits, audit_validation, endpoints]
from ../../codec/assurances import ValidatorCount
import ./ticket_production
from ../../codec/disputes import JudgeIndex
import ../../jamnp-s/[audit_context, audit_receipt, audit_origin, audit_evaluation, audit_recovery,
    audit_fetch, judgment_claim, judgment_receipt, audit_participation, audit_publication]
from ../../jamnp-s/assurance_store import AssuranceScanControl, stopped
import ../../jamnp-s/work_recovery
import ../../jamnp-s/availability_proof
import ../../jamnp-s/[work_distribution, read_stream, read_validation]
import ../../codec/[report_owned, owned]
import ../../chain/[provider, genesis]
import ../../codec/bounded
from ../../codec/state/safrole import StateValidatorIndex, StateEdKey, StateTime, nullValidator
from ../../state/computed/guarantee import ComputedGuaranteeTranscript
from ../../codec/work/report import ErasureShards
import ../../state/[store, input_refinement, authorized_refinement]
import ../../state/report/identity
import ../../state/authorization/invocation
import "../../state/import/inputs" as import_inputs
import "../../state/import/justification" as import_justification
import ../../codec/work/report as work_report
import ../../chain/parameters

type
  WorkJobError* {.pure.} = enum ## Local capture refusals contain no source-bearing input capability.
    Uninitialized, None, InvalidInput, LimitExceeded
  WorkJobResultKind* {.pure.} = enum ## A completed CPU turn exposes only its selected full success or genuine child failure.
    Uninitialized, Authorized, Refined, InvalidSource, AuthorizationFailure, BodyFailure,
    RefinementFailure, DutyFailure, Reported, ReportFailure, ImportPlanningFailure,
    RecoveryUpdated, RecoveryFailure, RecoveryCompletionFailure, Contributed,
    EligibilityFailure, SigningFailure, SharingFailure, ExchangePrepared,
    ExchangePreparationFailure, PeerAccepted, PeerResponseFailure, GuaranteeCollected,
    GuaranteeCollectionFailure, DistributionQualified, DistributionFailure,
    DistributionEncodingFailure, DistributionCacheFailure, DistributionOutputLimit,
    AssuranceQualified, AssuranceFailure, AssurancePlanned, AssurancePlanningFailure,
    AssuranceScheduled, AssuranceScheduleFailure, AuditPlanned, AuditPlanningFailure,
      AuditAnnouncementsQualified, AuditAnnouncementFailure, AuditOriginPrepared,
    AuditOriginPreparationFailure, AuditEvaluated, AuditEvaluationFailure, AuditRecoveryFailure,
    AuditSigned, AuditSigningFailure, AuditFetchPlanned, AuditFetchPlanningFailure,
    AuditShardVerified, AuditShardVerificationFailure, JudgmentClaimsVerified, JudgmentClaimFailure,
      JudgmentReceiptPrepared, JudgmentReceiptFailure, AuditParticipationPlanned,
        AuditParticipationFailure, AuditPublicationPrepared, AuditPublicationFailure,
    InitialAuditProduced, InitialAuditSourceFailure, InitialAuditSigningFailure,
    InitialAuditEncodingFailure, InitialAuditNoDuty
  WorkSource = ref object ## Immutable acyclic provenance retains the exact original complete map, package header and policy.
    header: WorkSubmissionHeader
    state: StateStoreSnapshot
    parameters: Parameters
    limits: WorkSubmissionLimits
    execution: InputRefinementLimits
    recipient: WorkRecipient
    dutyLimits: WorkDutyLimits
    view: ChainView
    recovery: WorkRecoveryPolicy
  WorkContextData = ref object ## A real successful grant cannot be rebound to another source or execution policy.
    source: WorkSource
    grant: AuthorizedWorkSubmission
    duty: WorkDuty
    imports: WorkImportPlan
    recovery: WorkRecovery
  AuthorizedWorkContext* = object ## Only a successful private CPU capability can construct a usable context.
    data: nil WorkContextData
  InitialAuditRecipient* = object ## One physical original auditor and its optional advertised endpoint.
    identity*: StateEdKey
    endpoint*: EndpointResult
  ProducedInitialAudit* = object ## Detached wire record and exact selected cores survive collection without retaining chain ownership.
    announcement*: AuditAnnouncement
    epoch*: uint64
    selected*: InitialAuditSelection
    reportOrdinals*: array[10, int]
    request*: ReadRequest
    recipients*: seq[InitialAuditRecipient]
  WorkJobResult* = object ## Failed/default results expose no input, grant, partial refinement or unrelated child.
    case status: WorkJobResultKind
    of RecoveryUpdated: recovered: WorkRecovery
    of RecoveryFailure: recoveryReason: WorkRecoveryResult[WorkRecovery]
    of RecoveryCompletionFailure: recoveryCompletionReason: WorkRecoveryResult[VerifiedImportInputs]
    of ImportPlanningFailure: planningReason: WorkSubmissionResult[WorkImportPlan]
    of SharingFailure: sharingReason: WorkSharingResult[SignedWorkContribution]
    of ExchangePrepared:
      preparedRequest: SharedWorkRequest
      preparedRound: WorkGuaranteeRound
      preparedTargets: array[2, WorkShareTarget]
      preparedCount: int
    of ExchangePreparationFailure: exchangeReason: WorkSharingResult[SharedWorkRequest]
    of PeerAccepted: acceptedRound: WorkGuaranteeRound
    of PeerResponseFailure: peerReason: WorkGuaranteeResult[WorkGuaranteeRound]
    of GuaranteeCollected: collected: CollectedWorkGuarantee
    of GuaranteeCollectionFailure: collectionReason: WorkGuaranteeResult[CollectedWorkGuarantee]
    of InitialAuditProduced: initialAudit: ProducedInitialAudit
    of InitialAuditSourceFailure: initialAuditSourceReason: AuditContextError
    of InitialAuditSigningFailure: initialAuditSigningReason: AuditValidationError
    of AuditOriginPrepared: auditOrigin: AuditBlockOrigin
    of AuditOriginPreparationFailure: auditOriginReason: AuditOriginResult[AuditBlockOrigin]
    of AuditRecoveryFailure: auditRecoveryReason: AuditRecoveryResult[AuditRecoveryEvidence]
    of AuditPublicationPrepared: auditPublication: AuditPublication
    of AuditPublicationFailure: auditPublicationReason: AuditPublicationResult[AuditPublication]
    of AuditParticipationPlanned: auditParticipation: AuditParticipationPlan
    of AuditParticipationFailure: auditParticipationReason: AuditParticipationResult[AuditParticipationPlan]
    of JudgmentReceiptPrepared: judgmentReceipt: PreparedJudgmentBatch
    of JudgmentReceiptFailure: judgmentReceiptReason: JudgmentReceiptResult[PreparedJudgmentBatch]
    of JudgmentClaimsVerified: judgmentClaims: SignedJudgmentBatch
    of JudgmentClaimFailure: judgmentClaimReason: JudgmentClaimResult[SignedJudgmentBatch]
    of AuditShardVerified: auditShard: VerifiedAvailabilityTransfer
    of AuditShardVerificationFailure: auditShardReason: AuditFetchResult[VerifiedAvailabilityTransfer]
    of AuditFetchPlanned: auditFetch: AuditFetchPlan
    of AuditFetchPlanningFailure: auditFetchReason: AuditFetchResult[AuditFetchPlan]
    of AuditSigned: auditSigned: SignedAuditJudgment
    of AuditSigningFailure: auditSigningReason: AuditSigningResult[SignedAuditJudgment]
    of AuditEvaluated: auditEvaluation: AuditEvaluation
    of AuditEvaluationFailure: auditEvaluationReason: AuditEvaluationResult[AuditEvaluation]
    of AuditAnnouncementsQualified: auditBatch: CheckedAuditBatch
    of AuditAnnouncementFailure: auditReceiptReason: AuditReceiptResult[CheckedAuditBatch]
    of AuditPlanned: auditContext: AuditContext
    of AuditPlanningFailure: auditReason: AuditContextResult[AuditContext]
    of AssuranceScheduled: assuranceSchedule: AssuranceSchedule
    of AssuranceScheduleFailure: assuranceScheduleReason: AssuranceScheduleResult[AssuranceSchedule]
    of AssurancePlanned: assurancePlan: AssuranceFetchPlan
    of AssurancePlanningFailure: assurancePlanReason: AssuranceFetchResult[AssuranceFetchPlan]
    of AssuranceQualified: assured: CheckedAssurance
    of AssuranceFailure: assuranceReason: AssuranceDistributionResult[CheckedAssurance]
    of DistributionQualified:
      distributed: CheckedWorkDistribution
      distributionReport: CheckedReadReply
    of DistributionFailure: distributionReason: WorkDistributionResult[CheckedWorkDistribution]
    of DistributionEncodingFailure: distributionEncodingReason: OwnershipError
    of DistributionCacheFailure: distributionCacheReason: ReadVerificationResult[CheckedReadReply]
    of Contributed: contribution: SignedWorkContribution
    of EligibilityFailure: eligibilityReason: WorkEligibilityResult[EligibleWorkGuarantee]
    of SigningFailure: signingReason: WorkSignerResult[SignedWorkContribution]
    of Reported: report: ComputedGuaranteeTranscript
    of ReportFailure: reportReason: WorkReportResult
    of DutyFailure: dutyReason: WorkDutyResult[WorkDuty]
    of Authorized: context: AuthorizedWorkContext
    of Refined: execution: InputRefinement
    of AuthorizationFailure: authorizationReason: WorkSubmissionResult[AuthorizedWorkSubmission]
    of BodyFailure: bodyReason: WorkSubmissionResult[VerifiedImportInputs]
    of RefinementFailure: refinementReason: InputRefinementResult[InputRefinement]
    else: discard # Defaults contain neither selected-state ownership nor an invented success.
  WorkRunner = proc(data: WorkJobData): WorkJobResult {.nimcall.}
    ## Closed capability is bound only to the actual implementation in this module.
  CancellableWorkRunner = proc(data: WorkJobData, control: AssuranceScanControl): WorkJobResult {.nimcall.}
    ## Only private closed factories select this runner; live cancellation control is supplied at execution and is never stored in a queued job.
  WorkJobData = ref object ## Detached bounded bytes accompany immutable selected-state owners; no stream pointer crosses the CPU boundary.
    run: nil WorkRunner
    cancellable: nil CancellableWorkRunner
    auditBandersnatch: TicketSigner
    auditInitialOrdinal: JudgeIndex
    auditDiscoverOrdinal: bool
    auditProofLimits: AuditProofLimits
    auditView: ChainView
    auditAlternatives: seq[ChainView]
    auditHash: genesis.BlockHash
    auditLimits: AuditContextLimits
    auditWire: seq[byte]
    auditReceiptLimits: AuditReceiptLimits
    auditOriginLimits: AuditOriginLimits
    auditTarget: AuditReportOrigin
    auditFetchPlan: AuditFetchPlan
    auditFetchOrdinal: int
    auditFetchTransferLimits: AvailabilityMerkleLimits
    judgmentClaimLimits: JudgmentClaimLimits
    judgmentClaims: SignedJudgmentBatch
    judgmentInputs: seq[JudgmentSourceInput]
    judgmentReceiptLimits: JudgmentReceiptLimits
    auditPublicationLimits: AuditPublicationLimits
    auditRoutingBasis: AuditRoutingBasis
    auditParticipationLimits: AuditParticipationLimits
    auditParticipationCurrent: BlockSnapshotResult
    auditParticipationIdentity: StateEdKey
    auditFetchLimits: AuditFetchLimits
    auditEvaluationLimits: AuditEvaluationLimits
    auditPackets: seq[VerifiedAvailabilityTransfer]
    auditRecoveryLimits: AuditRecoveryLimits
    auditEvaluation: AuditEvaluation
    auditValidator: StateValidatorIndex
    source: WorkSource
    context: AuthorizedWorkContext
    refined: InputRefinement
    shards: ErasureShards
    reportLimits: WorkReportLimits
    signer: WorkSigner
    transcript: ComputedGuaranteeTranscript
    signingView: ChainView
    signingLimits: WorkEligibilityLimits
    retentionLimits: AvailabilityMerkleLimits
    retainedSources: seq[GuarantorAvailability]
    signingIdentity: StateEdKey
    signingTime: StateTime
    assuranceSource: BlockSnapshotResult
    assurancePeer: StateEdKey
    assuranceLimits: AssuranceDistributionLimits
    assuranceFetchLimits: AssuranceFetchLimits
    assuranceScheduleLimits: AssuranceScheduleLimits
    assuranceWindow: AssuranceWindow
    distributionRequest: ReadRequest
    distributionView: ChainView
    distributionLimits: WorkDistributionLimits
    distributionTime: StateTime
    sharingRequest: SharedWorkRequest
    sharingPeer: StateEdKey
    sharingLimits: WorkSharingLimits
    contribution: SignedWorkContribution
    round: WorkGuaranteeRound
    target: WorkShareTarget
    response: array[96, byte]
    exchangeBytes: ByteLimit
    recovery: WorkRecovery
    recoveryVersion: uint64
    validator: StateValidatorIndex
    fetched: bool
    extrinsics, segments, proofs: seq[byte]
    imports: seq[seq[VerifiedImport]]
    lookup: seq[SegmentLookup]
  WorkSubmissionJob* = object ## Default jobs have no executable source or private runner.
    data: nil WorkJobData
  WorkJobAdmission* = object ## Only complete capture carries an executable job.
    case status: WorkJobError
    of None: completed: WorkSubmissionJob
    else: discard            # No captured prefix escapes refusal.
func workJobFailure*(reason: WorkJobError): WorkJobAdmission {.requires: reason !=
    WorkJobError.None.} =
  ## Closed boundary composition can preserve a real capture refusal without constructing an executable runner.
  WorkJobAdmission(status: reason)
func error*(outcome: WorkJobAdmission): WorkJobError =
  ## Inspect local capture status before selecting a job.
  outcome.status
func value*(outcome: WorkJobAdmission): WorkSubmissionJob {.requires: outcome.status ==
    WorkJobError.None.} =
  ## Capture grants execution-input authority, never successful authorization or refinement.
  outcome.completed
func kind*(outcome: WorkJobResult): WorkJobResultKind =
  ## Scalar observations retain no canonical graph alias.
  outcome.status
func exchangeRequest*(outcome: WorkJobResult): SharedWorkRequest {.requires: outcome.status ==
    WorkJobResultKind.ExchangePrepared.} =
  ## Extract only independent raw prepared bytes, after exact worker collection and before admitting another graph borrower.
  outcome.preparedRequest
func exchangeRound*(outcome: WorkJobResult): WorkGuaranteeRound {.requires: outcome.status in {
    WorkJobResultKind.ExchangePrepared, WorkJobResultKind.PeerAccepted}.} =
  ## Private credential ownership remains frozen through every subsequent worker lease.
  if outcome.status == WorkJobResultKind.ExchangePrepared: outcome.preparedRound else: outcome.acceptedRound
func exchangeTargets*(outcome: WorkJobResult): array[2,
    WorkShareTarget] {.requires: outcome.status == WorkJobResultKind.ExchangePrepared.} =
  ## Fixed source-bound target copies remain safe for native control without canonical graph access.
  outcome.preparedTargets
func exchangeTargetCount*(outcome: WorkJobResult): int {.requires: outcome.status ==
    WorkJobResultKind.ExchangePrepared.} =
  ## Only the selected prefix contains actual remote targets; null or local cohort positions are excluded.
  outcome.preparedCount
func exchangePreparationError*(outcome: WorkJobResult): WorkSharingResult[
    SharedWorkRequest] {.requires: outcome.status ==
    WorkJobResultKind.ExchangePreparationFailure.} =
  ## Preserve the genuine outgoing bundle preparation refusal without a prepared prefix.
  outcome.exchangeReason
func peerResponseError*(outcome: WorkJobResult): WorkGuaranteeResult[
    WorkGuaranteeRound] {.requires: outcome.status == WorkJobResultKind.PeerResponseFailure.} =
  ## Rejected signatures preserve their precise reason and never replace the previous accepted round.
  outcome.peerReason
func collectedGuarantee*(outcome: WorkJobResult): CollectedWorkGuarantee {.requires: outcome.status ==
    WorkJobResultKind.GuaranteeCollected.} =
  ## Two/three genuine credentials produced this owner; no fresh block-admission or distribution promise is implied.
  outcome.collected
func guaranteeCollectionError*(outcome: WorkJobResult): WorkGuaranteeResult[
    CollectedWorkGuarantee] {.requires: outcome.status ==
    WorkJobResultKind.GuaranteeCollectionFailure.} =
  ## Preserve actual threshold/byte/codec refusal without a completed guarantee.
  outcome.collectionReason
func preparedAuditPublication*(outcome: WorkJobResult): AuditPublication {.requires: outcome.status ==
    WorkJobResultKind.AuditPublicationPrepared.} =
  ## Only complete original-key signing and independent serving bytes leave the private worker.
  outcome.auditPublication
func auditPublicationError*(outcome: WorkJobResult): AuditPublicationResult[
    AuditPublication] {.requires: outcome.status == WorkJobResultKind.AuditPublicationFailure.} =
  ## A genuine failed local publication contains no signature or raw report prefix.
  outcome.auditPublicationReason
func plannedAuditParticipation*(outcome: WorkJobResult): AuditParticipationPlan {.requires: outcome.status ==
    WorkJobResultKind.AuditParticipationPlanned.} =
  ## Source-free original roles and recipients retain no canonical map or signer alias.
  outcome.auditParticipation
func auditParticipationError*(outcome: WorkJobResult): AuditParticipationResult[
    AuditParticipationPlan] {.requires: outcome.status ==
    WorkJobResultKind.AuditParticipationFailure.} =
  ## Preserve actual missing/policy/cancellation metadata refusal without a recipient prefix.
  outcome.auditParticipationReason
func preparedJudgmentReceipt*(outcome: WorkJobResult): PreparedJudgmentBatch {.requires: outcome.status ==
    WorkJobResultKind.JudgmentReceiptPrepared.} =
  ## This source-bearing result belongs exclusively to the exact private managed audit collector.
  outcome.judgmentReceipt
func judgmentReceiptError*(outcome: WorkJobResult): JudgmentReceiptResult[
    PreparedJudgmentBatch] {.requires: outcome.status ==
    WorkJobResultKind.JudgmentReceiptFailure.} =
  ## Preserve only the genuine whole-receipt failure, with no successful prefix.
  outcome.judgmentReceiptReason
func verifiedJudgmentClaims*(outcome: WorkJobResult): SignedJudgmentBatch {.requires: outcome.status ==
    WorkJobResultKind.JudgmentClaimsVerified.} =
  ## Whole original-key claims are source-free, while negative inline guarantees still require private report/role qualification.
  outcome.judgmentClaims
func judgmentClaimError*(outcome: WorkJobResult): JudgmentClaimResult[
    SignedJudgmentBatch] {.requires: outcome.status == WorkJobResultKind.JudgmentClaimFailure.} =
  ## Preserve actual whole-batch policy, epoch, signature and source refusal without any accepted prefix.
  outcome.judgmentClaimReason
func verifiedAuditShard*(outcome: WorkJobResult): VerifiedAvailabilityTransfer {.requires: outcome.status ==
    WorkJobResultKind.AuditShardVerified.} =
  ## This source-free proof owner still requires exact private target binding and threshold reconstruction before judgment evaluation.
  outcome.auditShard
func auditShardVerificationError*(outcome: WorkJobResult): AuditFetchResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status ==
    WorkJobResultKind.AuditShardVerificationFailure.} =
  ## A malformed transcript, quota or genuine proof refusal never becomes report-invalid authority.
  outcome.auditShardReason
func plannedAuditFetch*(outcome: WorkJobResult): AuditFetchPlan {.requires: outcome.status ==
    WorkJobResultKind.AuditFetchPlanned.} =
  ## Only source-free detached routing escapes the exact worker collection boundary.
  outcome.auditFetch
func auditFetchPlanningError*(outcome: WorkJobResult): AuditFetchResult[
    AuditFetchPlan] {.requires: outcome.status == WorkJobResultKind.AuditFetchPlanningFailure.} =
  ## Preserve actual missing roster, quota or source refusal without an accepted target prefix.
  outcome.auditFetchReason
func preparedAuditOrigin*(outcome: WorkJobResult): AuditBlockOrigin {.requires: outcome.status ==
    WorkJobResultKind.AuditOriginPrepared.} =
  ## Full source-bearing origin aliases remain frozen whenever this result or a later registered target is borrowed by native work.
  outcome.auditOrigin
func auditOriginPreparationError*(outcome: WorkJobResult): AuditOriginResult[
    AuditBlockOrigin] {.requires: outcome.status ==
    WorkJobResultKind.AuditOriginPreparationFailure.} =
  ## Failed whole-origin preparation contains no retained state or partially qualified report target.
  outcome.auditOriginReason
func signedAudit*(outcome: WorkJobResult): SignedAuditJudgment {.requires: outcome.status ==
    WorkJobResultKind.AuditSigned.} =
  ## Completed source-free signed ownership retains no private key or evaluation graph.
  outcome.auditSigned
func auditSigningError*(outcome: WorkJobResult): AuditSigningResult[
    SignedAuditJudgment] {.requires: outcome.status == WorkJobResultKind.AuditSigningFailure.} =
  ## Preserve only the actual failed signing alternative.
  outcome.auditSigningReason
func auditRecoveryError*(outcome: WorkJobResult): AuditRecoveryResult[
    AuditRecoveryEvidence] {.requires: outcome.status == WorkJobResultKind.AuditRecoveryFailure.} =
  ## Reconstruction refusal carries no successfully authenticated prefix.
  outcome.auditRecoveryReason
func evaluatedAudit*(outcome: WorkJobResult): AuditEvaluation {.requires: outcome.status ==
    WorkJobResultKind.AuditEvaluated.} =
  ## Only actual complete report reproduction exposes its private source-bound evaluation capability.
  outcome.auditEvaluation
func auditEvaluationError*(outcome: WorkJobResult): AuditEvaluationResult[
    AuditEvaluation] {.requires: outcome.status == WorkJobResultKind.AuditEvaluationFailure.} =
  ## Direct malformed input and local resource/backend failures retain genuine reasons, never a negative judgment.
  outcome.auditEvaluationReason
func qualifiedAuditAnnouncements*(outcome: WorkJobResult): CheckedAuditBatch {.requires: outcome.status ==
    WorkJobResultKind.AuditAnnouncementsQualified.} =
  ## Only a wholly qualified batch contains source-free authenticated obligations.
  outcome.auditBatch
func auditAnnouncementError*(outcome: WorkJobResult): AuditReceiptResult[
    CheckedAuditBatch] {.requires: outcome.status == WorkJobResultKind.AuditAnnouncementFailure.} =
  ## Late source/proof/cancellation refusal never exposes an earlier accepted record.
  outcome.auditReceiptReason
func plannedAuditContext*(outcome: WorkJobResult): AuditContext {.requires: outcome.status ==
    WorkJobResultKind.AuditPlanned.} =
  ## Only exact uncancelled managed collection grants a whole source-free audit context.
  outcome.auditContext
func auditPlanningError*(outcome: WorkJobResult): AuditContextResult[
    AuditContext] {.requires: outcome.status == WorkJobResultKind.AuditPlanningFailure.} =
  ## Preserve the actual context/prefix/role failure without an accepted audit prefix.
  outcome.auditReason
func scheduledAssurance*(outcome: WorkJobResult): AssuranceSchedule {.requires: outcome.status ==
    WorkJobResultKind.AssuranceScheduled.} =
  ## Exact collection exposes only source-free author routing, timing and requested-core metadata.
  outcome.assuranceSchedule
func assuranceScheduleError*(outcome: WorkJobResult): AssuranceScheduleResult[
    AssuranceSchedule] {.requires: outcome.status == WorkJobResultKind.AssuranceScheduleFailure.} =
  ## Preserve actual temporal, duty, topology or output refusal without an author-set prefix.
  outcome.assuranceScheduleReason
func plannedAssurance*(outcome: WorkJobResult): AssuranceFetchPlan {.requires: outcome.status ==
    WorkJobResultKind.AssurancePlanned.} =
  ## Exact collection exposes source-free per-core/target metadata, never the canonical input graph.
  outcome.assurancePlan
func assurancePlanningError*(outcome: WorkJobResult): AssuranceFetchResult[
    AssuranceFetchPlan] {.requires: outcome.status == WorkJobResultKind.AssurancePlanningFailure.} =
  ## Real source, complete output-admission or historical-key refusal cannot expose a partial request plan.
  outcome.assurancePlanReason
func qualifiedAssurance*(outcome: WorkJobResult): CheckedAssurance {.requires: outcome.status ==
    WorkJobResultKind.AssuranceQualified.} =
  ## Exact collection exposes a source-free verified assurance, never the worker's canonical graph.
  outcome.assured
func assuranceError*(outcome: WorkJobResult): AssuranceDistributionResult[
    CheckedAssurance] {.requires: outcome.status == WorkJobResultKind.AssuranceFailure.} =
  ## Real selected canonical/signature refusal remains guarded and has no accepted prefix.
  outcome.assuranceReason
func qualifiedDistribution*(outcome: WorkJobResult): CheckedWorkDistribution {.requires:
    outcome.status == WorkJobResultKind.DistributionQualified.} =
  ## Source-bearing qualification remains behind the managed graph gate until its fixed facts and detached bytes are cut.
  outcome.distributed
func distributionReport*(outcome: WorkJobResult): CheckedReadReply {.requires:
    outcome.status == WorkJobResultKind.DistributionQualified.} =
  ## Independently decoded/hash-checked report bytes retain no canonical graph and may enter detached CE136 retention after matching collection.
  outcome.distributionReport
func distributionError*(outcome: WorkJobResult): WorkDistributionResult[
    CheckedWorkDistribution] {.requires:
    outcome.status == WorkJobResultKind.DistributionFailure.} =
  ## Preserve exact genuine context/credential/policy refusals without a successful prefix.
  outcome.distributionReason
func distributionEncodingError*(outcome: WorkJobResult): OwnershipError {.requires:
    outcome.status == WorkJobResultKind.DistributionEncodingFailure.} =
  ## Only an actual owned-report encoder refusal exposes this cause.
  outcome.distributionEncodingReason
func distributionCacheError*(outcome: WorkJobResult): ReadVerificationResult[
    CheckedReadReply] {.requires:
    outcome.status == WorkJobResultKind.DistributionCacheFailure.} =
  ## Retain the real detached report verification failure rather than inventing a cache certificate.
  outcome.distributionCacheReason
func context*(outcome: WorkJobResult): AuthorizedWorkContext {.requires: outcome.status ==
    WorkJobResultKind.Authorized.} =
  ## Retain the original authorization context only while the host owns the shared graph lease.
  outcome.context
func execution*(outcome: WorkJobResult): InputRefinement {.requires: outcome.status ==
    WorkJobResultKind.Refined.} =
  ## Only genuine complete refinement exposes its original immutable execution owner.
  outcome.execution
func authorizationError*(outcome: WorkJobResult): WorkSubmissionResult[
    AuthorizedWorkSubmission] {.requires: outcome.status ==
    WorkJobResultKind.AuthorizationFailure.} =
  ## Preserve the exact real failed admission result and its guarded child details.
  outcome.authorizationReason
func bodyError*(outcome: WorkJobResult): WorkSubmissionResult[
    VerifiedImportInputs] {.requires: outcome.status == WorkJobResultKind.BodyFailure.} =
  ## No successfully verified prefix can be extracted from body refusal.
  outcome.bodyReason
func refinementError*(outcome: WorkJobResult): InputRefinementResult[
    InputRefinement] {.requires: outcome.status == WorkJobResultKind.RefinementFailure.} =
  ## Preserve the existing execution pipeline's actual failed child.
  outcome.refinementReason
func dutyError*(outcome: WorkJobResult): WorkDutyResult[WorkDuty] {.requires: outcome.status ==
    WorkJobResultKind.DutyFailure.} =
  ## Preserve actual source/assignment refusal before any authorizer executes or a grant escapes.
  outcome.dutyReason
proc duty*(context: AuthorizedWorkContext): WorkDuty =
  ## Copy detached assignment facts only while the caller owns graph access; old computation-only contexts have no duty claim.
  let data = context.data
  if data == nil: return default(WorkDuty)
  data.duty
func reportTranscript*(outcome: WorkJobResult): ComputedGuaranteeTranscript {.requires: outcome.status ==
    WorkJobResultKind.Reported.} =
  ## Only genuine complete report preparation exposes its original-bound transcript, never a signature or inclusion certificate.
  outcome.report
func reportPreparationError*(outcome: WorkJobResult): WorkReportResult {.requires: outcome.status ==
    WorkJobResultKind.ReportFailure.} =
  ## Preserve the exact selected report/bundle/availability stage failure without exposing earlier owners.
  outcome.reportReason
func signedContribution*(outcome: WorkJobResult): SignedWorkContribution {.requires: outcome.status ==
    WorkJobResultKind.Contributed.} =
  ## Only one genuine fully qualified signature escapes a successful signing job.
  outcome.contribution
func eligibilityError*(outcome: WorkJobResult): WorkEligibilityResult[
    EligibleWorkGuarantee] {.requires: outcome.status == WorkJobResultKind.EligibilityFailure.} =
  ## Preserve the exact failed fresh-view qualification without an eligible prefix.
  outcome.eligibilityReason
func signingError*(outcome: WorkJobResult): WorkSignerResult[
    SignedWorkContribution] {.requires: outcome.status == WorkJobResultKind.SigningFailure.} =
  ## Preserve actual signer identity/backend failure without a signature.
  outcome.signingReason
func sharingError*(outcome: WorkJobResult): WorkSharingResult[
    SignedWorkContribution] {.requires: outcome.status == WorkJobResultKind.SharingFailure.} =
  ## Preserve the genuine failed whole-bundle receiver stage without signature authority.
  outcome.sharingReason
func valid*(job: WorkSubmissionJob): bool =
  ## Exactly one private closed runner selects the operation; defaults or ambiguous dispatch grant no execution capability.
  let data = job.data
  if data == nil: return false
  if data.run != nil: return data.cancellable == nil
  data.cancellable != nil
func valid*(context: AuthorizedWorkContext): bool =
  ## Default contexts never grant body CPU admission.
  context.data != nil
proc info*(context: AuthorizedWorkContext): WorkSubmissionResult[WorkSubmissionInfo] =
  ## Copy geometry while canonical graph access is available; the caller must retire this activation before another job starts.
  let data = context.data
  if data == nil: return default(WorkSubmissionResult[WorkSubmissionInfo])
  data.grant.submissionInfo
proc importRequest*(context: AuthorizedWorkContext): WorkSubmissionResult[seq[byte]] =
  ## Detach request bytes only while the shared graph is idle; no context or grant alias leaves in the returned buffer.
  let data = context.data
  if data == nil: return default(WorkSubmissionResult[seq[byte]])
  data.imports.workImportRequest
func importPlanningError*(outcome: WorkJobResult): WorkSubmissionResult[WorkImportPlan] {.requires:
    outcome.status == WorkJobResultKind.ImportPlanningFailure.} =
  ## Preserve a genuine missing/conflicting source mapping refusal without exposing a usable partial plan.
  outcome.planningReason
proc recovery*(context: AuthorizedWorkContext): WorkRecovery =
  ## Retain the initial private progress only while graph access is idle; hosts use detached Services metadata instead.
  let data = context.data
  if data == nil: return default(WorkRecovery)
  data.recovery
func recovery*(outcome: WorkJobResult): WorkRecovery {.requires: outcome.status ==
    WorkJobResultKind.RecoveryUpdated.} =
  ## Only a genuine completed CPU step exposes its next immutable private progress.
  outcome.recovered
func recoveryError*(outcome: WorkJobResult): WorkRecoveryResult[
    WorkRecovery] {.requires: outcome.status == WorkJobResultKind.RecoveryFailure.} =
  ## Preserve the exact packet/catalog refusal with no successful prefix.
  outcome.recoveryReason
func recoveryCompletionError*(outcome: WorkJobResult): WorkRecoveryResult[
    VerifiedImportInputs] {.requires: outcome.status ==
    WorkJobResultKind.RecoveryCompletionFailure.} =
  ## Preserve complete original-package binding refusal.
  outcome.recoveryCompletionReason
proc authorize(data: WorkJobData): WorkJobResult =
  ## Private staging aliases retire before the worker publishes Done.
  let source = data.source
  var duty = default(WorkDuty)
  if source.recipient.valid:
    # Network requests must prove the original local core assignment inside the same exclusive CPU lease.
    let selected = captureWorkDuty(source.state, source.parameters, source.recipient,
      source.header.submissionInfo.value.core, source.dutyLimits)
    if selected.error != WorkDutyError.None:
      return WorkJobResult(status: WorkJobResultKind.DutyFailure, dutyReason: selected)
    duty = selected.value
  let outcome = authorizeWorkSubmission(source.header, source.state, source.parameters, source.limits)
  if outcome.error != WorkSubmissionError.None:
    return WorkJobResult(status: WorkJobResultKind.AuthorizationFailure,
        authorizationReason: outcome)
  var imports = default(WorkImportPlan)
  if source.header.submissionInfo.value.kind == WorkSubmissionKind.Package:
    # Package-only imports are planned on the same CPU turn and exact state as successful authorization.
    let planned = prepareWorkImportPlan(outcome.value, source.limits)
    if planned.error != WorkSubmissionError.None:
      return WorkJobResult(status: WorkJobResultKind.ImportPlanningFailure, planningReason: planned)
    imports = planned.value
  var recovered = default(WorkRecovery)
  if source.recovery.valid and source.header.submissionInfo.value.kind ==
      WorkSubmissionKind.Package:
    # Catalog capture and original-map binding share this exact authorization lease; no host-provided report descriptor enters.
    let planned = beginWorkRecovery(imports, source.view, source.recovery)
    if planned.error != WorkRecoveryError.None:
      return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: planned)
    recovered = planned.value
  # Catalog rows retain only their original descriptors/rosters; network waits must not pin every old complete state in the captured view.
  let retained = WorkSource(header: source.header, state: source.state,
    parameters: source.parameters,
    limits: source.limits, execution: source.execution, recipient: source.recipient,
    dutyLimits: source.dutyLimits,
    view: default(ChainView), recovery: source.recovery)
  WorkJobResult(status: WorkJobResultKind.Authorized,
    context: AuthorizedWorkContext(data: WorkContextData(source: retained, grant: outcome.value,
        duty: duty, imports: imports, recovery: recovered)))
proc refine(context: WorkContextData, inputs: VerifiedImportInputs): WorkJobResult =
  ## Every path executes the same original source, core and immutable refinement policy after complete input binding.
  let source = context.source
  let described = context.grant.submissionInfo.value
  let executed = runInputRefinement(source.state, inputs, described.core, source.parameters,
      source.execution)
  if executed.error != InputRefinementError.None:
    return WorkJobResult(status: WorkJobResultKind.RefinementFailure, refinementReason: executed)
  WorkJobResult(status: WorkJobResultKind.Refined, execution: executed.value)
proc recoverPacket(data: WorkJobData): WorkJobResult =
  ## No native or host alias is touched while both proof pieces and any threshold reconstruction run on this lease.
  let completed = acceptRecoveryPacket(data.recovery, data.recoveryVersion, data.validator, data.segments)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: completed)
  WorkJobResult(status: WorkJobResultKind.RecoveryUpdated, recovered: completed.value)
proc retryRecovery(data: WorkJobData): WorkJobResult =
  ## Discard unproven packet ownership only on the private managed CPU lease, never from a callback or busy host.
  let completed = retryRecoveryProven(data.recovery)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: completed)
  WorkJobResult(status: WorkJobResultKind.RecoveryUpdated, recovered: completed.value)
proc completeRecovered(data: WorkJobData): WorkJobResult =
  ## The exact original grant owns both recovery and complete binding before real source-bound execution.
  let context = data.context.data
  if context == nil: return default(WorkJobResult)
  let completed = completeRecoveredWork(data.recovery, context.grant, data.extrinsics,
      context.source.limits)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryCompletionFailure,
        recoveryCompletionReason: completed)
  refine(context, completed.value)
proc complete(data: WorkJobData): WorkJobResult =
  ## Validate only the original grant's body, then execute from the same immutable source and fixed original policy.
  let context = data.context.data
  if context == nil: return default(WorkJobResult)
  let source = context.source
  let described = context.grant.submissionInfo.value
  let inputs = if described.kind == WorkSubmissionKind.Bundle:
    completeBundleSubmission(context.grant, data.extrinsics, data.segments, data.proofs, source.limits)
  elif data.fetched:
    completeFetchedPackageSubmission(context.grant, context.imports, data.extrinsics, data.segments, source.limits)
  else:
    completePackageSubmission(context.grant, data.extrinsics, data.imports, data.lookup, source.limits)
  if inputs.error != WorkSubmissionError.None:
    return WorkJobResult(status: WorkJobResultKind.BodyFailure, bodyReason: inputs)
  refine(context, inputs.value)
proc report(data: WorkJobData): WorkJobResult =
  ## Original refinement stays under the same graph lease through every bounded encoding/hash stage.
  let computed = prepareWorkReport(data.refined, data.shards, data.reportLimits)
  if computed.error != WorkReportError.None:
    return WorkJobResult(status: WorkJobResultKind.ReportFailure, reportReason: computed)
  let context = data.context.data
  if context == nil: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  if not computed.value.workReportMatches(context.source.header, context.source.state,
      context.source.parameters):
    return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  WorkJobResult(status: WorkJobResultKind.Reported, report: computed.value)
proc captureWorkReport*(context: AuthorizedWorkContext, source: InputRefinement,
    shards: ErasureShards, limits: WorkReportLimits): WorkJobAdmission =
  ## Require the original session's package/core/map before encoding; every captured alias remains frozen through exact collection.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let identity = source.inputRefinementIdentity
  if identity.error != InputRefinementError.None:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let authorization = identity.value.identitySource.value.authorizedSource.value
  if not data.source.header.submissionMatchesAuthorization(authorization, data.source.state):
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not authorization.authorizationParameters.value.sameParameterProfile(data.source.parameters):
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: report, context: context, refined: source, shards: shards, reportLimits: limits)))
proc contribute(data: WorkJobData): WorkJobResult =
  ## Qualification and private-key signing share one exact managed graph lease and one fresh canonical view.
  let context = data.context.data
  if context == nil: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  let qualified = qualifyWorkGuarantee(data.transcript, context.source.header, context.source.state,
    data.signingView, data.signingIdentity, data.signingTime, data.signingLimits)
  if qualified.error != WorkEligibilityError.None:
    return WorkJobResult(status: WorkJobResultKind.EligibilityFailure, eligibilityReason: qualified)
  let signed = data.signer.signWorkContribution(qualified.value, data.retentionLimits,
      data.retainedSources)
  if signed.error != WorkSignerError.None:
    return WorkJobResult(status: WorkJobResultKind.SigningFailure, signingReason: signed)
  WorkJobResult(status: WorkJobResultKind.Contributed, contribution: signed.value)
proc copyRetainedSources(existing: openArray[GuarantorAvailability]): seq[GuarantorAvailability] =
  ## Capture validates the fixed entry bound before privately copying source-free aliases; all tables freeze through collection.
  result = newSeq[GuarantorAvailability](existing.len)
  for index in 0..<existing.len: result[index] = existing[index]
proc captureWorkContribution*(context: AuthorizedWorkContext,
    transcript: ComputedGuaranteeTranscript, view: ChainView, local: StateEdKey, now: StateTime,
        signer: WorkSigner,
    limits: WorkEligibilityLimits, retention: AvailabilityMerkleLimits,
    existing: openArray[GuarantorAvailability] = []): WorkJobAdmission =
  ## Capture only while all owners are host-exclusive; every alias, including signer and view, stays frozen until exact collect/join.
  ## Services supplies its privately loaded key; callers never install an external signer alias into Services.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if existing.len > 64 or not retention.validGuarantorLimits:
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if not transcript.workReportMatches(data.source.header, data.source.state,
      data.source.parameters):
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let count = view.retainedCount
  if uint64(count) > uint64(limits.anchors.ancestors.headers) or
      count > high(int) div sizeof(BlockSnapshotResult):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if uint64(view.validationHeaderCount) > uint64(limits.anchors.ancestors.headers):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: contribute, context: context, transcript: transcript, signingView: view,
    signingIdentity: local, signingTime: now, signer: signer, signingLimits: limits,
    retentionLimits: retention, retainedSources: copyRetainedSources(existing))))
proc prepareExchange(data: WorkJobData): WorkJobResult =
  ## Bundle copying/encoding and sealed target discovery execute only on the exclusive managed CPU lease.
  let prepared = prepareWorkSharing(data.contribution, data.exchangeBytes)
  if prepared.error != WorkSharingError.None:
    return WorkJobResult(status: WorkJobResultKind.ExchangePreparationFailure,
        exchangeReason: prepared)
  let initial = beginWorkGuarantee(data.contribution)
  if initial.error != WorkGuaranteeError.None: return WorkJobResult(
      status: WorkJobResultKind.InvalidSource)
  var targets = default(array[2, WorkShareTarget])
  var count = 0
  for position in 0..<3:
    # Null/local keys need no request; each physical remote key is contacted once even when it owns several distinct original indices.
    let selected = sharingTarget(data.contribution, position)
    if selected.error == WorkGuaranteeError.InvalidTarget: continue
    if selected.error != WorkGuaranteeError.None:
      return WorkJobResult(status: WorkJobResultKind.InvalidSource)
    var present = false
    for index in 0..<count:
      let prior = targets[index].participant.validator.ed25519
      let current = selected.value.participant.validator.ed25519
      if array[32, byte](prior) == array[32, byte](current): present = true
    if present: continue
    if count >= targets.len: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
    targets[count] = selected.value
    inc count
  WorkJobResult(status: WorkJobResultKind.ExchangePrepared, preparedRequest: prepared.value,
    preparedRound: initial.value, preparedTargets: targets, preparedCount: count)
proc captureWorkExchange*(contribution: SignedWorkContribution,
    maximum: ByteLimit): WorkJobAdmission =
  ## Capture only a genuine local signature; every source alias stays frozen until exact collection or joined stop.
  if contribution.contributionInfo.error != WorkSignerError.None:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: prepareExchange, contribution: contribution, exchangeBytes: maximum)))
proc acceptResponse(data: WorkJobData): WorkJobResult =
  ## Actual transport identity and detached fixed bytes cannot substitute for the round's original sealed target.
  let accepted = addWorkResponse(data.round, data.target, data.sharingPeer, data.response)
  if accepted.error != WorkGuaranteeError.None:
    return WorkJobResult(status: WorkJobResultKind.PeerResponseFailure, peerReason: accepted)
  WorkJobResult(status: WorkJobResultKind.PeerAccepted, acceptedRound: accepted.value)
proc captureWorkResponse*(round: WorkGuaranteeRound, target: WorkShareTarget,
    peer: StateEdKey, response: array[96, byte]): WorkJobAdmission =
  ## No native handle or raw request/plan parent enters signature verification; only the private round graph and fixed copies are retained.
  if round.credentialCount == 0 or not target.valid:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: acceptResponse, round: round, target: target, sharingPeer: peer, response: response)))
proc collectGuarantee(data: WorkJobData): WorkJobResult =
  ## Sorting, structural preflight and final canonical encoding share the exact round's managed lease.
  let collected = collectWorkGuarantee(data.round, data.exchangeBytes)
  if collected.error != WorkGuaranteeError.None:
    return WorkJobResult(status: WorkJobResultKind.GuaranteeCollectionFailure,
        collectionReason: collected)
  WorkJobResult(status: WorkJobResultKind.GuaranteeCollected, collected: collected.value)
proc captureWorkGuarantee*(round: WorkGuaranteeRound, maximum: ByteLimit): WorkJobAdmission =
  ## Capture an existing genuine round, allowing the worker to return precise threshold/output-budget refusals.
  if round.credentialCount == 0: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: collectGuarantee, round: round, exchangeBytes: maximum)))
proc qualifyDistribution(data: WorkJobData): WorkJobResult =
  ## All signatures, source checks and report-cache hashing run inside this closed managed turn, never in native callbacks.
  let wire = data.distributionRequest.payload
  let checked = qualifyWorkDistribution(wire, data.distributionView, data.distributionTime,
    data.distributionLimits)
  if checked.error != WorkDistributionError.None:
    return WorkJobResult(status: WorkJobResultKind.DistributionFailure, distributionReason: checked)
  let report = checked.value.distributionGuarantee.value.report
  let length = report.ownedReportInfo.value.consumed
  if length <= 0 or length > MaxReadReplyBytes-4:
    return WorkJobResult(status: WorkJobResultKind.DistributionOutputLimit)
  var framed = newSeq[byte](length+4)
  for index in 0..<4: framed[index] = byte((uint32(length) shr (8*index)) and 255)
  let encoded = encodeOwnedReport(report, framed.toOpenArray(4, framed.high))
  if encoded.error != OwnershipError.None:
    return WorkJobResult(status: WorkJobResultKind.DistributionEncodingFailure,
      distributionEncodingReason: encoded.error)
  let source = captureReadSource(data.distributionView.bestBlock)
  if source.error != ReadVerificationError.None:
    return WorkJobResult(status: WorkJobResultKind.InvalidSource) # The already-qualified immutable view cannot become unavailable within this turn.
  let query = decodeReadRequest(ReadKind.Report, checked.value.distributionInfo.value.reportHash)
  if query.error != ReadError.None: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  let cached = verifyReadReply(query.value, framed, source.value,
    ReadVerificationLimits(wireBytes: data.distributionLimits.wireBytes))
  if cached.error != ReadVerificationError.None:
    return WorkJobResult(status: WorkJobResultKind.DistributionCacheFailure,
        distributionCacheReason: cached)
  WorkJobResult(status: WorkJobResultKind.DistributionQualified, distributed: checked.value,
    distributionReport: cached.value)
proc planAssurance(data: WorkJobData): WorkJobResult =
  ## Complete canonical roster/assignment work executes only on the bounded managed worker.
  let planned = captureAssuranceFetch(data.assuranceSource, data.assurancePeer,
      data.assuranceFetchLimits)
  if planned.error != AssuranceFetchError.None:
    return WorkJobResult(status: WorkJobResultKind.AssurancePlanningFailure,
        assurancePlanReason: planned)
  WorkJobResult(status: WorkJobResultKind.AssurancePlanned, assurancePlan: planned.value)
proc captureAssurancePlanning*(source: BlockSnapshotResult, local: StateEdKey,
    limits: AssuranceFetchLimits): WorkJobAdmission =
  ## Capture owns no I/O or proof side effects; its wrapper and source aliases retire before moved native submission.
  if source.error != GenesisError.None or not limits.valid or array[32, byte](local) == default(
      array[32, byte]):
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: planAssurance, assuranceSource: source, assurancePeer: local,
    assuranceFetchLimits: limits)))
proc planAuditContext(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Canonical body, prior rosters and all authentication run only behind the existing managed graph lease.
  let selected = captureAuditContext(data.auditView, data.auditHash, data.auditLimits, control)
  if selected.error != AuditContextError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditPlanningFailure, auditReason: selected)
  WorkJobResult(status: WorkJobResultKind.AuditPlanned, auditContext: selected.value)
proc captureAuditPlanning*(source: ChainView, blockHash: genesis.BlockHash,
    limits: AuditContextLimits): WorkJobAdmission =
  ## Capturing immutable source authority performs no body decoding, hashing or crypto; only this fixed cancellable runner can be queued.
  if source.fuzzOnly or source.bestBlock.error != GenesisError.None or not limits.valid:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: planAuditContext, auditView: source, auditHash: blockHash, auditLimits: limits)))
proc qualifyIncomingAudit(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## All body admission, actual prior-role lookup and batch crypto execute behind the managed graph lease.
  let checked = qualifyAuditAnnouncements(data.auditView, data.auditWire, data.auditReceiptLimits,
      control, data.auditAlternatives)
  if checked.error != AuditReceiptError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditAnnouncementFailure,
        auditReceiptReason: checked)
  WorkJobResult(status: WorkJobResultKind.AuditAnnouncementsQualified, auditBatch: checked.value)
proc captureAuditAnnouncements*(source: ChainView, wire: openArray[byte],
    limits: AuditReceiptLimits, alternatives: sink seq[ChainView] = @[]): WorkJobAdmission =
  ## Capture only finite detached bytes and the actual immutable chain; callers cannot enqueue a verifier or an invented context.
  if source.fuzzOnly or source.bestBlock.error != GenesisError.None or not limits.valid:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(limits.message.bytes):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  var captured = newSeq[byte](wire.len)
  for index in 0..<wire.len: captured[index] = wire[index] # No caller buffer alias crosses native submission.
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: qualifyIncomingAudit, auditView: source, auditWire: captured,
    auditReceiptLimits: limits, auditAlternatives: alternatives)))
func producedInitialAudit*(outcome: WorkJobResult): ProducedInitialAudit {.requires:
    outcome.status == WorkJobResultKind.InitialAuditProduced.} =
  ## Only complete production exposes detached signed bytes and selected cores.
  outcome.initialAudit
func initialAuditSourceError*(outcome: WorkJobResult): AuditContextError {.requires:
    outcome.status == WorkJobResultKind.InitialAuditSourceFailure.} =
  ## Preserve the source refusal independently of signing.
  outcome.initialAuditSourceReason
func initialAuditSigningError*(outcome: WorkJobResult): AuditValidationError {.requires:
    outcome.status == WorkJobResultKind.InitialAuditSigningFailure.} =
  ## Preserve validation and signing refusal without retaining the source context.
  outcome.initialAuditSigningReason
proc initialRecipients(context: AuditContext, identity: StateEdKey,
    control: AssuranceScanControl): seq[InitialAuditRecipient] =
  ## Each original active identity receives the declaration once per physical connection.
  let local = array[32, byte](identity)
  let excluded = array[32, byte](nullValidator().ed25519)
  let empty = default(array[32, byte])
  result = @[]
  for ordinal in 0..<context.contextInfo.value.auditors:
    # Repeated keys still have distinct signing ordinals but share physical delivery.
    if control.stopped: return @[]
    let member = context.auditorAt(ordinal).value
    let key = array[32, byte](member.ed25519)
    if key == local or key == excluded or key == empty: continue
    let endpoint = validatorEndpoint(array[128, byte](member.metadata))
    var duplicate = false
    for index in 0..<result.len:
      # Prefer the first advertised endpoint when duplicate positions carry different metadata.
      if array[32, byte](result[index].identity) == key:
        if result[index].endpoint.error != EndpointError.None and endpoint.error ==
            EndpointError.None:
          result[index].endpoint = endpoint
        duplicate = true
        break
    if not duplicate: result.add(InitialAuditRecipient(identity: member.ed25519,
        endpoint: endpoint))
proc nextInitialOrdinal(data: WorkJobData, source: AuditContext,
    control: AssuranceScanControl): int =
  ## Scan original positions without compressing duplicates or assuming the current topology index.
  let local = array[32, byte](data.auditParticipationIdentity)
  let key = data.auditBandersnatch.signingPublic
  if local == default(array[32, byte]) or local == array[32, byte](nullValidator().ed25519):
    return -1
  for ordinal in int(uint16(data.auditInitialOrdinal))..<source.contextInfo.value.auditors:
    # TLS and JIP-5 signing ownership must match at the same original position.
    if control.stopped: return -1
    let member = source.auditorAt(ordinal).value
    if array[32, byte](member.ed25519) == local and array[32, byte](member.bandersnatch) == key:
      return ordinal
  -1
proc runInitialAudit(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Resolve the original roster inside the lease and require the local identity at the signed ordinal.
  let source = captureAuditContext(data.auditView, data.auditHash, data.auditLimits, control)
  if source.error != AuditContextError.None:
    return WorkJobResult(status: WorkJobResultKind.InitialAuditSourceFailure,
        initialAuditSourceReason: source.error)
  var ordinal = data.auditInitialOrdinal
  if data.auditDiscoverOrdinal:
    if source.value.contextInfo.value.reports == 0:
      return WorkJobResult(status: WorkJobResultKind.InitialAuditNoDuty)
    let next = nextInitialOrdinal(data, source.value, control)
    if control.stopped: return WorkJobResult(status: WorkJobResultKind.InitialAuditSourceFailure,
        initialAuditSourceReason: AuditContextError.Cancelled)
    if next < 0: return WorkJobResult(status: WorkJobResultKind.InitialAuditNoDuty)
    ordinal = JudgeIndex(uint16(next))
  let member = source.value.auditorAt(int(uint16(ordinal)))
  if member.error != AuditContextError.None or
      array[32, byte](member.value.ed25519) != array[32, byte](data.auditParticipationIdentity):
    return WorkJobResult(status: WorkJobResultKind.InitialAuditSigningFailure,
        initialAuditSigningReason: AuditValidationError.InvalidAuditor)
  if control.stopped: return WorkJobResult(status: WorkJobResultKind.InitialAuditSourceFailure,
      initialAuditSourceReason: AuditContextError.Cancelled)
  let signed = produceAuditAnnouncement(data.auditBandersnatch, source.value,
      ordinal, data.auditProofLimits)
  if signed.error != AuditValidationError.None:
    return WorkJobResult(status: WorkJobResultKind.InitialAuditSigningFailure,
        initialAuditSigningReason: signed.error)
  var selected = InitialAuditSelection(count: signed.value.announcementInfo.value.selected)
  for ordinal in 0..<selected.count:
    selected.cores[ordinal] = signed.value.selectedCore(ordinal).value
  let announcement = signed.value.announcementRecord.value
  var output = ProducedInitialAudit(announcement: announcement, selected: selected,
      epoch: source.value.contextInfo.value.epoch)
  if selected.count > 0:
    # A declaration exists on the wire only when it selects one or more newly available reports.
    let facts = source.value.contextInfo.value
    var found = 0
    for ordinal in 0..<facts.reports:
      # The checked selection preserves dense source report order after filtering the shuffled cores.
      if found == selected.count: break
      if uint64(source.value.availableCore(ordinal).value) == uint64(selected.cores[found]):
        output.reportOrdinals[found] = ordinal
        inc found
    if found != selected.count:
      return WorkJobResult(status: WorkJobResultKind.InitialAuditEncodingFailure)
    let limits = AuditLimits(validators: ValidatorCount(uint64(facts.auditors)),
        cores: facts.maximumCores, bytes: ByteLimit(131), records: ElementLimit(1))
    let wire = encodeAnnouncements([announcement], limits)
    if wire.error != AuditError.None:
      return WorkJobResult(status: WorkJobResultKind.InitialAuditEncodingFailure)
    let request = decodeReadRequest(ReadKind.AuditAnnouncement, wire.value)
    if request.error != ReadError.None:
      return WorkJobResult(status: WorkJobResultKind.InitialAuditEncodingFailure)
    output.request = request.value
    output.recipients = initialRecipients(source.value, data.auditParticipationIdentity, control)
    if control.stopped:
      return WorkJobResult(status: WorkJobResultKind.InitialAuditSourceFailure,
          initialAuditSourceReason: AuditContextError.Cancelled)
  WorkJobResult(status: WorkJobResultKind.InitialAuditProduced, initialAudit: move(output))
proc captureInitialAuditJob*(source: ChainView, blockHash: genesis.BlockHash,
    context: AuditContextLimits, proof: AuditProofLimits, signer: TicketSigner,
    identity: StateEdKey, ordinal: JudgeIndex, discover = false): WorkJobAdmission =
  ## Only a private installed signer and bounded chain context can enter production.
  if source.fuzzOnly or source.bestBlock.error != GenesisError.None or not context.valid or
      not proof.valid or uint64(proof.proofs) < 2 or not signer.valid:
    return workJobFailure(WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: runInitialAudit, auditView: source, auditHash: blockHash, auditLimits: context,
    auditProofLimits: proof, auditBandersnatch: signer, auditInitialOrdinal: ordinal,
    auditParticipationIdentity: identity, auditDiscoverOrdinal: discover)))
proc prepareAuditOrigin(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Whole body/prefix validation and complete-map retention accounting execute only behind the shared source lease.
  let prepared = captureAuditOrigin(data.auditView, data.auditHash, data.auditLimits,
      data.auditOriginLimits, control)
  if prepared.error != AuditOriginError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditOriginPreparationFailure,
        auditOriginReason: prepared)
  WorkJobResult(status: WorkJobResultKind.AuditOriginPrepared, auditOrigin: prepared.value)
proc captureAuditOriginJob*(source: ChainView, blockHash: genesis.BlockHash,
    context: AuditContextLimits, limits: AuditOriginLimits): WorkJobAdmission =
  ## Capturing actual complete history performs no crypto, state scan or caller callback; the fixed private runner owns every later source traversal.
  if source.fuzzOnly or source.bestBlock.error != GenesisError.None or not context.valid or
      not limits.valid:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: prepareAuditOrigin, auditView: source, auditHash: blockHash, auditLimits: context,
    auditOriginLimits: limits)))
proc checkJudgmentClaims(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## The fixed worker alone reads actual original-epoch rosters and verifies the complete CE145 message.
  let checked = verifyJudgmentClaims(data.auditView, data.auditWire, data.judgmentClaimLimits, control)
  if checked.error != JudgmentClaimError.None:
    return WorkJobResult(status: WorkJobResultKind.JudgmentClaimFailure,
        judgmentClaimReason: checked)
  WorkJobResult(status: WorkJobResultKind.JudgmentClaimsVerified, judgmentClaims: checked.value)
proc captureJudgmentClaimJob*(view: ChainView, wire: openArray[byte],
    limits: JudgmentClaimLimits): WorkJobAdmission =
  ## Whole bounded raw bytes are detached before publication; no caller key table, signature-valid bit or callback becomes a verification runner.
  if not limits.valid or view.fuzzOnly or view.bestBlock.error != GenesisError.None:
    return workJobFailure(WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(limits.message.bytes): return workJobFailure(
      WorkJobError.LimitExceeded)
  var captured = newSeq[byte](wire.len)
  for ordinal in 0..<wire.len: captured[ordinal] = wire[ordinal]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: checkJudgmentClaims, auditView: view, auditWire: move(captured),
        judgmentClaimLimits: limits)))
proc planAuditParticipation(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Original auditor and known successor extraction execute under the same fixed private full-source lease.
  let plan = captureAuditParticipation(data.auditTarget, data.auditParticipationCurrent,
    data.auditParticipationIdentity, data.auditParticipationLimits, control)
  if plan.error != AuditParticipationError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditParticipationFailure,
        auditParticipationReason: plan)
  WorkJobResult(status: WorkJobResultKind.AuditParticipationPlanned, auditParticipation: plan.value)
proc captureAuditParticipationJob*(origin: AuditReportOrigin, current: BlockSnapshotResult,
    identity: StateEdKey, limits: AuditParticipationLimits): WorkJobAdmission =
  ## Capture genuine private target/current snapshot ownership only; no caller-provided local index, key table or callback supplies duty authority.
  if not origin.valid or current.error != GenesisError.None or not limits.valid:
    return workJobFailure(WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: planAuditParticipation, auditTarget: origin, auditParticipationCurrent: current,
    auditParticipationIdentity: identity, auditParticipationLimits: limits)))
proc runAuditRoutingRefresh(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Execute the shared topology planner with worker-owned detached original metadata.
  let plan = refreshAuditParticipation(data.auditRoutingBasis, data.auditParticipationCurrent,
      data.auditParticipationLimits, control)
  if plan.error != AuditParticipationError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditParticipationFailure,
        auditParticipationReason: plan)
  WorkJobResult(status: WorkJobResultKind.AuditParticipationPlanned, auditParticipation: plan.value)
proc captureAuditRoutingRefresh*(basis: AuditRoutingBasis, current: BlockSnapshotResult,
    limits: AuditParticipationLimits): WorkJobAdmission =
  ## Capture an independent public roster copy so foreground delivery may continue during the lease.
  if not basis.valid or current.error != GenesisError.None or not limits.valid:
    return workJobFailure(WorkJobError.InvalidInput)
  let copied = basis.detached(limits.workspaceBytes)
  if not copied.valid: return workJobFailure(WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: runAuditRoutingRefresh, auditRoutingBasis: copied,
    auditParticipationCurrent: current, auditParticipationLimits: limits)))
proc prepareIncomingJudgment(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Original negative guarantees, historical lookup sources and whole-map accounting execute only on the fixed CPU worker.
  let prepared = prepareJudgmentReceipt(data.auditView, data.judgmentClaims, data.judgmentInputs,
      data.judgmentReceiptLimits, control)
  if prepared.error != JudgmentReceiptError.None:
    return WorkJobResult(status: WorkJobResultKind.JudgmentReceiptFailure,
        judgmentReceiptReason: prepared)
  WorkJobResult(status: WorkJobResultKind.JudgmentReceiptPrepared, judgmentReceipt: prepared.value)
proc captureJudgmentReceiptJob*(view: ChainView, claims: SignedJudgmentBatch,
    inputs: openArray[JudgmentSourceInput], limits: JudgmentReceiptLimits): WorkJobAdmission =
  ## Every report/claim/source alias stays frozen until exact collection or joined stop. Raw report objects provide no inclusion or validity authority.
  if view.fuzzOnly or not claims.valid or not limits.valid or claims.len > 16 or inputs.len != claims.len:
    return workJobFailure(WorkJobError.InvalidInput)
  var captured = newSeq[JudgmentSourceInput](inputs.len)
  for ordinal in 0..<inputs.len:
    # Only negative records retain reports; reject oversized complete report input before capturing any source-bearing job.
    if not claims.claimAt(ordinal).value.judgmentRecord.valid:
      let info = inputs[ordinal].report.ownedReportInfo
      if info.error != OwnershipError.None: return workJobFailure(WorkJobError.InvalidInput)
      if uint64(info.value.consumed) > uint64(limits.support.support.wire.maxBytes):
        return workJobFailure(WorkJobError.LimitExceeded)
      captured[ordinal] = inputs[ordinal]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: prepareIncomingJudgment, auditView: view, judgmentClaims: claims,
    judgmentInputs: move(captured), judgmentReceiptLimits: limits)))
proc verifyAuditShard(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Exact expected source-free metadata and coordinates feed the maintained Merkle verifier on the CPU worker.
  if control.stopped: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  let verified = verifyAuditFetchShard(data.auditFetchPlan, data.auditFetchOrdinal,
    data.auditWire, data.auditFetchTransferLimits)
  if verified.error != AuditFetchError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditShardVerificationFailure,
        auditShardReason: verified)
  WorkJobResult(status: WorkJobResultKind.AuditShardVerified, auditShard: verified.value)
proc captureAuditShardVerificationJob*(plan: AuditFetchPlan, ordinal: int,
    wire: openArray[byte], limits: AvailabilityMerkleLimits): WorkJobAdmission =
  ## Bound complete detached bytes before copying; no caller-supplied expected root or unchecked shard replaces the original plan.
  if not plan.valid or plan.targetAt(true, ordinal).error != AuditFetchError.None:
    return workJobFailure(WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(plan.replyLimit(true)): return workJobFailure(
      WorkJobError.LimitExceeded)
  var captured = newSeq[byte](wire.len)
  for index in 0..<wire.len: captured[index] = wire[index]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: verifyAuditShard, auditFetchPlan: plan, auditFetchOrdinal: ordinal,
    auditWire: move(captured), auditFetchTransferLimits: limits)))
proc prepareAuditFetch(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Source traversal stays under the original lease; exact worker collection additionally suppresses cancelled Done output.
  if control.stopped: return WorkJobResult(status: WorkJobResultKind.InvalidSource)
  let planned = captureAuditFetch(data.auditTarget, data.auditFetchLimits)
  if planned.error != AuditFetchError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditFetchPlanningFailure,
        auditFetchReason: planned)
  WorkJobResult(status: WorkJobResultKind.AuditFetchPlanned, auditFetch: planned.value)
proc captureAuditFetchJob*(origin: AuditReportOrigin, limits: AuditFetchLimits): WorkJobAdmission =
  ## Capture only the actual original immutable target; the closed worker builds independently owned routing rows.
  if not origin.valid or not limits.valid: return workJobFailure(WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: prepareAuditFetch, auditTarget: origin, auditFetchLimits: limits)))
proc evaluateAudit(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Actual authorization/refinement/availability comparison runs only on the closed reusable worker; caller booleans or detached digest replacements are never accepted.
  let evaluated = evaluateDirectAudit(data.auditTarget, data.auditWire, data.auditEvaluationLimits, control)
  if evaluated.error != AuditEvaluationError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditEvaluationFailure,
        auditEvaluationReason: evaluated)
  WorkJobResult(status: WorkJobResultKind.AuditEvaluated, auditEvaluation: evaluated.value)
proc captureAuditEvaluationJob*(origin: AuditReportOrigin, wire: openArray[byte],
    limits: AuditEvaluationLimits): WorkJobAdmission =
  ## Only an immutable qualified original target and finite detached wire cross the CPU boundary; execution-only cancellation is never stored in the job.
  if not origin.valid or not limits.valid: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(limits.bundle.bytes) or uint64(wire.len) > uint64(
      limits.report.bundleBytes):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  var captured = newSeq[byte](wire.len)
  for ordinal in 0..<wire.len: captured[ordinal] = wire[
      ordinal] # Native callbacks and caller mutations cannot change a queued candidate.
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: evaluateAudit, auditTarget: origin, auditWire: captured,
    auditEvaluationLimits: limits)))
proc recoverEvaluateAudit(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Complete original-coordinate authentication/recovery before private reproduction can create a negative capability.
  let recovered = recoverAuditBundle(data.auditTarget, data.auditPackets, data.auditRecoveryLimits, control)
  if recovered.error != AuditRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditRecoveryFailure,
        auditRecoveryReason: recovered)
  let evaluated = evaluateRecoveredAudit(data.auditTarget, recovered.value,
      data.auditEvaluationLimits, control)
  if evaluated.error != AuditEvaluationError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditEvaluationFailure,
        auditEvaluationReason: evaluated)
  WorkJobResult(status: WorkJobResultKind.AuditEvaluated, auditEvaluation: evaluated.value)
proc captureAuditRecoveryEvaluationJob*(origin: AuditReportOrigin,
    packets: openArray[VerifiedAvailabilityTransfer], recovery: AuditRecoveryLimits,
    evaluation: AuditEvaluationLimits): WorkJobAdmission =
  ## Original checked packets retain immutable root/coordinate provenance; all aliases freeze through exact collection. Whole descriptor/payload ceilings precede copying.
  if not origin.valid or not recovery.valid or not evaluation.valid or packets.len == 0 or
      packets.len > 342:
    return workJobFailure(WorkJobError.InvalidInput)
  var bytes = 0'u64
  for packet in packets:
    if not packet.valid: return workJobFailure(WorkJobError.InvalidInput)
    let size = packet.payloadBytes
    if size > uint64(recovery.bytes)-bytes: return workJobFailure(WorkJobError.LimitExceeded)
    bytes += size
  var retained = newSeq[VerifiedAvailabilityTransfer](packets.len)
  for ordinal in 0..<packets.len: retained[ordinal] = packets[ordinal]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: recoverEvaluateAudit, auditTarget: origin, auditPackets: retained,
    auditRecoveryLimits: recovery, auditEvaluationLimits: evaluation)))
proc prepareAuditPublication(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## Whole output admission, exact report encoding and original-key signing execute under one private source/key lease.
  let prepared = prepareAuditPublication(data.signer, data.auditEvaluation,
    data.auditValidator, data.auditPublicationLimits, control)
  if prepared.error != AuditPublicationError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditPublicationFailure,
        auditPublicationReason: prepared)
  WorkJobResult(status: WorkJobResultKind.AuditPublicationPrepared,
      auditPublication: prepared.value)
proc captureAuditPublicationJob*(signer: WorkSigner, evaluation: AuditEvaluation,
    validator: StateValidatorIndex, limits: AuditPublicationLimits): WorkJobAdmission =
  ## Callers cannot provide a purported judgment, report replacement, completed-validity bit or arbitrary signing message.
  if not evaluation.valid or not limits.valid or signer.signerIdentity.error !=
      WorkSignerError.None:
    return workJobFailure(WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: prepareAuditPublication, signer: signer, auditEvaluation: evaluation,
    auditValidator: validator, auditPublicationLimits: limits)))
proc signAudit(data: WorkJobData, control: AssuranceScanControl): WorkJobResult =
  ## The only input validity is a genuine private completed evaluation, selected by Services under its canonical graph gate.
  let signed = signAuditJudgment(data.signer, data.auditEvaluation, data.auditValidator, control)
  if signed.error != AuditSigningError.None:
    return WorkJobResult(status: WorkJobResultKind.AuditSigningFailure, auditSigningReason: signed)
  WorkJobResult(status: WorkJobResultKind.AuditSigned, auditSigned: signed.value)
proc captureAuditSigningJob*(signer: WorkSigner, evaluation: AuditEvaluation,
    validator: StateValidatorIndex): WorkJobAdmission =
  ## Capture never accepts raw message bytes, caller validity or replacement report/state tables.
  if signer.signerIdentity.error != WorkSignerError.None or not evaluation.valid:
    return workJobFailure(WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    cancellable: signAudit, signer: signer, auditEvaluation: evaluation,
    auditValidator: validator)))

proc planAssuranceSchedule(data: WorkJobData): WorkJobResult =
  ## All complete-source and C4/C8/C9 copying executes under the existing exclusive native lease.
  let planned = captureAssuranceSchedule(data.assuranceSource, data.assurancePeer,
    data.assuranceWindow, data.assuranceScheduleLimits)
  if planned.error != AssuranceScheduleError.None:
    return WorkJobResult(status: WorkJobResultKind.AssuranceScheduleFailure,
        assuranceScheduleReason: planned)
  WorkJobResult(status: WorkJobResultKind.AssuranceScheduled, assuranceSchedule: planned.value)
proc captureAssuranceScheduleJob*(source: BlockSnapshotResult, local: StateEdKey,
    window: AssuranceWindow, limits: AssuranceScheduleLimits): WorkJobAdmission =
  ## Capture retains only immutable original inputs for this closed runner; no caller-selected code, private key or namespace crosses the boundary.
  if source.error != GenesisError.None or not limits.valid or uint32(window.targetSlot) == 0 or
      array[32, byte](local) == default(array[32, byte]):
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: planAssuranceSchedule, assuranceSource: source, assurancePeer: local,
    assuranceWindow: window, assuranceScheduleLimits: limits)))
proc qualifyIncomingAssurance(data: WorkJobData): WorkJobResult =
  ## This closed operation performs all canonical reads, bit checks and signature work outside native callbacks.
  let checked = qualifyAssuranceDistribution(data.distributionRequest, data.assuranceSource,
    data.assurancePeer, data.assuranceLimits)
  if checked.error != AssuranceDistributionError.None:
    return WorkJobResult(status: WorkJobResultKind.AssuranceFailure, assuranceReason: checked)
  WorkJobResult(status: WorkJobResultKind.AssuranceQualified, assured: checked.value)
proc captureAssuranceDistribution*(request: ReadRequest, source: BlockSnapshotResult,
    peer: StateEdKey, limits: AssuranceDistributionLimits): WorkJobAdmission =
  ## Whole detached-wire admission precedes private capture; all source/result aliases retire before moved submission.
  if not request.valid or request.kind != ReadKind.Assurance or not limits.valid:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if uint64(request.payloadLength) > uint64(limits.wireBytes):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if source.error != GenesisError.None: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: qualifyIncomingAssurance, distributionRequest: detachedReadRequest(request),
    assuranceSource: source, assurancePeer: peer, assuranceLimits: limits)))
proc captureWorkDistribution*(request: ReadRequest, view: ChainView, now: StateTime,
    limits: WorkDistributionLimits): WorkJobAdmission =
  ## Bound the complete raw input before its independent copy; staging view aliases retire before this job is submitted.
  if not request.valid or request.kind != ReadKind.Guarantee:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let size = uint64(request.payloadLength)
  if size > uint64(limits.wireBytes) or size > uint64(MaxReadReplyBytes):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if view.fuzzOnly or view.bestBlock.error != GenesisError.None:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: qualifyDistribution, distributionRequest: detachedReadRequest(request),
        distributionView: view,
    distributionTime: now, distributionLimits: limits)))
proc receiveSharing(data: WorkJobData): WorkJobResult =
  ## The whole received bundle, actual sender/local facts, current view and private key remain on one managed lease.
  let received = receiveSharedWork(data.sharingRequest, data.signingView, data.signingIdentity,
    data.sharingPeer, data.signingTime, data.signer, data.sharingLimits, data.retainedSources)
  if received.error != WorkSharingError.None:
    return WorkJobResult(status: WorkJobResultKind.SharingFailure, sharingReason: received)
  WorkJobResult(status: WorkJobResultKind.Contributed, contribution: received.value)
proc captureWorkSharing*(request: SharedWorkRequest, view: ChainView, local, peer: StateEdKey,
    now: StateTime, signer: WorkSigner, limits: WorkSharingLimits,
    existing: openArray[GuarantorAvailability] = []): WorkJobAdmission =
  ## Independent wire ownership permits native task retirement immediately after submission without racing ARC counters.
  if existing.len > 64: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  let sizes = request.sharingInfo
  if sizes.error != SharingWireError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if uint64(sizes.value.bundleBytes) > uint64(limits.bundleBytes):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  let count = view.retainedCount
  if uint64(count) > uint64(limits.eligibility.anchors.ancestors.headers) or
      count > high(int) div sizeof(BlockSnapshotResult) or
      uint64(view.validationHeaderCount) > uint64(limits.eligibility.anchors.ancestors.headers):
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  let copied = request.detachedSharingRequest
  if copied.error != SharingWireError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: receiveSharing, sharingRequest: copied.value, sharingPeer: peer, signingView: view,
    signingIdentity: local, signingTime: now, signer: signer, sharingLimits: limits,
    retainedSources: copyRetainedSources(existing))))
proc captureWorkAuthorization*(header: WorkSubmissionHeader, state: StateStoreSnapshot,
    parameters: Parameters, limits: WorkSubmissionLimits,
    execution: InputRefinementLimits, recipient: WorkRecipient,
    dutyLimits: WorkDutyLimits, view: ChainView,
    recovery: WorkRecoveryPolicy): WorkJobAdmission =
  ## The staging caller owns the shared graph; every returned alias must retire before it submits the moved job.
  if header.submissionInfo.error != WorkSubmissionError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if not parameters.valid: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not sameStateSnapshot(state, state): return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if recovery.valid and header.submissionInfo.value.kind == WorkSubmissionKind.Package:
    # Bound the captured view container and reject a distinct posterior owner before retaining any source aliases for the worker.
    if uint64(view.retainedCount) > uint64(recovery.limits.catalog.blocks):
      return WorkJobAdmission(status: WorkJobError.LimitExceeded)
    let head = view.bestBlock
    if head.error != GenesisError.None: return WorkJobAdmission(status: WorkJobError.InvalidInput)
    if not sameStateSnapshot(head.value.stateSnapshot, state): return WorkJobAdmission(
        status: WorkJobError.InvalidInput)
  let source = WorkSource(header: header, state: state, parameters: parameters, limits: limits,
      execution: execution, recipient: recipient, dutyLimits: dutyLimits, view: view,
      recovery: recovery)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: authorize, source: source)))
proc captureWorkAuthorization*(header: WorkSubmissionHeader, state: StateStoreSnapshot,
    parameters: Parameters, limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recipient = default(WorkRecipient), dutyLimits = default(WorkDutyLimits)): WorkJobAdmission =
  ## Computation-only callers need no chain context; keep the complex private variant default inside its owning factory.
  ## The pinned compiler rejects direct variant defaults in omitted arguments; see NIM-006.
  captureWorkAuthorization(header, state, parameters, limits, execution, recipient, dutyLimits,
    genesisView(unavailableGenesis()), default(WorkRecoveryPolicy))
proc copied(input: openArray[byte]): seq[byte] =
  ## Bounded callers receive independent bytes; later input mutation cannot change a pending job.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
proc captureWorkRecoveryPacket*(context: AuthorizedWorkContext, recovery: WorkRecovery,
    version: uint64, validator: StateValidatorIndex, wire: openArray[byte]): WorkJobAdmission =
  ## Deep-copy only bounded raw bytes; caller progress/context aliases retire before the submitted closed CPU job executes.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let request = recovery.recoveryRequest(validator)
  if request.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if request.value.version != version: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(request.value.maximum): return WorkJobAdmission(
      status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: recoverPacket, context: context, recovery: recovery, recoveryVersion: version,
    validator: validator, segments: copied(wire))))
proc captureWorkRecoveryRetry*(context: AuthorizedWorkContext,
    recovery: WorkRecovery): WorkJobAdmission =
  ## Only matching private progress can change trust mode; no raw peer response or caller flag fabricates proven packets.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let info = recovery.recoveryInfo
  if info.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if info.value.complete or info.value.proven: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: retryRecovery, context: context, recovery: recovery)))
proc captureRecoveredWorkPackage*(context: AuthorizedWorkContext, recovery: WorkRecovery,
    extrinsics: openArray[byte]): WorkJobAdmission =
  ## Only complete matching private progress can enter the original full input/refinement pipeline.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let info = recovery.recoveryInfo
  if info.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if not info.value.complete: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if extrinsics.len != data.grant.submissionInfo.value.extrinsicBytes: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: completeRecovered, context: context, recovery: recovery, extrinsics: copied(extrinsics))))
proc captureWorkBundle*(context: AuthorizedWorkContext, extrinsics, segments,
    proofs: openArray[byte]): WorkJobAdmission =
  ## Preflight complete message geometry before copying any body bytes under the shared graph gate.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Bundle: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if extrinsics.len != info.extrinsicBytes or segments.len != info.segmentBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if proofs.len > info.importCount*385: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if info.packageBytes+extrinsics.len+segments.len+proofs.len > 13904950:
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context,
    extrinsics: copied(extrinsics), segments: copied(segments), proofs: copied(proofs))))
proc captureFetchedWorkPackage*(context: AuthorizedWorkContext, extrinsics,
    reply: openArray[byte]): WorkJobAdmission =
  ## Copy only bounded untrusted bytes; original plan verification and refinement run together on the exclusive CPU worker.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Package or extrinsics.len != info.extrinsicBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if reply.len > 8+info.segmentBytes+info.importCount*385:
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context, fetched: true,
    extrinsics: copied(extrinsics), segments: copied(reply))))
proc captureWorkPackage*(context: AuthorizedWorkContext, extrinsics: openArray[byte],
    imports: openArray[seq[VerifiedImport]], lookup: openArray[SegmentLookup]): WorkJobAdmission =
  ## CE133 receives separately verified availability witnesses; exact original binding still occurs on the CPU.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Package or extrinsics.len != info.extrinsicBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if imports.len > 16 or lookup.len > 8: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  var count = 0
  for row in imports:
    if row.len > 3072-count: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
    count += row.len
  var rows = newSeq[seq[VerifiedImport]](imports.len)
  for item in 0..<imports.len:
    # Descriptor copies own independent rows; each verified leaf is itself immutable acyclic storage.
    rows[item] = newSeq[VerifiedImport](imports[item].len)
    for index in 0..<imports[item].len: rows[item][index] = imports[item][index]
  var dictionary = newSeq[SegmentLookup](lookup.len)
  for index in 0..<lookup.len: dictionary[index] = lookup[index]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context,
    extrinsics: copied(extrinsics), imports: rows, lookup: dictionary)))
proc executeWorkSubmission*(job: WorkSubmissionJob, control: AssuranceScanControl = default(
    AssuranceScanControl)): WorkJobResult =
  ## The worker invokes a private genuine capability outside native callbacks and retires all activation aliases before Done.
  let data = job.data
  if data == nil: return default(WorkJobResult)
  let cancellable = data.cancellable
  if cancellable != nil: return cancellable(data, control)
  let run = data.run
  if run == nil: return default(WorkJobResult)
  run(data)
