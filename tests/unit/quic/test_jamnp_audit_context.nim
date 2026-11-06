# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_audit_context_arc_release"}

## Actual published available reports, header entropy and original prior-role credentials define audit context; absent bodies and assignment disappearance cannot substitute authority.
import std/[assertions, syncio, monotimes, times, posix/posix]
import ../../../src/app/[services, options, audit_state]
import ../../../src/app/proof/[worker, work_submission, ticket_production]
import ../../../src/jamnp-s/[audit_validation, audits, read_stream]
from ../../../src/codec/assurances import ValidatorCount, CoreCount
from ../../../src/codec/disputes import JudgeIndex
import ../../../src/rpc/server
import ../../../src/jamnp-s/assurance_store
import ../../../src/jamnp-s/[audit_context, audit_receipt, audit_origin, audit_evaluation,
    audit_registry, work_signer, audit_fetch, audit_participation]
import ../../../src/chain/[genesis, provider, parameters]
from ../../../src/state/store import sameStateSnapshot
from ../../../src/codec/state/trie import TrieNodeLimit
import ../../../src/codec/[bounded, owned, report_owned, block_codec]
import ../../../src/codec/state/[safrole, layout]
import "../../../src/state/block/transition"
import "../../../src/state/block/admission"
import ../../../src/crypto/primitives
import ../../support/[jamnp_audit_evaluation, jamnp_audit_faults, jamnp_audit_signing,
    jamnp_audit_acquisition, assurance_signer_context]
import ../../support/[jamnp_audit_context, arc_evidence, current_application_context,
    jamnp_audit_validation, jamnp_topology_fixture]
import ../../support/jamnp_audit_branch_network
import ../../support/jamnp_audit_participation
proc checked(fixture: AuditContextFixture) =
  ## Canonical availability output selects cores0/1 and exact original credentials after genuine accumulated publication.
  let selected = captureAuditContext(fixture.view, fixture.blockHash, auditLimits())
  assert selected.error == AuditContextError.None, "genuine complete audit context: " &
      $selected.error
  let context = selected.value
  let info = context.contextInfo.value
  assert uint64(info.cores) == 3 and uint64(info.maximumCores) == 3, "active selection domain remains distinct from configured maximum"
  assert uint32(info.slot) == 3 and uint32(info.parentSlot) == 2 and info.auditors == 9 and
      info.reports == 2,
    "genuine new availability and original prior-C8 population"
  assert context.matches(fixture.view), "exact retained child/body and predecessor authority"
  assert not context.matches(fixture.prior), "missing successor cannot revive context"
  for ordinal in 0..<info.reports:
    # Original report bytes independently define the expected identity; credential count/slot remain those actually admitted.
    let guarantee = context.auditGuarantee(ordinal).value
    let report = guarantee.report.ownedReportInfo.value
    let core = context.availableCore(ordinal).value
    assert uint64(core) == uint64(ordinal) and uint64(report.core) == uint64(ordinal), "original newly available core order"
    var bytes = newSeq[byte](report.consumed)
    assert guarantee.report.encodeOwnedReport(bytes).error == OwnershipError.None, "independent full report encoding"
    assert array[32, byte](context.auditReportHash(ordinal).value) == array[32, byte](blake2b256(
        bytes).value), "exact canonical report identity"
    assert guarantee.credentialCount in 2..3, "authentic original guarantee quorum"
    for credential in 0..<guarantee.credentialCount:
      assert context.auditGuarantor(ordinal, credential).error == AuditContextError.None, "actual original-epoch guarantor metadata"
  let original = fixture.prior.bestBlock.value
  for ordinal in 0..<info.auditors:
    # The prior C8 codec supplies an independent ordinal/key check; null or repeated positions may not be compressed.
    let roster = decodeStateValidators(original.lookup(chapterKey(StateChapter(8))).value.bytes,
      auditLimits().availability.rosters).value.value
    let expected = roster.validatorAt(StateValidatorIndex(uint64(ordinal))).value
    assert array[32, byte](context.auditorAt(ordinal).value.ed25519) == array[32, byte](
        expected.ed25519), "exact original auditor ordinal"
  assert context.auditorAt(-1).error == AuditContextError.InvalidIndex and context.auditorAt(
      9).error == AuditContextError.InvalidIndex,
    "auditor lookup is bounded"
  assert context.auditGuarantee(2).error == AuditContextError.InvalidIndex, "no nonexistent available prefix"
  assert captureAuditContext(fixture.prior, fixture.blockHash, auditLimits()).error ==
      AuditContextError.UnknownBlock,
    "unknown block cannot invent newly available reports"
  assert captureAuditContext(fixture.prior, original.blockHash, auditLimits()).error ==
      AuditContextError.MissingBody,
    "header-only legacy publication supplies no complete block body"
  assert captureAuditContext(fixture.view, fixture.blockHash, default(AuditContextLimits)).error ==
      AuditContextError.InvalidPolicy,
    "default policy has no authority"
  var limited = auditLimits()
  limited.bodyBytes = ByteLimit(1)
  assert captureAuditContext(fixture.view, fixture.blockHash, limited).error ==
      AuditContextError.LimitExceeded,
    "body preflight refuses before decoding"
  limited = auditLimits()
  limited.hashes = ElementLimit(3)
  assert captureAuditContext(fixture.view, fixture.blockHash, limited).error ==
      AuditContextError.LimitExceeded,
    "whole two-report comparison count is reserved before hashing"
  limited = auditLimits()
  limited.outputBytes = ByteLimit(1)
  assert captureAuditContext(fixture.view, fixture.blockHash, limited).error ==
      AuditContextError.LimitExceeded,
    "source-free output capacity is explicit"
  limited = auditLimits()
  limited.workspaceBytes = ByteLimit(1000000)
  assert captureAuditContext(fixture.view, fixture.blockHash, limited).error ==
      AuditContextError.LimitExceeded,
    "copied chapters alone cannot fund whole-map descriptors and fixed transition scratch"

proc branchPrefixChecks(fixture: AuditContextFixture) =
  ## A trusted prefix reuses exact original owners and excludes later selected state.
  let parent = fixture.prior.bestBlock.value
  let prefix = fixture.view.retainedPrefix(parent.blockHash)
  assert prefix.error == ViewAdvanceError.None and sameChainView(prefix.value, fixture.prior)
  assert sameStateSnapshot(prefix.value.bestBlock.value.stateSnapshot, parent.stateSnapshot)
  assert prefix.value.blockAt(fixture.blockHash).error == GenesisError.Unavailable
  let finalized = fixture.view.finalizeView(fixture.blockHash).value
  assert finalized.retainedPrefix(parent.blockHash).error == ViewAdvanceError.NotChild
  assert fixture.view.retainedPrefix(default(genesis.BlockHash)).error ==
      ViewAdvanceError.InvalidSnapshot, "no independently retained parent"
proc hostileBody(fixture: AuditContextFixture) =
  ## A structurally retained same-header/same-map body is not authenticated merely because its byte framing succeeds.
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let child = fixture.view.bestBlock.value
  var bytes = child.blockBody
  assert bytes.len > 4 and bytes[^1] == 0 and bytes[^2] == 0 and bytes[^3] == 0,
    "independent final empty disputes vectors"
  bytes[bytes.len-4] = bytes[bytes.len-4] xor 1 # Corrupt the final real assurance signature while preserving structural record lengths.
  let attached = withBlockBody(child, bytes)
  assert attached.error == GenesisError.None, "structural helper does not authenticate extrinsic commitment"
  let changed = fixture.prior.advanceView(attached)
  assert changed.error == ViewAdvanceError.None, "test-only hostile retained-body witness"
  assert not context.matches(changed.value), "exact body digest prevents same-header context revival"
  let rejected = captureAuditContext(changed.value, fixture.blockHash, auditLimits())
  assert rejected.error == AuditContextError.TransitionFailure,
    "real consensus prefix rejects hostile body before any new obligation"
  assert rejected.transitionError.error == BlockTransitionError.AdmissionFailure and
    rejected.transitionError.admissionError == BlockAdmissionError.InvalidExtrinsicHash,
    "actual committed-extrinsic mismatch remains selected"
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Test-owned startup files are independent from any other running suite.
proc stopNow(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Immediate trusted cancellation has no external graph or callback lifetime.
  true
proc cancellation(fixture: AuditContextFixture) =
  ## Execution-only control can stop both direct and closed captured operations without publishing accepted context storage.
  let control = assuranceScanControl(stopNow, nil)
  assert captureAuditContext(fixture.view, fixture.blockHash, auditLimits(), control).error ==
      AuditContextError.Cancelled,
    "immediate context cancellation exposes no metadata prefix"
  let captured = captureAuditPlanning(fixture.view, fixture.blockHash, auditLimits())
  assert captured.error == WorkJobError.None, "closed immutable canonical audit capture"
  let completed = executeWorkSubmission(captured.value, control)
  assert completed.kind == WorkJobResultKind.AuditPlanningFailure and
      completed.auditPlanningError.error == AuditContextError.Cancelled,
    "a queued input never stores a caller-supplied cancellation callback"
proc originCycle(fixture: AuditContextFixture) =
  ## Actual complete predecessor ownership survives only through immutable origin/report capabilities and retires with the last target alias.
  let captured = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
      auditOriginLimits())
  assert captured.error == AuditOriginError.None, "genuine bounded execution origin: " &
      $captured.error
  let origin = captured.value
  let info = origin.originInfo.value
  let parent = fixture.prior.bestBlock.value
  assert info.reports == 2 and info.entries == parent.stateSnapshot.commitment.entries and
      info.valueBytes > 0, "original complete state and available report population"
  assert array[32, byte](info.parentHash) == array[32, byte](parent.blockHash) and
    array[32, byte](info.parentRoot) == array[32, byte](parent.stateRoot), "exact actual predecessor identities"
  let target = origin.reportAt(0).value
  assert target.valid and sameStateSnapshot(target.originState.value, parent.stateSnapshot), "full-state source is the original immutable owner"
  assert target.originParameters.value.sameParameterProfile(parent.chainParameters), "whole original execution parameter profile"
  assert uint64(target.originReport.value.ownedReportInfo.value.core) == 0, "original selected guarantee report cannot be replaced"
  assert array[32, byte](target.originReportHash.value) == array[32, byte](
      origin.originContext.value.auditReportHash(0).value), "report identity remains bound to its block and state"
  assert origin.reportAt(-1).error == AuditOriginError.InvalidIndex and origin.reportAt(2).error ==
      AuditOriginError.InvalidIndex, "origin target ordinals are checked before access"
proc originChecks(fixture: AuditContextFixture) =
  ## Independent entry/node/value ceilings and cancellation cannot expose a partially retained execution source.
  originCycle(fixture)
  var limited = auditOriginLimits()
  limited.entries = ElementLimit(1)
  assert captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), limited).error ==
      AuditOriginError.LimitExceeded, "all unrelated full-map entries count toward retention"
  limited = auditOriginLimits()
  limited.nodes = TrieNodeLimit(1)
  assert captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), limited).error ==
      AuditOriginError.LimitExceeded, "whole original state topology is bounded"
  limited = auditOriginLimits()
  limited.valueBytes = ByteLimit(1)
  assert captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), limited).error ==
      AuditOriginError.LimitExceeded, "whole logical value accounting cannot return a pinned prefix"
  let missing = captureAuditOrigin(fixture.prior, fixture.blockHash, auditLimits(),
      auditOriginLimits())
  assert missing.error == AuditOriginError.ContextFailure and missing.contextError.error ==
      AuditContextError.UnknownBlock, "genuine original context failure is preserved"
  assert captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits(),
      assuranceScanControl(stopNow, nil)).error == AuditOriginError.Cancelled, "execution-only cancellation grants no retained state"
  assert not default(AuditBlockOrigin).valid and default(AuditReportOrigin).originState.error ==
      AuditOriginError.Uninitialized, "default origin and target cannot supply a full-state source"
proc waitDone(worker: var StateProofWorker) =
  ## Observe synchronized scalar state while immutable view/source aliases belong to the fixed native thread.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded native audit context"
proc waitServices(owner: var Services) =
  ## No canonical or RPC source graph is inspected while the Services worker has its exact lease.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded managed audit planning"
proc finalizedRetentionChecks() {.raises.} =
  ## A selected high-slot checkpoint gives no expiry authority until local finality is explicitly installed.
  let snapshot = topologyCaptured([topologyRecords(2, 9), topologyRecords(3, 9),
      topologyRecords(4, 9)], atSlot = 37)
  assert snapshot.error == GenesisError.None
  var path = "audit-retention-services-" & $processId() & ".json"
  writeFile(path, currentApplicationText(snapshot.value))
  defer: discard posix.unlink(path.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], settings)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(settings, "audit retention from installed finality")
  assert owner.expireFinalizedAudits(0) == 0, "best-head epoch cannot expire any original duties"
  assert owner.publishFinalized(snapshot.value.blockHash) == ViewFinalizeError.None
  assert owner.expireFinalizedAudits(0) == 2, "epoch three keeps its previous epoch eligible"
  assert owner.expireFinalizedAudits(2) == 2, "repeated finalized epoch is idempotent"
proc detachedRouting(fixture: AuditContextFixture): AuditRoutingBasis =
  ## Capture a genuine original routing basis whose execution origin goes out of scope.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
      auditOriginLimits()).value.reportAt(0).value
  let member = origin.auditorAt(1).value.ed25519
  captureAuditParticipation(origin, fixture.view.bestBlock, member,
      participationLimits()).value.routingBasis
proc managed(fixture: AuditContextFixture) {.raises.} =
  ## A genuine trusted complete header-only seed qualifies neither a body nor an audit; exact managed failure and foreign Done ownership still retire correctly.
  var file = "audit-context-services-" & $processId() & ".json"
  writeFile(file, currentApplicationText(fixture.prior.bestBlock.value))
  defer: discard posix.unlink(file.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", file], settings), "actual full-state startup options"
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(settings, "native audit context"), "independently decoded genuine complete seed"
  let target = owner.chainView.bestBlock.value.blockHash
  let routing = detachedRouting(fixture)
  assert routing.valid and not owner.auditRetentionConfigured
  assert not routing.detached(ByteLimit(1)).valid, "copy budget precedes detached roster allocation"
  let refresh = owner.beginAuditRoutingRefresh(routing, participationLimits())
  assert refresh.error == StateProofAdmissionError.None
  owner.waitServices()
  let routed = owner.collectAudit(refresh.value)
  assert routed.kind == ManagedAuditKind.ParticipationPlanned
  let facts = routed.participationPlan.participationInfo.value
  assert facts.localValidators == 1 and array[32, byte](facts.source) == array[32, byte](target),
      "detached refresh keeps original role while selecting the current trusted topology"

  assert owner.beginAuditPlanning(target, default(AuditContextLimits)).error ==
      StateProofAdmissionError.QueryFailure,
    "invalid policy acquires no canonical lease"
  assert owner.stateProofAvailable and not owner.rpc.chainPaused, "failed capture keeps exclusion idle"
  let started = owner.beginAuditPlanning(target, auditLimits())
  assert started.error == StateProofAdmissionError.None and owner.rpc.chainPaused, "actual audit planning takes exact canonical/RPC exclusion"
  owner.waitServices()
  assert owner.beginAuditPlanning(target, auditLimits()).error == StateProofAdmissionError.Busy,
    "foreign completed audit job retains its lease"
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized and
    owner.stateProofActive(started.value), "wrong ticket cannot consume managed Done"
  let completed = owner.collectStateProof(started.value)
  assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted, "closed managed audit completion"
  assert completed.workSubmissionValue.kind == WorkJobResultKind.AuditPlanningFailure and
    completed.workSubmissionValue.auditPlanningError.error == AuditContextError.MissingBody,
    "header-only seed does not invent a complete audited block"
  assert owner.stateProofAvailable and not owner.rpc.chainPaused, "exact failure collection resumes canonical RPC"
  let cancelled = owner.beginAuditPlanning(target, auditLimits()).value
  owner.waitServices()
  assert owner.cancelStateProof(cancelled), "cancel exact audit Done"
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled,
    "cancelled managed planning exposes no context or failed-prefix payload"
  assert owner.stateProofAvailable and not owner.assuranceStorageInfo.opened and
      not owner.assuranceSigningConfigured,
    "planning imports neither an archive nor a private signer"
func initialProofLimits(): AuditProofLimits =
  ## The production worker reserves a sign, a verification and both possible shuffle groups.
  AuditProofLimits(proofs: ElementLimit(2), hashes: ElementLimit(2),
      bytes: ByteLimit(4096), hashBytes: ByteLimit(72))
proc managedEvaluation(fixture: AuditContextFixture) {.raises.} =
  ## A separately decoded trusted checkpoint can retain genuine authenticated archive material; only exact private evaluation crosses the managed native lease.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let wire = fixture.originalWire(origin.reportAt(0).value)
  var file = "audit-evaluation-services-" & $processId() & ".json"
  writeFile(file, currentApplicationText(fixture.view.bestBlock.value))
  defer:
    discard posix.unlink(file.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", file], settings)
  var keyFile = "managed-audit-key-" & $processId() & ".pem"
  var certificateFile = "managed-audit-certificate-" & $processId() & ".pem"
  assuranceSignerFiles(keyFile, certificateFile, 12)
  defer:
    discard posix.unlink(keyFile.toCString())
    discard posix.unlink(certificateFile.toCString())
  var owner = default(Services)
  defer:
    owner.close()
  assert owner.start(settings, "native audit evaluation"), "independently trusted current checkpoint"
  assert owner.beginAuditEvaluation(default(AuditOriginId), 0, wire, evaluationLimits()).error ==
      StateProofAdmissionError.QueryFailure, "optional audit registry stays disabled by default"
  assert owner.configureAudits(registryLimits()) and not owner.configureAudits(registryLimits()), "explicit bounded once-only retention"
  assert owner.retainAuditOrigin(default(AuditBlockOrigin)).error ==
      AuditRegistryError.InvalidSource, "default source supplies no backfill authority"
  assert not owner.auditSigningConfigured, "retention activates no private signer"
  let identity = origin.originContext.value.auditorAt(1).value.ed25519
  let noSigner = owner.beginInitialAudit(fixture.blockHash, identity, JudgeIndex(1),
      auditLimits(), initialProofLimits())
  assert noSigner.error == StateProofAdmissionError.QueryFailure,
      "initial announcement requires explicit Bandersnatch signer configuration"
  assert owner.configureTicketSignerSeed(default(array[32, byte])).error == TicketSignerError.None
  let production = owner.beginInitialAudit(fixture.blockHash, identity, JudgeIndex(1),
      auditLimits(), initialProofLimits())
  assert production.error == StateProofAdmissionError.None and owner.rpc.chainPaused,
      "initial announcement holds the canonical lease"
  owner.waitServices()
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized and owner.rpc.chainPaused,
      "foreign collection cannot release the production lease"
  let missingAnnouncement = owner.collectStateProof(production.value).workSubmissionValue
  assert missingAnnouncement.kind == WorkJobResultKind.InitialAuditSourceFailure and
      missingAnnouncement.initialAuditSourceError == AuditContextError.MissingBody and
          not owner.rpc.chainPaused,
      "a checkpoint cannot produce an announcement without the authenticated body"
  let mismatched = owner.configureAuditSigner(certificateFile, keyFile, default(StateEdKey))
  assert mismatched.error == WorkSigningSetupError.InvalidIdentity and
      not owner.auditSigningConfigured, "configured private signer must match actual transport identity"
  assert owner.configureAuditSigner(certificateFile, keyFile, identity).error ==
      WorkSigningSetupError.None
  assert owner.configureAuditSigner(certificateFile, keyFile, identity).error ==
      WorkSigningSetupError.Busy, "live private signer cannot be replaced silently"
  let id = owner.retainAuditOrigin(origin).value
  assert owner.retainAuditOrigin(origin).value == id, "actual trusted block binds authentic whole origin idempotently"
  assert owner.beginAuditEvaluation(default(AuditOriginId), 0, wire, evaluationLimits()).error ==
      StateProofAdmissionError.QueryFailure, "fabricated selector cannot choose complete state"
  assert owner.beginAuditEvaluation(id, 2, wire, evaluationLimits()).error ==
      StateProofAdmissionError.QueryFailure, "original report ordinal remains bounded"
  assert owner.beginAuditSigning(id, 0, StateValidatorIndex(1)).error ==
      StateProofAdmissionError.QueryFailure, "origin registration and public facts cannot authorize private signing"
  let cancelledFetch = owner.beginAuditFetchPlanning(id, 0, fetchLimits()).value
  owner.waitServices()
  assert owner.cancelStateProof(cancelledFetch)
  assert owner.collectAudit(cancelledFetch).kind == ManagedAuditKind.Cancelled, "cancelled Done exposes no routing prefix"
  let fetching = owner.beginAuditFetchPlanning(id, 0, fetchLimits()).value
  owner.waitServices()
  assert owner.collectStateProof(fetching).kind == ProofWorkerCompletionKind.Uninitialized
  let routes = owner.collectAudit(fetching)
  assert routes.kind == ManagedAuditKind.FetchPlanned and
      routes.fetchPlan.fetchInfo.value.threshold == 4, "private Services lookup publishes only detached original routes"
  let started = owner.beginAuditEvaluation(id, 0, wire, evaluationLimits())
  assert started.error == StateProofAdmissionError.None and owner.rpc.chainPaused, "genuine registered execution owns the exact canonical lease"
  assert owner.collectAudit(default(ProofWorkerTicket)).kind == ManagedAuditKind.Uninitialized, "foreign control cannot collect or expose a private capability"
  owner.waitServices()
  assert owner.collectStateProof(started.value).kind == ProofWorkerCompletionKind.Uninitialized and
      owner.stateProofActive(started.value), "generic collection cannot leak a private evaluation graph even at Done"
  assert owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).error ==
      StateProofAdmissionError.Busy, "Done retains full exclusion until exact collection"
  let completed = owner.collectAudit(started.value)
  assert completed.kind == ManagedAuditKind.Evaluated and completed.evaluationInfo.positive and
      completed.evaluationId == id and completed.evaluationOrdinal == 0, "actual whole execution becomes detached metadata after private registry retention"
  assert owner.stateProofAvailable and not owner.rpc.chainPaused, "exact private collection restores ordinary canonical access"
  assert owner.collectAudit(started.value).kind == ManagedAuditKind.Uninitialized, "stale completion cannot be collected twice"
  let signing = owner.beginAuditSigning(id, 0, StateValidatorIndex(1)).value
  owner.waitServices()
  assert owner.collectStateProof(signing).kind == ProofWorkerCompletionKind.Uninitialized, "generic collection cannot steal managed signing control"
  let signed = owner.collectAudit(signing)
  assert signed.kind == ManagedAuditKind.JudgmentSigned and signed.signingId == id and
      signed.signingOrdinal == 0, "exact private registered evaluation authorizes one source-free completed signature"
  verifySignedAudit(signed.signedJudgment, origin.reportAt(0).value, true)
  let cancelSigning = owner.beginAuditSigning(id, 0, StateValidatorIndex(1)).value
  owner.waitServices()
  assert owner.cancelStateProof(cancelSigning)
  assert owner.collectAudit(cancelSigning).kind == ManagedAuditKind.Cancelled, "cancelled Done signing publishes no signed result"
  let wrongSigner = owner.beginAuditSigning(id, 0, StateValidatorIndex(0)).value
  owner.waitServices()
  let wrong = owner.collectAudit(wrongSigner)
  assert wrong.kind == ManagedAuditKind.SigningFailure and wrong.signingError.error ==
      AuditSigningError.IdentityMismatch, "private key matches the original auditor ordinal independently of a host selector"
  let cancelled = owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).value
  owner.waitServices()
  assert owner.cancelStateProof(cancelled), "cancel exact completed execution before collection"
  assert owner.collectAudit(cancelled).kind == ManagedAuditKind.Cancelled, "cancelled Done cannot publish completed evaluation metadata"
  var damaged = wire
  damaged[0] = damaged[0] xor 1
  let bad = owner.beginAuditEvaluation(id, 0, damaged, evaluationLimits()).value
  owner.waitServices()
  let refused = owner.collectAudit(bad)
  assert refused.kind == ManagedAuditKind.EvaluationFailure and
      refused.evaluationError.needsRecovery, "unproved corrupt direct data yields recovery requirement, never a negative capability"
  let missingBody = owner.beginAuditOriginCapture(fixture.blockHash, auditLimits(),
      auditOriginLimits()).value
  owner.waitServices()
  let unavailable = owner.collectAudit(missingBody)
  assert unavailable.kind == ManagedAuditKind.OriginFailure and
      unavailable.originError.contextError.error == AuditContextError.MissingBody, "trusted checkpoint alone cannot manufacture the original body or predecessor"
  let stopped = owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).value
  owner.waitServices()
  owner.stopStateProofs()
  assert owner.collectAudit(stopped).kind == ManagedAuditKind.Uninitialized and
      owner.stateProofAvailable, "joined stop revokes pending controls before another worker can borrow retained pins"
  let repeated = owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).value
  owner.waitServices()
  assert owner.collectAudit(repeated).kind == ManagedAuditKind.Evaluated, "joined proof restart preserves full retained obligations"
  let closing = owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).value
  owner.waitServices()
  owner.close()
  assert owner.collectAudit(closing).kind == ManagedAuditKind.Uninitialized, "joined whole shutdown retires controls before full pins"
  assert owner.start(settings, "new audit lifetime") and owner.configureAudits(registryLimits()), "new lifetime gets a fresh bounded namespace"
  assert owner.beginAuditEvaluation(id, 0, wire, evaluationLimits()).error ==
      StateProofAdmissionError.QueryFailure, "old lifetime selector cannot select a new origin"

proc native(worker: var StateProofWorker, fixture: AuditContextFixture, index: int) {.raises.} =
  ## Exact native collection and Done cancellation use the same genuinely published body and original source as synchronous qualification.
  var job = captureAuditPlanning(fixture.view, fixture.blockHash, auditLimits()).value
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "native submission moves the closed audit capability"
  worker.waitDone()
  if index mod 2 == 0:
    assert worker.cancel(admitted.value), "exact completed audit cancellation"
  let completed = worker.collect(admitted.value)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "Done cancellation hides all accepted metadata"
  else:
    assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted, "whole native audit context"
    let planned = completed.workSubmissionValue
    assert planned.kind == WorkJobResultKind.AuditPlanned and
        planned.plannedAuditContext.contextInfo.value.reports == 2,
      "actual available reports survive only uncancelled exact collection"
proc initialNative(worker: var StateProofWorker, fixture: AuditContextFixture) {.raises.} =
  ## An installed JIP-5 signer and genuine source cannot sign for a different original TLS identity.
  var job = captureInitialAuditJob(fixture.view, fixture.blockHash, auditLimits(),
      initialProofLimits(), captureTicketSigner(default(array[32, byte])).value,
      default(StateEdKey), JudgeIndex(1)).value
  let ticket = worker.submit(job).value
  worker.waitDone()
  let completed = worker.collect(ticket).workSubmissionValue
  assert completed.kind == WorkJobResultKind.InitialAuditSigningFailure and
      completed.initialAuditSigningError == AuditValidationError.InvalidAuditor,
      "an ordinal whose original Ed25519 identity differs cannot reach private signing"
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let local = context.auditorAt(8).value.ed25519
  var discovered = captureInitialAuditJob(fixture.view, fixture.blockHash, auditLimits(),
      initialProofLimits(), captureTicketSigner(default(array[32, byte])).value,
      local, JudgeIndex(0), discover = true).value
  let signing = worker.submit(discovered).value
  worker.waitDone()
  let signed = worker.collect(signing).workSubmissionValue
  assert signed.kind == WorkJobResultKind.InitialAuditProduced
  let declaration = signed.producedInitialAudit
  assert uint16(declaration.announcement.validator) == 8 and declaration.selected.count == 2
  assert declaration.reportOrdinals[0] == 0 and declaration.reportOrdinals[1] == 1
  assert declaration.recipients.len == 8, "all other original physical auditors"
  for destination in declaration.recipients:
    # Compare the complete identity so the local original validator cannot be its own destination.
    assert array[32, byte](destination.identity) != array[32, byte](local)
  assert declaration.request.kind == ReadKind.AuditAnnouncement
  let wire = decodeAnnouncements(declaration.request.payload, AuditLimits(
      validators: ValidatorCount(9), cores: CoreCount(3), bytes: ByteLimit(131),
      records: ElementLimit(1))).value
  let verified = qualifyInitialAudit(context, wire.announcementAt(0).value, initialProofLimits())
  assert verified.error == AuditValidationError.None and
      uint16(verified.value.announcementInfo.value.validator) == 8,
      "the maintained receiver accepts the complete signed worker output"
proc receiptNative(worker: var StateProofWorker, fixture: AuditContextFixture, wire: seq[
    byte]) {.raises.} =
  ## The real joined worker moves bounded bytes and discards all successful records on exact Done cancellation.
  for cancelled in [false, true]:
    var job = captureAuditAnnouncements(fixture.view, wire, receiptLimits(auditLimits())).value
    let admitted = worker.submit(job)
    assert admitted.error == ProofWorkerError.None and not job.valid, "closed native batch submission moves its source"
    worker.waitDone()
    if cancelled: assert worker.cancel(admitted.value), "exact whole-batch Done cancellation"
    let completed = worker.collect(admitted.value)
    if cancelled:
      assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled batch exposes no accepted prefix"
    else:
      assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted, "uncancelled whole batch completion"
      let value = completed.workSubmissionValue
      assert value.kind == WorkJobResultKind.AuditAnnouncementsQualified and
          value.qualifiedAuditAnnouncements.len == 2, "real shared-worker batch qualification"
proc nativeEvaluation(worker: var StateProofWorker, fixture: AuditContextFixture,
    iteration: int) {.raises.} =
  ## Both private origin capture and full report comparison use real moved closed jobs; exact Done cancellation hides their entire source-bearing result.
  var preparation = captureAuditOriginJob(fixture.view, fixture.blockHash, auditLimits(),
      auditOriginLimits()).value
  let pendingOrigin = worker.submit(preparation)
  assert pendingOrigin.error == ProofWorkerError.None and not preparation.valid, "closed origin job moves actual history ownership"
  worker.waitDone()
  if iteration mod 3 == 0: assert worker.cancel(pendingOrigin.value), "exact completed full-origin cancellation"
  let originCompletion = worker.collect(pendingOrigin.value)
  if iteration mod 3 == 0:
    assert originCompletion.kind == ProofWorkerCompletionKind.Cancelled, "cancelled source capture cannot expose a retained full map"
    return
  assert originCompletion.kind == ProofWorkerCompletionKind.WorkSubmitted, "actual full-origin native completion"
  let prepared = originCompletion.workSubmissionValue
  assert prepared.kind == WorkJobResultKind.AuditOriginPrepared, "actual source-bearing origin prepared on the worker"
  let origin = prepared.preparedAuditOrigin
  let target = origin.reportAt(0).value
  var job = captureAuditEvaluationJob(target, fixture.originalWire(target), evaluationLimits()).value
  let pending = worker.submit(job)
  assert pending.error == ProofWorkerError.None and not job.valid, "closed evaluation moves its original full-state source"
  worker.waitDone()
  if iteration mod 2 == 0: assert worker.cancel(pending.value), "exact completed private evaluation cancellation"
  let completed = worker.collect(pending.value)
  if iteration mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "Done cancellation grants no positive or negative evaluation capability"
  else:
    assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted, "actual whole-report native completion"
    let checked = completed.workSubmissionValue
    if checked.kind == WorkJobResultKind.AuditEvaluationFailure: echo "native evaluation: ",
        checked.auditEvaluationError.error
    assert checked.kind == WorkJobResultKind.AuditEvaluated and
        checked.evaluatedAudit.matchesOrigin(target) and
        checked.evaluatedAudit.evaluationInfo.value.positive, "only whole original report equality grants the private native capability"
proc cycle(fixture: AuditContextFixture) =
  ## Complete private consensus forks, decoders and detached outputs retire before the next observation.
  let selected = captureAuditContext(fixture.view, fixture.blockHash, auditLimits())
  assert selected.error == AuditContextError.None and selected.value.contextInfo.value.reports == 2,
    "repeat genuine context qualification"
proc main() {.raises.} =
  ## One genuine positive source and repeated execution preserve source identity and release transient context graphs.
  let fixture = auditContextFixture()
  checked(fixture)
  branchPrefixChecks(fixture)
  branchNetworkChecks()
  let announcements = auditValidationChecks(captureAuditContext(fixture.view, fixture.blockHash,
      auditLimits()).value, fixture.view, auditLimits())
  hostileBody(fixture)
  cancellation(fixture)
  originChecks(fixture)
  evaluationChecks(fixture)
  registryChecks(fixture)
  recoveryChecks(fixture)
  authenticatedFaultChecks()
  intrinsicEmptyFaultChecks()
  auditSigningChecks(fixture)
  managed(fixture)
  finalizedRetentionChecks()
  fetchChecks(fixture)
  auditAcquisitionChecks(fixture)
  declaredAuditChecks(fixture)
  managedEvaluation(fixture)
  let insufficient = auditContextFixture(6)
  let none = captureAuditContext(insufficient.view, insufficient.blockHash, auditLimits())
  assert none.error == AuditContextError.None and none.value.contextInfo.value.reports == 0,
    "six of nine genuine votes do not manufacture newly available audit obligations"
  let noOrigin = captureAuditOrigin(insufficient.view, insufficient.blockHash, auditLimits(),
      auditOriginLimits())
  assert noOrigin.error == AuditOriginError.NoReports, "no new availability requires no retained execution origin"
  var worker = default(StateProofWorker)
  assert worker.start(), "stable reusable audit worker"
  defer:
    worker.close() # Joined shutdown precedes retirement of every borrowed source and fixture.
  native(worker, fixture, 1)
  initialNative(worker, fixture)
  receiptNative(worker, fixture, announcements)
  nativeEvaluation(worker, fixture, 1)
  nativeEvaluation(worker, fixture, 2)
  nativeEvaluation(worker, fixture, 3)
  cycle(fixture)
  recoveryCycle(fixture)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    if iteration mod 64 == 0:
      recoveryCycle(fixture) # Proven original-coordinate parity recovery and full evaluation share the ARC witness.
    elif iteration mod 32 == 0:
      nativeEvaluation(worker, fixture, iteration div 32) # Whole-source capture and actual private evaluation cancellation participate in the ARC observation.
    elif iteration mod 16 == 0:
      evaluationCycle(fixture) # Actual whole-report recomputation participates in mixed context/native/origin ARC release.
    elif iteration mod 8 == 0:
      originCycle(fixture) # Full-state pins, target aliases and refused paths release under the same repeated ARC observation.
    elif iteration mod 2 == 0:
      cycle(fixture) # Re-run actual signature/body/availability qualification rather than copying a cached accepted plan.
    elif iteration mod 4 == 1:
      receiptNative(worker, fixture, announcements) # Native whole-batch success and Done cancellation participate in the repeated ARC witness.
    else:
      native(worker, fixture, iteration div 2) # Exact success and completed cancellation both retire their original source aliases.
  let after = getOccupiedMem()
  assert before == after, "canonical audit context ARC release"
  recordArcRelease("jamnp_audit_context", 1000, before, after)
  echo "JAMNP-S audit context passed"
try:
  main()
except:
  quit(2)
