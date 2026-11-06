# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional CE144 receipt owns detached raw requests and exact native/managed tokens; native callbacks never verify signatures or touch canonical graphs.
import std/[monotimes, times]
import ./services
import ./audit_pool
import ./proof/[worker, work_submission]
import ../jamnp-s/[node, connections, read_stream, audit_receipt, audit_validation]
import ../codec/bounded

type
  AuditReceiptPolicy* = object ## Explicit canonical work, bounded candidate storage and native deadline leave omission inactive.
    ready: bool
    limits: AuditReceiptLimits
    entries, timeout: int
    bytes: ByteLimit
  AuditDispatcher* = object ## A stable noncopyable controller owns one incoming claim until exact collection or joined revocation.
    policy: AuditReceiptPolicy
    pool: AuditIntentPool
    held, active, cancelled: bool
    ticket: NodeReadTicket
    request: ReadRequest
    proof: ProofWorkerTicket
    started: MonoTime
    received: uint64
func auditReceiptPolicy*(limits: AuditReceiptLimits, entries: range[1..256],
    bytes: ByteLimit, timeoutMs: range[1..120000] = 30000): AuditReceiptPolicy =
  ## Separate context and pool ceilings keep explicit initial-proof receipt finite; omission remains inactive.
  if not limits.valid or uint64(bytes) == 0 or uint64(bytes) > 256'u64*1024*1024:
    return default(AuditReceiptPolicy)
  AuditReceiptPolicy(ready: true, limits: limits, entries: entries, bytes: bytes,
      timeout: timeoutMs)
func valid*(policy: AuditReceiptPolicy): bool =
  ## Default policy never activates a selector.
  policy.ready
proc `=copy`*(destination: var AuditDispatcher, source: AuditDispatcher) {.error.}
  ## Copies could retire another controller's live exact lease or native stream.
proc `=dup`*(source: AuditDispatcher): AuditDispatcher {.error.}
  ## Construction cannot duplicate a live token owner.
proc requireClosed(owner: AuditDispatcher) {.requires: not owner.held and not owner.active.} =
  ## Explicit retirement must precede destruction of any callback/controller storage.
  discard
proc `=wasMoved`*(owner: var AuditDispatcher) {.nodestroy, requires: not owner.held and
    not owner.active.} =
  ## Only an inactive controller moves; delegate all potentially owned children.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.pool)
  `=wasMoved`(owner.ticket)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.proof)
proc `=destroy`*(owner: AuditDispatcher) =
  ## The foreground host joins exact borrowed work before dropping this controller.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.pool)
  `=destroy`(owner.ticket)
  `=destroy`(owner.request)
  `=destroy`(owner.proof)
func configured*(owner: AuditDispatcher): bool =
  ## Outgoing initial declarations share the explicitly enabled validator selector.
  owner.policy.ready
func received*(owner: AuditDispatcher): uint64 =
  ## Count whole authenticated uploads for which the native route accepted the bare acknowledgment FIN.
  owner.received
func pendingCount*(owner: AuditDispatcher): int =
  ## Count distinct original checked declarations independently of transport peers and selected core count.
  owner.pool.len
proc pendingAt*(owner: AuditDispatcher, ordinal: int): CheckedAuditAnnouncement {.requires: (
    ordinal >= 0) and (ordinal < owner.pool.len).} =
  ## Copy immutable checked intent metadata without granting judgment, finality or private signing authority.
  owner.pool.announcementAt(ordinal)
proc configure*(owner: var AuditDispatcher, streams: var NodeService,
    policy: AuditReceiptPolicy): bool =
  ## Install bounded retention before explicitly enabling the separately optional validator selector.
  if owner.policy.ready or not policy.ready or owner.held or owner.active: return false
  if not streams.isValidator: return false
  if policy.entries < 1 or policy.entries > 256: return false
  if not owner.pool.configure(range[1..256](policy.entries), policy.bytes): return false
  if not streams.enableAuditStreams():
    owner.pool.clear()
    return false
  owner.policy = policy
  owner.received = 0 # A newly configured incarnation starts its own historical acceptance counter.
  true
proc clearClaim(owner: var AuditDispatcher) =
  ## Only exact managed retirement or proven joined revocation permits dropping the detached request/token owners.
  owner.held = false
  owner.active = false
  owner.cancelled = false
  owner.ticket = default(NodeReadTicket)
  owner.request = default(ReadRequest)
  owner.proof = default(ProofWorkerTicket)
proc reject(owner: var AuditDispatcher, streams: var NodeService) =
  ## Reject only this physical request; no success FIN or partial candidate escapes.
  discard streams.reject(owner.ticket)
  owner.clearClaim()
proc poll*(owner: var AuditDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Retire completions before another actor submits work; source-free intent retention never borrows a foreign canonical graph.
  if not owner.policy.ready: return
  if not owner.held: return
  let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
  let live = streams.readLive(owner.ticket)
  if not owner.active:
    if expired or not live: owner.reject(streams)
    return
  if not services.stateProofActive(owner.proof):
    owner.reject(streams) # A joined external stop revoked this exact native generation.
    return
  if (expired or not live) and not owner.cancelled:
    owner.cancelled = services.cancelStateProof(owner.proof)
  let completed = services.collectStateProof(owner.proof)
  if completed.kind == ProofWorkerCompletionKind.Uninitialized: return
  owner.active = false
  owner.proof = default(ProofWorkerTicket)
  if expired or not live or owner.cancelled or completed.kind !=
      ProofWorkerCompletionKind.WorkSubmitted:
    owner.reject(streams)
    return
  let outcome = completed.workSubmissionValue
  if outcome.kind != WorkJobResultKind.AuditAnnouncementsQualified:
    owner.reject(streams)
    return
  let checked = outcome.qualifiedAuditAnnouncements
  if not owner.pool.remember(checked):
    owner.reject(streams)
    return
  let reply = captureReadReply(owner.request, [])
  if reply.error == ReadError.None and streams.respond(owner.ticket, reply.value) == ReadError.None:
    if owner.received < high(uint64): inc owner.received
    owner.clearClaim()
  else: owner.reject(streams) # A whole authenticated declaration may survive a transport reset; its original audit obligation does not depend on the acknowledgment arriving.
proc submit*(owner: var AuditDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime): bool {.raises.} =
  ## One exact FIN-complete upload waits under its original deadline; actual TLS identity comes only from its live native ticket.
  if not owner.policy.ready or owner.active or not services.stateProofAvailable: return false
  if not owner.held:
    let incoming = streams.takeRead(ReadKind.AuditAnnouncement)
    if incoming.error != NodeError.None: return false
    owner.ticket = incoming.value.ticket
    owner.request = incoming.value.request
    owner.started = clock
    owner.held = true
  if not streams.readLive(owner.ticket) or (clock-owner.started).inMilliseconds >=
      owner.policy.timeout:
    owner.reject(streams)
    return true
  let admitted = services.beginAuditAnnouncements(owner.request.payload, owner.policy.limits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.reject(streams)
    return true
  owner.proof = admitted.value
  owner.active = true
  owner.cancelled = false
  true
proc close*(owner: var AuditDispatcher, services: var Services, streams: var NodeService) =
  ## Shutdown retires only this exact lease; an unrelated actor's worker must not be cancelled or joined.
  if owner.active and services.stateProofActive(owner.proof): services.stopStateProofs()
  if owner.held: discard streams.reject(owner.ticket)
  owner.clearClaim()
  owner.pool.clear()
  owner.policy = default(AuditReceiptPolicy)
