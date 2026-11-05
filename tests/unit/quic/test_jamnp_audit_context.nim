# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_audit_context_arc_release"}

## Actual published available reports, header entropy and original prior-role credentials define audit context; absent bodies and assignment disappearance cannot substitute authority.
import std/[assertions, syncio, monotimes, times, posix/posix]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/rpc/server
import ../../../src/jamnp-s/assurance_store
import ../../../src/jamnp-s/[audit_context, audit_receipt]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, owned, report_owned, block_codec]
import ../../../src/codec/state/[safrole, layout]
import "../../../src/state/block/transition"
import "../../../src/state/block/admission"
import ../../../src/crypto/primitives
import ../../support/[jamnp_audit_context, arc_evidence, current_application_context, jamnp_audit_validation]
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
proc cycle(fixture: AuditContextFixture) =
  ## Complete private consensus forks, decoders and detached outputs retire before the next observation.
  let selected = captureAuditContext(fixture.view, fixture.blockHash, auditLimits())
  assert selected.error == AuditContextError.None and selected.value.contextInfo.value.reports == 2,
    "repeat genuine context qualification"
proc main() {.raises.} =
  ## One genuine positive source and repeated execution preserve source identity and release transient context graphs.
  let fixture = auditContextFixture()
  checked(fixture)
  let announcements = auditValidationChecks(captureAuditContext(fixture.view, fixture.blockHash,
      auditLimits()).value, fixture.view, auditLimits())
  hostileBody(fixture)
  cancellation(fixture)
  managed(fixture)
  let insufficient = auditContextFixture(6)
  let none = captureAuditContext(insufficient.view, insufficient.blockHash, auditLimits())
  assert none.error == AuditContextError.None and none.value.contextInfo.value.reports == 0,
    "six of nine genuine votes do not manufacture newly available audit obligations"
  var worker = default(StateProofWorker)
  assert worker.start(), "stable reusable audit worker"
  defer: worker.close()
  native(worker, fixture, 1)
  receiptNative(worker, fixture, announcements)
  cycle(fixture)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    if iteration mod 2 == 0:
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
