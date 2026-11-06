# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private full audit state belongs to Services. Controllers receive opaque host selectors and detached completion metadata; every source-bearing operation requires the shared graph gate.
import ./audit_branches
import ../jamnp-s/[audit_registry, audit_origin, audit_context, audit_evaluation, audit_recovery,
    work_signer, availability_proof, audit_fetch, judgment_receipt, audit_participation, audit_publication]
from ../codec/state/safrole import StateValidatorIndex, StateEdKey
import ../chain/[genesis, provider]
import ./proof/[worker, work_submission]

type
  ManagedAuditKind* {.pure.} = enum ## No failed or cancelled completion carries a successful origin or execution prefix.
    Uninitialized, OriginRetained, Evaluated, Cancelled, OriginFailure, EvaluationFailure,
    RegistryFailure, RecoveryFailure, JudgmentSigned, SigningFailure, FetchPlanned, FetchFailure,
      ShardVerified, ShardFailure, JudgmentsRetained, JudgmentReceiptFailure, ParticipationPlanned,
        ParticipationFailure, PublicationPrepared, PublicationFailure, InvalidResult
  RetainedJudgment* = object ## Source-free original signed record and an optional exact private negative-report selector carry no complete map or local evaluation authority.
    record: QualifiedJudgment
    source: AuditOriginId
  ManagedAuditCompletion* = object ## Fixed metadata and genuine failed children survive unrelated leases without borrowing full canonical state.
    case status: ManagedAuditKind
    of PublicationPrepared:
      publication: AuditPublication
      publicationId: AuditOriginId
      publicationOrdinal: int
    of PublicationFailure: publicationReason: AuditPublicationResult[AuditPublication]
    of ParticipationPlanned: participation: AuditParticipationPlan
    of ParticipationFailure: participationReason: AuditParticipationResult[AuditParticipationPlan]
    of JudgmentsRetained:
      judgments: seq[RetainedJudgment]
    of JudgmentReceiptFailure: judgmentReason: JudgmentReceiptResult[PreparedJudgmentBatch]
    of OriginRetained:
      originId: AuditOriginId
      originFacts: AuditOriginInfo
    of Evaluated:
      evaluationId: AuditOriginId
      evaluationOrdinal: int
      evaluationFacts: AuditEvaluationInfo
    of JudgmentSigned:
      signedId: AuditOriginId
      signedOrdinal: int
      signedValue: SignedAuditJudgment
    of ShardVerified: shardValue: VerifiedAvailabilityTransfer
    of ShardFailure: shardReason: AuditFetchResult[VerifiedAvailabilityTransfer]
    of FetchPlanned: fetchValue: AuditFetchPlan
    of FetchFailure: fetchReason: AuditFetchResult[AuditFetchPlan]
    of RecoveryFailure: recoveryReason: AuditRecoveryResult[AuditRecoveryEvidence]
    of SigningFailure: signingReason: AuditSigningResult[SignedAuditJudgment]
    of OriginFailure: originReason: AuditOriginResult[AuditBlockOrigin]
    of EvaluationFailure: evaluationReason: AuditEvaluationResult[AuditEvaluation]
    of RegistryFailure: registryReason: AuditRegistryError
    else: discard # No private source or caller-selected validity bit.
  AuditOperation {.pure.} = enum
    Idle, Origin, DeclarationOrigin, Evaluation, Signing, Fetch, Shard, JudgmentReceipt, Participation
  ManagedAuditState* = object ## No native owner or backpointer: registry pins form an acyclic graph and retire only after all Services borrowers join.
    registry: AuditOriginRegistry
    operation: AuditOperation
    ticket: ProofWorkerTicket
    selected: AuditOriginId
    ordinal: int
    ready: bool
    completion: ManagedAuditCompletion
func preparedPublication*(outcome: ManagedAuditCompletion): AuditPublication {.requires: outcome.status ==
    ManagedAuditKind.PublicationPrepared.} =
  ## Public signed record and independently frozen full report have no private source/key alias.
  outcome.publication
func publicationId*(outcome: ManagedAuditCompletion): AuditOriginId {.requires: outcome.status ==
    ManagedAuditKind.PublicationPrepared.} =
  ## Exact host correlation does not lend the original complete state.
  outcome.publicationId
func publicationOrdinal*(outcome: ManagedAuditCompletion): int {.requires: outcome.status ==
    ManagedAuditKind.PublicationPrepared.} =
  ## Preserve the original privately selected report position.
  outcome.publicationOrdinal
func publicationError*(outcome: ManagedAuditCompletion): AuditPublicationResult[
    AuditPublication] {.requires: outcome.status == ManagedAuditKind.PublicationFailure.} =
  ## Failed output admission/encoding/signing never releases an accepted prefix.
  outcome.publicationReason
func participationPlan*(outcome: ManagedAuditCompletion): AuditParticipationPlan {.requires: outcome.status ==
    ManagedAuditKind.ParticipationPlanned.} =
  ## Actual source-free roles and original signing indices are safe during unrelated later leases.
  outcome.participation
func participationError*(outcome: ManagedAuditCompletion): AuditParticipationResult[
    AuditParticipationPlan] {.requires: outcome.status == ManagedAuditKind.ParticipationFailure.} =
  ## No failed plan exposes an earlier recipient or local index prefix.
  outcome.participationReason
func judgment*(record: RetainedJudgment): QualifiedJudgment =
  ## The fixed qualified original record is safe to cache during unrelated source leases.
  record.record
func originId*(record: RetainedJudgment): AuditOriginId =
  ## Positive records have an invalid absent selector; negative records identify only the actual privately retained source.
  record.source
func retainedJudgmentCount*(outcome: ManagedAuditCompletion): int {.requires: outcome.status ==
    ManagedAuditKind.JudgmentsRetained.} =
  ## The returned complete batch never aliases full state or key storage.
  outcome.judgments.len
func retainedJudgmentAt*(outcome: ManagedAuditCompletion,
    ordinal: int): RetainedJudgment {.requires: outcome.status ==
    ManagedAuditKind.JudgmentsRetained and ordinal >= 0 and ordinal < outcome.judgments.len.} =
  ## Copy one original record and host selector after whole-batch qualification and retention succeeded.
  outcome.judgments[ordinal]
func judgmentReceiptError*(outcome: ManagedAuditCompletion): JudgmentReceiptResult[
    PreparedJudgmentBatch] {.requires: outcome.status == ManagedAuditKind.JudgmentReceiptFailure.} =
  ## A failed result has no prepared source or qualified judgment prefix.
  outcome.judgmentReason
func kind*(outcome: ManagedAuditCompletion): ManagedAuditKind =
  ## Read the tag before selecting success metadata or the actual failure.
  outcome.status
func verifiedShard*(outcome: ManagedAuditCompletion): VerifiedAvailabilityTransfer {.requires: outcome.status ==
    ManagedAuditKind.ShardVerified.} =
  ## Complete original-coordinate proof ownership carries no private source or negative judgment capability.
  outcome.shardValue
func shardError*(outcome: ManagedAuditCompletion): AuditFetchResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status == ManagedAuditKind.ShardFailure.} =
  ## Preserve the actual failed transcript/proof result after exclusive collection.
  outcome.shardReason
func fetchPlan*(outcome: ManagedAuditCompletion): AuditFetchPlan {.requires: outcome.status ==
    ManagedAuditKind.FetchPlanned.} =
  ## Detached target records retain no aliases to the registry's original complete state or report.
  outcome.fetchValue
func fetchError*(outcome: ManagedAuditCompletion): AuditFetchResult[
    AuditFetchPlan] {.requires: outcome.status == ManagedAuditKind.FetchFailure.} =
  ## Missing routing facts never turn into a negative evaluation.
  outcome.fetchReason
func originId*(outcome: ManagedAuditCompletion): AuditOriginId {.requires: outcome.status ==
    ManagedAuditKind.OriginRetained.} =
  ## Host-only namespace never enters worker source graphs.
  outcome.originId
func originInfo*(outcome: ManagedAuditCompletion): AuditOriginInfo {.requires: outcome.status ==
    ManagedAuditKind.OriginRetained.} =
  ## Cached fixed facts grant neither execution nor signing authority.
  outcome.originFacts
func evaluationInfo*(outcome: ManagedAuditCompletion): AuditEvaluationInfo {.requires: outcome.status ==
    ManagedAuditKind.Evaluated.} =
  ## Copy actual retained evaluation facts; mutation cannot change its private capability.
  outcome.evaluationFacts
func evaluationId*(outcome: ManagedAuditCompletion): AuditOriginId {.requires: outcome.status ==
    ManagedAuditKind.Evaluated.} =
  ## Identify the original registry namespace without returning its source.
  outcome.evaluationId
func evaluationOrdinal*(outcome: ManagedAuditCompletion): int {.requires: outcome.status ==
    ManagedAuditKind.Evaluated.} =
  ## Preserve the original checked report ordinal.
  outcome.evaluationOrdinal
func originError*(outcome: ManagedAuditCompletion): AuditOriginResult[
    AuditBlockOrigin] {.requires: outcome.status == ManagedAuditKind.OriginFailure.} =
  ## Only an actual failed origin result is retained here.
  outcome.originReason
func evaluationError*(outcome: ManagedAuditCompletion): AuditEvaluationResult[
    AuditEvaluation] {.requires: outcome.status == ManagedAuditKind.EvaluationFailure.} =
  ## Only an actual failed execution result is retained here.
  outcome.evaluationReason
func registryError*(outcome: ManagedAuditCompletion): AuditRegistryError {.requires: outcome.status ==
    ManagedAuditKind.RegistryFailure.} =
  ## Preserve the actual retention refusal without exposing a completed prefix.
  outcome.registryReason
func signedJudgment*(outcome: ManagedAuditCompletion): SignedAuditJudgment {.requires: outcome.status ==
    ManagedAuditKind.JudgmentSigned.} =
  ## Complete output is source-free and cannot expose its original private evaluation or key.
  outcome.signedValue
func signingId*(outcome: ManagedAuditCompletion): AuditOriginId {.requires: outcome.status ==
    ManagedAuditKind.JudgmentSigned.} =
  ## Preserve exact host-only operation correlation without source aliases.
  outcome.signedId
func signingOrdinal*(outcome: ManagedAuditCompletion): int {.requires: outcome.status ==
    ManagedAuditKind.JudgmentSigned.} =
  ## Keep the selected original report ordinal for outgoing publication accounting.
  outcome.signedOrdinal
func signingError*(outcome: ManagedAuditCompletion): AuditSigningResult[
    SignedAuditJudgment] {.requires: outcome.status == ManagedAuditKind.SigningFailure.} =
  ## A genuine failed signing operation has no reusable signature prefix.
  outcome.signingReason
func recoveryError*(outcome: ManagedAuditCompletion): AuditRecoveryResult[
    AuditRecoveryEvidence] {.requires: outcome.status == ManagedAuditKind.RecoveryFailure.} =
  ## Local/packet/arithmetic refusal exposes no authenticated prefix.
  outcome.recoveryReason
func configured*(state: ManagedAuditState): bool =
  ## Host-only optional activation flag grants no state alias or completed evaluation.
  state.registry.configured
func occupied*(state: ManagedAuditState): bool =
  ## Scalar capacity includes unconsumed detached completion, never silently overwritten by another job.
  state.operation != AuditOperation.Idle or state.ready
func active*(state: ManagedAuditState): bool =
  ## Host-only operation state may be read while its worker runs.
  state.operation != AuditOperation.Idle
func matches*(state: ManagedAuditState, ticket: ProofWorkerTicket): bool =
  ## Equality of private ticket namespace and generation cannot authorize a default idle selector.
  state.occupied and state.ticket == ticket
proc releaseDispute*(state: var ManagedAuditState, id: AuditOriginId): bool =
  ## No active or unconsumed managed completion can refer to the released row.
  not state.occupied and state.registry.releaseDispute(id)
proc releaseDeclaration*(state: var ManagedAuditState, id: AuditOriginId): bool =
  ## No managed worker or unconsumed completion may still refer to the source.
  not state.occupied and state.registry.releaseDeclaration(id)
proc expireBefore*(state: var ManagedAuditState, floor: uint64): bool =
  ## Retire only after exact collection has released every managed result and source borrow.
  if state.occupied: return false
  state.registry.expireBefore(floor)
  true
proc configure*(state: var ManagedAuditState, limits: AuditRegistryLimits): bool =
  ## Services first establishes idle complete-state readiness.
  if state.occupied: return false
  state.registry.configure(limits)
proc retain*(state: var ManagedAuditState, origin: AuditBlockOrigin,
    trusted: BlockSnapshotResult, forDeclaration = false): AuditRegistryResult[AuditOriginId] =
  ## The trusted block must be selected independently from Services canonical history, never supplied by a controller.
  if not origin.matchesTrustedBlock(trusted): return auditRegistryFailure[AuditOriginId](
      AuditRegistryError.InvalidSource)
  state.registry.retain(origin, forDeclaration)
proc stageEvaluation*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    wire: openArray[byte], limits: AuditEvaluationLimits): WorkJobAdmission =
  ## Select only the private registered source under the idle graph gate; public metadata cannot install a replacement capability.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let target = state.registry.target(id, ordinal)
  if target.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditEvaluationJob(target.value, wire, limits)
proc stageRecoveryEvaluation*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    packets: openArray[VerifiedAvailabilityTransfer], recovery: AuditRecoveryLimits,
    evaluation: AuditEvaluationLimits): WorkJobAdmission =
  ## Only private registry lookup may select the full origin; checked packet provenance cannot substitute another original target.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let target = state.registry.target(id, ordinal)
  if target.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditRecoveryEvaluationJob(target.value, packets, recovery, evaluation)
proc stageFetch*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    limits: AuditFetchLimits): WorkJobAdmission =
  ## Controllers choose a host selector only; the private registry selects the genuine original target under the shared gate.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let target = state.registry.target(id, ordinal)
  if target.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditFetchJob(target.value, limits)
proc stageParticipation*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    current: BlockSnapshotResult, identity: StateEdKey,
        limits: AuditParticipationLimits): WorkJobAdmission =
  ## Only a private registered target supplies original auditor authority; the foreground host cannot substitute a current key index or source map.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let target = state.registry.target(id, ordinal)
  if target.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditParticipationJob(target.value, current, identity, limits)
proc admitParticipation*(state: var ManagedAuditState, ticket: ProofWorkerTicket) =
  ## Exact host correlation keeps source-bearing planning input behind the ordinary private collector.
  state.operation = AuditOperation.Participation
  state.ticket = ticket
proc stageSigning*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    signer: WorkSigner, validator: StateValidatorIndex): WorkJobAdmission =
  ## No public evaluation metadata or externally supplied capability reaches the private key: select only Services' retained completed slot.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let found = state.registry.evaluation(id, ordinal)
  if found.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditSigningJob(signer, found.value, validator)
proc stagePublication*(state: ManagedAuditState, id: AuditOriginId, ordinal: int,
    signer: WorkSigner, validator: StateValidatorIndex,
        limits: AuditPublicationLimits): WorkJobAdmission =
  ## Only the actual private registered completed evaluation can reach publication preparation and the signer.
  if state.occupied: return workJobFailure(WorkJobError.InvalidInput)
  let selected = state.registry.evaluation(id, ordinal)
  if selected.error != AuditRegistryError.None: return workJobFailure(WorkJobError.InvalidInput)
  captureAuditPublicationJob(signer, selected.value, validator, limits)
proc admitJudgmentReceipt*(state: var ManagedAuditState, ticket: ProofWorkerTicket) =
  ## Exact operation correlation prevents generic completion from exposing source-bearing receipt output.
  state.operation = AuditOperation.JudgmentReceipt
  state.ticket = ticket
proc retainJudgments(state: var ManagedAuditState, prepared: PreparedJudgmentBatch,
    source: ChainView, branches: AuditBranches): ManagedAuditCompletion =
  ## Independently bind every original membership/support/execution context before atomically installing any negative origin.
  if not prepared.valid: return ManagedAuditCompletion(status: ManagedAuditKind.InvalidResult)
  var origins: seq[AuditDisputeOrigin] = @[]
  for ordinal in 0..<prepared.negativeCount:
    # All actual trust checks precede registry mutation, including a late foreign source in an otherwise valid batch.
    let origin = prepared.negativeOriginAt(ordinal).value
    var trusted = origin.matchesTrustedDispute(source)
    if not trusted:
      for branch in branches.liveViews(source):
        if origin.matchesTrustedDispute(branch):
          trusted = true
          break
    if not trusted:
      return ManagedAuditCompletion(status: ManagedAuditKind.RegistryFailure,
          registryReason: AuditRegistryError.InvalidSource)
    origins.add(origin)
  let retained = state.registry.retainDisputes(origins)
  if retained.error != AuditRegistryError.None:
    return ManagedAuditCompletion(status: ManagedAuditKind.RegistryFailure,
        registryReason: retained.error)
  var records = newSeq[RetainedJudgment](prepared.len)
  var negative = 0
  for ordinal in 0..<records.len:
    # Only the complete successful atomic registry result releases source-free qualified records to the controller.
    let record = prepared.judgmentAt(ordinal).value
    var selected = default(AuditOriginId)
    if not record.judgmentRecord.valid:
      selected = retained.value[negative]
      inc negative
    records[ordinal] = RetainedJudgment(record: record, source: selected)
  ManagedAuditCompletion(status: ManagedAuditKind.JudgmentsRetained, judgments: move(records))
proc admitOrigin*(state: var ManagedAuditState, ticket: ProofWorkerTicket, forDeclaration: bool) =
  ## Call only after successful native admission; no source graph is accessed here.
  state.operation = if forDeclaration: AuditOperation.DeclarationOrigin else: AuditOperation.Origin
  state.ticket = ticket
proc admitEvaluation*(state: var ManagedAuditState, ticket: ProofWorkerTicket,
    id: AuditOriginId, ordinal: int) =
  ## Host-only selectors never become worker inputs and cannot mutate the retained full origin.
  state.operation = AuditOperation.Evaluation
  state.ticket = ticket
  state.selected = id
  state.ordinal = ordinal
proc admitSigning*(state: var ManagedAuditState, ticket: ProofWorkerTicket,
    id: AuditOriginId, ordinal: int) =
  ## Only host namespace/scalar state changes after the worker takes its immutable source/key lease.
  state.admitEvaluation(ticket, id, ordinal)
  state.operation = AuditOperation.Signing
proc admitFetch*(state: var ManagedAuditState, ticket: ProofWorkerTicket,
    id: AuditOriginId, ordinal: int) =
  ## Host-only correlation changes without reading a leased original graph.
  state.admitEvaluation(ticket, id, ordinal)
  state.operation = AuditOperation.Fetch
proc admitShard*(state: var ManagedAuditState, ticket: ProofWorkerTicket) =
  ## A source-free verification still uses the exact private collector and fixed shared worker gate.
  state.ticket = ticket
  state.operation = AuditOperation.Shard
proc finish*(state: var ManagedAuditState, completed: ProofWorkerCompletion,
    source: ChainView, branches = default(AuditBranches)) =
  ## Exact native collection has ended the borrow, but Services keeps RPC paused until all private results are bound and cached.
  if not state.active or completed.kind == ProofWorkerCompletionKind.Uninitialized: return
  state.completion = ManagedAuditCompletion(status: ManagedAuditKind.InvalidResult)
  if completed.kind == ProofWorkerCompletionKind.Cancelled:
    state.completion = ManagedAuditCompletion(status: ManagedAuditKind.Cancelled)
  elif completed.kind == ProofWorkerCompletionKind.WorkSubmitted:
    let work = completed.workSubmissionValue
    case state.operation
    of AuditOperation.Participation:
      if work.kind == WorkJobResultKind.AuditParticipationPlanned:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.ParticipationPlanned,
          participation: work.plannedAuditParticipation)
      elif work.kind == WorkJobResultKind.AuditParticipationFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.ParticipationFailure,
          participationReason: work.auditParticipationError)
    of AuditOperation.JudgmentReceipt:
      if work.kind == WorkJobResultKind.JudgmentReceiptFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.JudgmentReceiptFailure,
          judgmentReason: work.judgmentReceiptError)
      elif work.kind == WorkJobResultKind.JudgmentReceiptPrepared:
        state.completion = state.retainJudgments(work.preparedJudgmentReceipt, source, branches)
    of AuditOperation.Origin, AuditOperation.DeclarationOrigin:
      if work.kind == WorkJobResultKind.AuditOriginPreparationFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.OriginFailure,
          originReason: work.auditOriginPreparationError)
      elif work.kind == WorkJobResultKind.AuditOriginPrepared:
        let origin = work.preparedAuditOrigin
        let info = origin.originInfo.value
        let selected = source.blockAt(info.blockHash)
        let trusted = if selected.error == GenesisError.None: selected
          else: branches.parentView(source, info.blockHash).blockAt(info.blockHash)
        let retained = state.retain(origin, trusted, state.operation ==
            AuditOperation.DeclarationOrigin)
        if retained.error == AuditRegistryError.None:
          state.completion = ManagedAuditCompletion(status: ManagedAuditKind.OriginRetained,
            originId: retained.value, originFacts: info)
        else:
          state.completion = ManagedAuditCompletion(status: ManagedAuditKind.RegistryFailure,
            registryReason: retained.error)
    of AuditOperation.Evaluation:
      if work.kind == WorkJobResultKind.AuditRecoveryFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.RecoveryFailure,
            recoveryReason: work.auditRecoveryError)
      elif work.kind == WorkJobResultKind.AuditEvaluationFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.EvaluationFailure,
          evaluationReason: work.auditEvaluationError)
      elif work.kind == WorkJobResultKind.AuditEvaluated:
        let evaluation = work.evaluatedAudit
        let remembered = state.registry.rememberEvaluation(state.selected, state.ordinal, evaluation)
        if remembered.error == AuditRegistryError.None:
          state.completion = ManagedAuditCompletion(status: ManagedAuditKind.Evaluated,
            evaluationId: state.selected, evaluationOrdinal: state.ordinal,
            evaluationFacts: evaluation.evaluationInfo.value)
        else:
          state.completion = ManagedAuditCompletion(status: ManagedAuditKind.RegistryFailure,
            registryReason: remembered.error)
    of AuditOperation.Signing:
      if work.kind == WorkJobResultKind.AuditPublicationPrepared:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.PublicationPrepared,
          publication: work.preparedAuditPublication, publicationId: state.selected,
          publicationOrdinal: state.ordinal)
      elif work.kind == WorkJobResultKind.AuditPublicationFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.PublicationFailure,
          publicationReason: work.auditPublicationError)
      elif work.kind == WorkJobResultKind.AuditSigningFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.SigningFailure,
            signingReason: work.auditSigningError)
      elif work.kind == WorkJobResultKind.AuditSigned:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.JudgmentSigned,
          signedId: state.selected, signedOrdinal: state.ordinal, signedValue: work.signedAudit)
    of AuditOperation.Shard:
      if work.kind == WorkJobResultKind.AuditShardVerified:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.ShardVerified,
          shardValue: work.verifiedAuditShard)
      elif work.kind == WorkJobResultKind.AuditShardVerificationFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.ShardFailure,
          shardReason: work.auditShardVerificationError)
    of AuditOperation.Fetch:
      if work.kind == WorkJobResultKind.AuditFetchPlanned:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.FetchPlanned,
          fetchValue: work.plannedAuditFetch)
      elif work.kind == WorkJobResultKind.AuditFetchPlanningFailure:
        state.completion = ManagedAuditCompletion(status: ManagedAuditKind.FetchFailure,
          fetchReason: work.auditFetchPlanningError)
    of AuditOperation.Idle: discard
  state.operation = AuditOperation.Idle
  state.selected = default(AuditOriginId)
  state.ready = true
proc collect*(state: var ManagedAuditState, ticket: ProofWorkerTicket): ManagedAuditCompletion =
  ## Only the exact completed selector consumes detached output; early, foreign and stale controls leave it intact.
  if not state.ready or not state.matches(ticket): return default(ManagedAuditCompletion)
  result = move(state.completion)
  state.ready = false
  state.ticket = default(ProofWorkerTicket)
proc stop*(state: var ManagedAuditState) =
  ## Joined proof shutdown revokes pending controls without dropping full pins that other Services workers might still borrow.
  state.operation = AuditOperation.Idle
  state.ready = false
  state.ticket = default(ProofWorkerTicket)
  state.selected = default(AuditOriginId)
  state.ordinal = 0
  state.completion = default(ManagedAuditCompletion)
proc clear*(state: var ManagedAuditState) =
  ## All worker families, disk IO and callbacks must have joined before retained full-state aliases retire.
  state.stop()
  state.registry.clear()
