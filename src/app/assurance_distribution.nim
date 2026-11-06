# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional CE141 receipt owns detached raw requests and exact native/managed tokens; native callbacks never verify signatures or touch canonical graphs.
import std/[monotimes, times]
import ./services
import ./assurance_pool
import ./proof/[worker, work_submission]
import ../jamnp-s/[node, connections, read_stream, assurance_distribution]
import ../codec/assurances

type
  AssuranceReceiptPolicy* = object ## Explicit canonical work, bounded candidate storage and native deadline leave omission inactive.
    ready: bool
    limits: AssuranceDistributionLimits
    entries, indices, timeout: int
  AssuranceDispatcher* = object ## A stable noncopyable controller owns one incoming claim until exact collection or joined revocation.
    policy: AssuranceReceiptPolicy
    pool: AssurancePool
    held, active, cancelled: bool
    ticket: NodeReadTicket
    request: ReadRequest
    proof: ProofWorkerTicket
    started: MonoTime
    received: uint64
func assuranceReceiptPolicy*(limits: AssuranceDistributionLimits,
    entries: range[1..MaxPendingAssurances], indices: range[1..1023],
    timeoutMs: range[1..120000] = 30000): AssuranceReceiptPolicy =
  ## No implicit canonical budgets or unbounded pool can become a ready policy.
  if not limits.valid: return default(AssuranceReceiptPolicy)
  AssuranceReceiptPolicy(ready: true, limits: limits, entries: entries, indices: indices,
      timeout: timeoutMs)
func valid*(policy: AssuranceReceiptPolicy): bool =
  ## Default policy never activates a selector.
  policy.ready
proc `=copy`*(destination: var AssuranceDispatcher, source: AssuranceDispatcher) {.error.}
  ## Copies could retire another controller's live exact lease or native stream.
proc `=dup`*(source: AssuranceDispatcher): AssuranceDispatcher {.error.}
  ## Construction cannot duplicate a live token owner.
proc requireClosed(owner: AssuranceDispatcher) {.requires: not owner.held and not owner.active.} =
  ## Explicit retirement must precede destruction of any callback/controller storage.
  discard
proc `=wasMoved`*(owner: var AssuranceDispatcher) {.nodestroy, requires: not owner.held and
    not owner.active.} =
  ## Only an inactive controller moves; delegate all potentially owned children.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.pool)
  `=wasMoved`(owner.ticket)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.proof)
proc `=destroy`*(owner: AssuranceDispatcher) =
  ## The foreground host joins exact borrowed work before dropping this controller.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.pool)
  `=destroy`(owner.ticket)
  `=destroy`(owner.request)
  `=destroy`(owner.proof)
func received*(owner: AssuranceDispatcher): uint64 =
  ## Count retained fresh candidates for which the native route accepted the bare acknowledgment FIN.
  owner.received
func pendingCount*(owner: AssuranceDispatcher): int =
  ## Return expanded candidate occupancy independently from distinct peer rows.
  owner.pool.candidateCount
proc pendingAt*(owner: AssuranceDispatcher, ordinal: int): Assurance {.requires: ordinal >= 0 and
    ordinal < owner.pool.candidateCount.} =
  ## A copied unadmitted block candidate grants no current canonical authority.
  owner.pool.candidateAt(ordinal)
proc configure*(owner: var AssuranceDispatcher, streams: var NodeService,
    policy: AssuranceReceiptPolicy): bool =
  ## Install bounded retention before explicitly enabling the separately optional validator selector.
  if owner.policy.ready or not policy.ready or owner.held or owner.active: return false
  if not streams.isValidator: return false
  if policy.entries < 1 or policy.entries > MaxPendingAssurances or policy.indices < 1 or
      policy.indices > 1023: return false
  if not owner.pool.configure(range[1..MaxPendingAssurances](policy.entries), range[1..1023](
      policy.indices)): return false
  if not streams.enableAssuranceStreams():
    owner.pool.clear()
    return false
  owner.policy = policy
  owner.received = 0 # A newly configured incarnation starts its own historical acceptance counter.
  true
proc clearClaim(owner: var AssuranceDispatcher) =
  ## Only exact managed retirement or proven joined revocation permits dropping the detached request/token owners.
  owner.held = false
  owner.active = false
  owner.cancelled = false
  owner.ticket = default(NodeReadTicket)
  owner.request = default(ReadRequest)
  owner.proof = default(ProofWorkerTicket)
proc reject(owner: var AssuranceDispatcher, streams: var NodeService) =
  ## Reject only this physical request; no success FIN or partial candidate escapes.
  discard streams.reject(owner.ticket)
  owner.clearClaim()
proc poll*(owner: var AssuranceDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Retire completions before another actor submits work; source-free pool refresh never borrows a foreign canonical graph.
  if not owner.policy.ready: return
  owner.pool.refresh(services)
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
  if outcome.kind != WorkJobResultKind.AssuranceQualified:
    owner.reject(streams)
    return
  let checked = outcome.qualifiedAssurance
  if not services.assuranceDistributionCurrent(checked): return # Preserve the original raw claim/deadline for requalification.
  owner.pool.refresh(services)
  if not owner.pool.remember(checked):
    owner.reject(streams)
    return
  let reply = captureReadReply(owner.request, [])
  if reply.error == ReadError.None and streams.respond(owner.ticket, reply.value) == ReadError.None:
    if owner.received < high(uint64): inc owner.received
    owner.clearClaim()
  else: owner.reject(streams) # A valid locally retained candidate may survive a transport reset.
proc submit*(owner: var AssuranceDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime): bool {.raises.} =
  ## One exact FIN-complete upload waits under its original deadline; actual TLS identity comes only from its live native ticket.
  if not owner.policy.ready or owner.active or not services.stateProofAvailable: return false
  if not owner.held:
    let incoming = streams.takeRead(ReadKind.Assurance)
    if incoming.error != NodeError.None: return false
    owner.ticket = incoming.value.ticket
    owner.request = incoming.value.request
    owner.started = clock
    owner.held = true
  if not streams.readLive(owner.ticket) or (clock-owner.started).inMilliseconds >=
      owner.policy.timeout:
    owner.reject(streams)
    return true
  let admitted = services.beginAssuranceDistribution(owner.request,
      owner.ticket.sourcePeer.identity, owner.policy.limits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.reject(streams)
    return true
  owner.proof = admitted.value
  owner.active = true
  owner.cancelled = false
  true
proc close*(owner: var AssuranceDispatcher, services: var Services, streams: var NodeService) =
  ## Shutdown retires only this exact lease; an unrelated actor's worker must not be cancelled or joined.
  if owner.active and services.stateProofActive(owner.proof): services.stopStateProofs()
  if owner.held: discard streams.reject(owner.ticket)
  owner.clearClaim()
  owner.pool.clear()
  owner.policy = default(AssuranceReceiptPolicy)
