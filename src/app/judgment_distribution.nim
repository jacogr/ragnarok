# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional CE145 receipt holds exact TLS/worker claims while complete negative support is acquired by hash and qualified. Only whole successful private retention releases source-free records, serving copies and forced-audit obligations.
import std/[monotimes, times]
import ./[services, audit_state]
import ../jamnp-s/audit_publication
import ./proof/[worker, work_submission]
import ../jamnp-s/[node, connections, read_stream, read_validation, report_cache,
  judgment_claim, judgment_receipt, judgment_source, judgment_store, audit_registry, audits]
import ../codec/[bounded, disputes]
import ../chain/genesis

type
  JudgmentReceiptPolicy* = object ## Whole-message work, detached ledger/report storage and exact native deadline are explicit; defaults activate nothing.
    ready: bool
    claims: JudgmentClaimLimits
    receipt: JudgmentReceiptLimits
    verification: ReadVerificationLimits
    store, local: JudgmentStoreLimits
    bytes: ByteLimit
    timeout, attempts: int
  ReceiptPhase {.pure.} = enum ## Every waiting phase retains one original bounded claim; CPU and native acquisition never create independent unmanaged workers.
    Empty, ClaimsReady, Claims, LocalReady, Local, Remote, VerifyReady, Verify, ReceiptReady, Receipt
  FailedJudgmentSource = object ## Fixed selector pair and its exact batch position.
    ordinal: int
    attempt: JudgmentSourceAttempt
  JudgmentDispatcher* = object ## Stable noncopyable exact-token owner retains detached storage; report input aliases remain untouched through the private receipt lease.
    policy: JudgmentReceiptPolicy
    store, localStore: JudgmentStore
    pending: seq[RetainedJudgment]
    reports, localReports: seq[ReadReply]
    held, active, cancelled, requested: bool
    phase: ReceiptPhase
    ticket: NodeReadTicket
    request, query: ReadRequest
    network: NodeRequestTicket
    proof: ProofWorkerTicket
    started: MonoTime
    claims: SignedJudgmentBatch
    inputs: seq[JudgmentSourceInput]
    replies: seq[ReadReply]
    failedSources: seq[FailedJudgmentSource]
    sourceSlots: seq[uint64]
    wire: seq[byte]
    ordinal, primaryRetries, alternateRetries: int
    received: uint64
func judgmentReceiptPolicy*(claims: JudgmentClaimLimits, receipt: JudgmentReceiptLimits,
    verification: ReadVerificationLimits, store: JudgmentStoreLimits, bytes: ByteLimit,
    timeoutMs: range[1..120000] = 30000, sourceAttempts: range[1..64] = 4,
    local = default(JudgmentStoreLimits)): JudgmentReceiptPolicy =
  ## Reserve worst-case persistent and transient wire storage up front; every per-message source retry remains under the same native deadline and finite attempt budget.
  if not claims.valid or not receipt.valid or not store.valid or uint64(store.records) > 256 or
      uint64(store.bytes) > 1024'u64*1024: return default(JudgmentReceiptPolicy)
  let localLimits = if uint64(local.records) == 0 and uint64(local.bytes) == 0: store else: local
  if not localLimits.valid: return default(JudgmentReceiptPolicy)
  let wire = uint64(verification.wireBytes)
  if wire < 4 or wire > uint64(MaxReadReplyBytes): return default(JudgmentReceiptPolicy)
  if uint64(bytes) == 0 or uint64(bytes) > 64'u64*1024*1024*1024: return default(JudgmentReceiptPolicy)
  let rows = uint64(store.records)+uint64(localLimits.records)+3*uint64(claims.message.records)
  if rows*wire+uint64(store.bytes)+uint64(localLimits.bytes)+uint64(claims.retainedBytes)+65536 >
      uint64(bytes):
    return default(JudgmentReceiptPolicy)
  JudgmentReceiptPolicy(ready: true, claims: claims, receipt: receipt, verification: verification,
    store: store, local: localLimits, bytes: bytes, timeout: timeoutMs, attempts: sourceAttempts)
func valid*(policy: JudgmentReceiptPolicy): bool =
  ## Omission cannot enable native CE145 or retain any judgment.
  policy.ready
proc `=copy`*(destination: var JudgmentDispatcher, source: JudgmentDispatcher) {.error.}
  ## Duplicate token ownership could cancel another controller's native stream or worker.
proc `=dup`*(source: JudgmentDispatcher): JudgmentDispatcher {.error.}
  ## Construction cannot duplicate a live exact-token controller.
proc requireClosed(owner: JudgmentDispatcher) {.requires: not owner.held and not owner.active and
    not owner.requested.} =
  ## Explicit exact cancellation/join and native retirement precede owner destruction.
  discard
proc `=wasMoved`*(owner: var JudgmentDispatcher) {.nodestroy, requires: not owner.held and
    not owner.active and not owner.requested.} =
  ## Delegate every owned child only after all physical borrowers have retired.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.store)
  `=wasMoved`(owner.localStore)
  `=wasMoved`(owner.pending)
  `=wasMoved`(owner.reports)
  `=wasMoved`(owner.localReports)
  `=wasMoved`(owner.ticket)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.query)
  `=wasMoved`(owner.network)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.claims)
  `=wasMoved`(owner.inputs)
  `=wasMoved`(owner.replies)
  `=wasMoved`(owner.sourceSlots)
  `=wasMoved`(owner.wire)
proc `=destroy`*(owner: JudgmentDispatcher) =
  ## Explicit foreground close joins this owner's exact lease before report/source aliases retire.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.store)
  `=destroy`(owner.localStore)
  `=destroy`(owner.pending)
  `=destroy`(owner.reports)
  `=destroy`(owner.localReports)
  `=destroy`(owner.ticket)
  `=destroy`(owner.request)
  `=destroy`(owner.query)
  `=destroy`(owner.network)
  `=destroy`(owner.proof)
  `=destroy`(owner.claims)
  `=destroy`(owner.inputs)
  `=destroy`(owner.replies)
  `=destroy`(owner.sourceSlots)
  `=destroy`(owner.wire)
func received*(owner: JudgmentDispatcher): uint64 =
  ## Count complete native acknowledgments after full qualification and retention.
  owner.received
func pendingCount*(owner: JudgmentDispatcher): int =
  ## A qualified negative publication creates a forced-audit obligation without a CE144 announcement or fabricated available block.
  owner.pending.len
proc pendingAt*(owner: JudgmentDispatcher, ordinal: int): RetainedJudgment {.requires: ordinal >=
    0 and ordinal < owner.pending.len.} =
  ## Detached original record and exact host selector reveal no private full state or signing key.
  owner.pending[ordinal]
func retainedReportCount*(owner: JudgmentDispatcher): int =
  ## Detached immutable raw serving rows can remain available while private report inputs are leased elsewhere.
  owner.reports.len+owner.localReports.len
func judgmentCount*(owner: JudgmentDispatcher): int =
  ## Scalar source-free ledger occupancy is independent of private worker phases.
  owner.store.len+owner.localStore.len
proc judgmentAt*(owner: JudgmentDispatcher, ordinal: int): QualifiedJudgment {.requires: ordinal >=
    0 and ordinal < owner.judgmentCount.} =
  ## Preserve both original opposite signed claims rather than replacing either side of an accountable conflict.
  if ordinal < owner.store.len: owner.store.judgmentAt(ordinal).value
  else: owner.localStore.judgmentAt(ordinal-owner.store.len).value
func configured*(owner: JudgmentDispatcher): bool =
  ## Optional receipt must be configured before enabling automatic participation.
  owner.policy.ready

func canExpire*(owner: JudgmentDispatcher): bool =
  ## No held receipt may have reserved ledger or raw-reply capacity.
  not owner.held
proc expireBefore*(owner: var JudgmentDispatcher, floor: uint64): array[256, bool] {.requires:
    owner.canExpire.} =
  ## Compact only after whole receipt retirement and report the old positions of surviving duties.
  result = default(array[256, bool])
  owner.store.expireBefore(floor)
  owner.localStore.expireBefore(floor)
  var kept = 0
  for row in 0..<owner.pending.len:
    # Preserve original negative duty identity and ordering for controller progress.
    let epoch = uint64(uint32(owner.pending[row].judgment.judgmentRecord.epoch))
    if epoch >= floor:
      result[row] = true
      if kept != row: owner.pending[kept] = move(owner.pending[row])
      inc kept
  owner.pending.setLen(kept)
  kept = 0
  for row in 0..<owner.reports.len:
    # A hash shared with a live epoch keeps its exact reply.
    if owner.store.containsReport(owner.reports[row].request.payload):
      if kept != row: owner.reports[kept] = move(owner.reports[row])
      inc kept
  owner.reports.setLen(kept)
  kept = 0
  for row in 0..<owner.localReports.len:
    if owner.localStore.containsReport(owner.localReports[row].request.payload):
      if kept != row: owner.localReports[kept] = move(owner.localReports[row])
      inc kept
  owner.localReports.setLen(kept)
proc rememberPublication*(owner: var JudgmentDispatcher, publication: AuditPublication): bool =
  ## Commit a genuine local signature and its detached serving reply together.
  if not owner.policy.ready or not publication.valid: return false
  let qualified = qualifyLocalJudgment(publication.signedJudgment)
  if qualified.error != JudgmentReceiptError.None: return false
  let reply = publication.reportReply
  if uint64(reply.byteLength) > uint64(owner.policy.verification.wireBytes): return false
  var known = false
  for old in owner.localReports:
    if old.matches(reply.request): known = true
  if not known and uint64(owner.localReports.len) >= uint64(
      owner.policy.local.records): return false
  if owner.localStore.append([qualified.value]).error != JudgmentStoreError.None: return false
  if not known: owner.localReports.add(reply)
  true

proc configure*(owner: var JudgmentDispatcher, streams: var NodeService,
    policy: JudgmentReceiptPolicy): bool =
  ## Enable the distinct native validator selector only after explicit finite local retention succeeds.
  if owner.policy.ready or not policy.ready or owner.held or owner.active or
      not streams.isValidator: return false
  if not owner.store.configure(policy.store): return false
  if not owner.localStore.configure(policy.local) or not streams.enableJudgmentStreams():
    owner.store.clear()
    owner.localStore.clear()
    return false
  owner.policy = policy
  owner.received = 0
  true
proc clearClaim(owner: var JudgmentDispatcher) =
  ## Only exact worker retirement or joined shutdown permits releasing source-bearing report inputs.
  owner.held = false
  owner.active = false
  owner.cancelled = false
  owner.requested = false
  owner.phase = ReceiptPhase.Empty
  owner.ticket = default(NodeReadTicket)
  owner.request = default(ReadRequest)
  owner.query = default(ReadRequest)
  owner.network = default(NodeRequestTicket)
  owner.proof = default(ProofWorkerTicket)
  owner.claims = default(SignedJudgmentBatch)
  owner.inputs = @[]
  owner.replies = @[]
  owner.failedSources = @[]
  owner.sourceSlots = @[]
  owner.wire = @[]
  owner.ordinal = 0
  owner.primaryRetries = 0
  owner.alternateRetries = 0
proc reject(owner: var JudgmentDispatcher, streams: var NodeService) =
  ## Reject only this exact request and outgoing child; complete detached earlier obligations remain intact.
  if owner.requested: discard streams.cancelRequest(owner.network)
  discard streams.reject(owner.ticket)
  owner.clearClaim()
proc findReport*(owner: JudgmentDispatcher, request: ReadRequest): ReadResult[ReadReply] =
  ## Serving copies share only detached raw framing, never the OwnedReport input graph frozen on the private worker.
  if not request.valid or request.kind != ReadKind.Report: return readFailure[ReadReply](
      ReadError.Unavailable)
  for report in owner.localReports:
    if report.matches(request): return report.forRequest(request)
  for report in owner.reports:
    # Each retained reply was hash-verified under this exact full report request before whole negative receipt succeeded.
    if report.matches(request): return report.forRequest(request)
  readFailure[ReadReply](ReadError.Unavailable)
proc nextReport(owner: var JudgmentDispatcher, services: Services): bool =
  ## Skip positive records and reuse only exact earlier full-hash report bytes; report verification and original guarantee qualification remain separate.
  while owner.ordinal < owner.claims.len:
    let claim = owner.claims.claimAt(owner.ordinal).value
    if claim.judgmentRecord.valid:
      inc owner.ordinal
      continue
    let selected = services.judgmentSource(claim)
    if selected.error != JudgmentSourceError.None: return false
    owner.inputs[owner.ordinal].source = selected.value
    owner.inputs[owner.ordinal].membership = selected.membershipSource
    owner.sourceSlots[owner.ordinal] = selected.sourceSlot
    var hash: seq[byte] = @[]
    for octet in array[32, byte](claim.judgmentRecord.report): hash.add(octet)
    let query = decodeReadRequest(ReadKind.Report, hash)
    if query.error != ReadError.None: return false
    owner.query = query.value
    owner.phase = ReceiptPhase.LocalReady
    return true
  owner.phase = ReceiptPhase.ReceiptReady
  true
proc releaseUnused(owner: JudgmentDispatcher, services: var Services,
    completed: ManagedAuditCompletion) =
  ## Duplicate or rejected receipt outcomes must not strand a newly pinned private origin.
  if completed.kind != ManagedAuditKind.JudgmentsRetained: return
  for ordinal in 0..<completed.retainedJudgmentCount:
    # Positive records have no private origin. A negative source stays live while a pending relay references it.
    let id = completed.retainedJudgmentAt(ordinal).originId
    if not id.valid: continue
    var used = false
    for row in owner.pending:
      if row.originId == id: used = true
    if not used: discard services.releaseDisputedAudit(id)
proc retainWhole(owner: var JudgmentDispatcher, completed: ManagedAuditCompletion): bool =
  ## Whole ledger and distinct report/obligation capacity is proven before mutation; an unacknowledged transport retry cannot erase qualified evidence.
  if completed.kind != ManagedAuditKind.JudgmentsRetained or completed.retainedJudgmentCount !=
      owner.claims.len: return false
  var records: seq[QualifiedJudgment] = @[]
  var pending: seq[RetainedJudgment] = @[]
  var reports: seq[ReadReply] = @[]
  for ordinal in 0..<completed.retainedJudgmentCount:
    # Only detached qualified records and raw reply owners are copied here; no private source or mutable report backing storage escapes.
    let retained = completed.retainedJudgmentAt(ordinal)
    let record = retained.judgment
    records.add(record)
    if record.judgmentRecord.valid: continue
    var duplicate = false
    for old in owner.pending:
      if sameJudgmentKey(old.judgment, record): duplicate = true
    for old in pending:
      if sameJudgmentKey(old.judgment, record): duplicate = true
    if not duplicate: pending.add(retained)
    var known = false
    for old in owner.reports:
      if old.matches(owner.replies[ordinal].request): known = true
    for old in reports:
      if old.matches(owner.replies[ordinal].request): known = true
    if not known: reports.add(owner.replies[ordinal])
  if uint64(owner.pending.len+pending.len) > uint64(owner.policy.store.records) or uint64(
      owner.reports.len+reports.len) > uint64(owner.policy.store.records): return false
  if owner.store.append(records).error != JudgmentStoreError.None: return false
  for record in pending: owner.pending.add(record) # All bounded source-free additions are already reserved.
  for report in reports: owner.reports.add(report) # Retained original publishers remain able to serve CE136 after the transient request retires.
  true
proc poll*(owner: var JudgmentDispatcher, services: var Services,
    streams: var NodeService, cache: var ReportCache, clock: MonoTime) =
  ## Poll exact completion/deadline state without submitting another job; expensive parsing/signatures remain on the shared bounded worker.
  if not owner.policy.ready or not owner.held: return
  let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
  let live = streams.readLive(owner.ticket)
  if (expired or not live) and owner.active and not owner.cancelled:
    owner.cancelled = services.cancelStateProof(owner.proof)
  if not owner.active:
    if expired or not live:
      owner.reject(streams)
      return
    if owner.phase == ReceiptPhase.Remote:
      if not owner.requested: return
      let reply = streams.takeReply(owner.network)
      if reply.error == ReadError.None:
        owner.requested = false
        owner.network = default(NodeRequestTicket)
        owner.wire = reply.value.bytes
        owner.phase = ReceiptPhase.VerifyReady
      elif reply.error != ReadError.Unavailable: owner.reject(streams)
    return
  if not services.stateProofActive(owner.proof):
    owner.active = false
    owner.reject(streams)
    return
  if owner.phase == ReceiptPhase.Receipt:
    let completed = services.collectAudit(owner.proof)
    if completed.kind == ManagedAuditKind.Uninitialized: return
    owner.active = false
    owner.proof = default(ProofWorkerTicket)
    if expired or not live or owner.cancelled or completed.kind == ManagedAuditKind.Cancelled:
      owner.releaseUnused(services, completed)
      owner.reject(streams)
      return
    if completed.kind == ManagedAuditKind.JudgmentReceiptFailure:
      let ordinal = completed.judgmentReceiptError.failedOrdinal
      let primaryCredit = owner.primaryRetries < owner.policy.attempts-1
      let alternateCredit = owner.alternateRetries < owner.policy.attempts-1
      if ordinal >= 0 and ordinal < owner.inputs.len and (primaryCredit or alternateCredit) and
          owner.failedSources.len < 128:
        let failed = owner.inputs[ordinal]
        # At most 126 retried attempts can precede this failure in one message.
        owner.failedSources.add(FailedJudgmentSource(ordinal: ordinal,
            attempt: JudgmentSourceAttempt(source: failed.source, membership: failed.membership)))
        var excluded = default(array[128, JudgmentSourceAttempt])
        var count = 0
        for source in owner.failedSources:
          if source.ordinal == ordinal:
            excluded[count] = source.attempt
            inc count
        let next = services.judgmentSource(owner.claims.claimAt(ordinal).value,
            excluded.toOpenArray(0, count-1), owner.sourceSlots[ordinal], primaryCredit, alternateCredit)
        if next.error == JudgmentSourceError.None:
          let membership = next.membershipSource
          if array[32, byte](membership) == default(array[32, byte]): inc owner.primaryRetries
          else: inc owner.alternateRetries
          owner.inputs[ordinal].source = next.value
          owner.inputs[ordinal].membership = membership
          owner.phase = ReceiptPhase.ReceiptReady
          return
    let retained = owner.retainWhole(completed)
    owner.releaseUnused(services, completed)
    if not retained:
      owner.reject(streams)
      return
    let acknowledgment = captureReadReply(owner.request, [])
    if acknowledgment.error == ReadError.None and streams.respond(owner.ticket,
        acknowledgment.value) == ReadError.None:
      if owner.received < high(uint64): inc owner.received
      owner.clearClaim()
    else: owner.reject(streams)
    return
  let completed = services.collectStateProof(owner.proof)
  if completed.kind == ProofWorkerCompletionKind.Uninitialized: return
  owner.active = false
  owner.proof = default(ProofWorkerTicket)
  if expired or not live or owner.cancelled or completed.kind ==
      ProofWorkerCompletionKind.Cancelled:
    owner.reject(streams)
    return
  case owner.phase
  of ReceiptPhase.Claims:
    if completed.kind != ProofWorkerCompletionKind.WorkSubmitted or
        completed.workSubmissionValue.kind != WorkJobResultKind.JudgmentClaimsVerified:
      owner.reject(streams)
      return
    owner.claims = completed.workSubmissionValue.verifiedJudgmentClaims
    if not owner.store.canAppendClaims(owner.claims):
      owner.reject(streams)
      return
    owner.inputs = newSeq[JudgmentSourceInput](owner.claims.len)
    owner.replies = newSeq[ReadReply](owner.claims.len)
    owner.sourceSlots = newSeq[uint64](owner.claims.len)
    owner.ordinal = 0
    if not owner.nextReport(services): owner.reject(streams)
  of ReceiptPhase.Local:
    if completed.kind == ProofWorkerCompletionKind.ReadCompleted and completed.readValue.error ==
        ReadError.None:
      owner.wire = completed.readValue.value.bytes
      owner.phase = ReceiptPhase.VerifyReady
    else: owner.phase = ReceiptPhase.Remote # A local miss queries the original still-live negative publisher first.
  of ReceiptPhase.Verify:
    if completed.kind != ProofWorkerCompletionKind.ReadVerified or
        completed.verifiedReadValue.error != ReadVerificationError.None:
      owner.reject(streams)
      return
    let checked = completed.verifiedReadValue.value
    if checked.kind != ReadKind.Report:
      owner.reject(streams)
      return
    owner.inputs[owner.ordinal].report = checked.workReport
    let frozen = captureReadReply(owner.query, owner.wire)
    if frozen.error != ReadError.None:
      owner.reject(streams)
      return
    owner.replies[owner.ordinal] = frozen.value
    discard cache.remember(checked)
    owner.wire = @[]
    inc owner.ordinal
    if not owner.nextReport(services): owner.reject(streams)
  else: owner.reject(streams) # Foreign or impossible completions never advance an incoming request.
proc submit*(owner: var JudgmentDispatcher, services: var Services,
    streams: var NodeService, cache: var ReportCache, clock: MonoTime): bool {.raises.} =
  ## Admit one bounded action per foreground turn; Busy keeps the original native claim/deadline and exact source-free staging intact.
  if not owner.policy.ready or owner.active or not services.stateProofAvailable: return false
  if not owner.held:
    let incoming = streams.takeRead(ReadKind.Judgment)
    if incoming.error != NodeError.None: return false
    owner.ticket = incoming.value.ticket
    owner.request = incoming.value.request
    owner.started = clock
    owner.held = true
    owner.phase = ReceiptPhase.ClaimsReady
  if not streams.readLive(owner.ticket) or (clock-owner.started).inMilliseconds >=
      owner.policy.timeout:
    owner.reject(streams)
    return true
  case owner.phase
  of ReceiptPhase.ClaimsReady:
    let admitted = services.beginJudgmentClaims(owner.request.payload, owner.policy.claims)
    if admitted.error == StateProofAdmissionError.Busy: return false
    if admitted.error != StateProofAdmissionError.None:
      owner.reject(streams)
      return true
    owner.proof = admitted.value
    owner.phase = ReceiptPhase.Claims
  of ReceiptPhase.LocalReady:
    let retained = owner.findReport(owner.query)
    if retained.error == ReadError.None:
      owner.wire = retained.value.bytes
      owner.phase = ReceiptPhase.VerifyReady
      return true
    let cached = cache.find(owner.query)
    if cached.error == ReportCacheError.None:
      owner.wire = cached.value.bytes
      owner.phase = ReceiptPhase.VerifyReady
      return true
    let admitted = services.beginNetworkRead(owner.query)
    if admitted.error == StateProofAdmissionError.Busy: return false
    if admitted.error != StateProofAdmissionError.None:
      owner.phase = ReceiptPhase.Remote
      return true
    owner.proof = admitted.value
    owner.phase = ReceiptPhase.Local
  of ReceiptPhase.Remote:
    if owner.requested: return false
    let requested = streams.request(owner.ticket.sourcePeer, owner.query,
        owner.policy.verification.wireBytes)
    if requested.error != NodeError.None: return false
    owner.network = requested.value
    owner.requested = true
    return true
  of ReceiptPhase.VerifyReady:
    let admitted = services.beginReadVerification(owner.query, owner.wire,
        owner.policy.verification)
    if admitted.error == StateProofAdmissionError.Busy: return false
    if admitted.error != StateProofAdmissionError.None:
      owner.reject(streams)
      return true
    owner.proof = admitted.value
    owner.phase = ReceiptPhase.Verify
  of ReceiptPhase.ReceiptReady:
    let admitted = services.beginJudgmentReceipt(owner.claims, owner.inputs, owner.policy.receipt)
    if admitted.error == StateProofAdmissionError.Busy: return false
    if admitted.error != StateProofAdmissionError.None:
      owner.reject(streams)
      return true
    owner.proof = admitted.value
    owner.phase = ReceiptPhase.Receipt
  else: return false # Running phases are harvested exclusively by poll.
  owner.active = true
  owner.cancelled = false
  true
proc close*(owner: var JudgmentDispatcher, services: var Services, streams: var NodeService) =
  ## Join only after this exact cancellation succeeds; another actor's worker generation remains untouched.
  if owner.active and services.stateProofActive(owner.proof):
    if services.cancelStateProof(owner.proof): services.stopStateProofs()
  if owner.requested: discard streams.cancelRequest(owner.network)
  if owner.held: discard streams.reject(owner.ticket)
  owner.clearClaim()
  owner.store.clear()
  owner.localStore.clear()
  owner.pending = @[]
  owner.reports = @[]
  owner.localReports = @[]
  owner.policy = default(JudgmentReceiptPolicy)
