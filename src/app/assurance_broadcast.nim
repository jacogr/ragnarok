# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional timed CE141 fanout owns only detached plans, collected signatures and exact native/worker tickets; fresh managed storage checks remain the sole signing authority.
import std/[monotimes, times]
import ./services
import ./proof/[worker, work_submission]
import ../jamnp-s/[node, connections, endpoints, read_stream, read_client, topology,
  assurance_schedule, assurance_record, assurance_possession, work_signer]
import ../codec/bounded
import ../codec/state/[safrole, consensus]

type
  AssuranceBroadcastPolicy* = object ## Explicit bounded planning, signing and whole-window network reservations leave omission inactive.
    ready: bool
    planning: AssuranceScheduleLimits
    signing: AssurancePossessionLimits
    period: uint64
    requests, dials, bytes: uint64
    parallel, peerTimeout, jobTimeout: int
  AssuranceBroadcastPhase* {.pure.} = enum ## A finished round claims transport acknowledgments only, never canonical inclusion.
    Idle, Planning, SignReady, Signing, Waiting, Sending, Retiring
  BroadcastPeerPhase {.pure.} = enum ## Duplicate identities and self have no additional wire obligation.
    Waiting, Connecting, Requested, Finished
  BroadcastPeer = object ## Fixed routing and exact tickets retain no canonical or private storage alias.
    member: Membership
    phase: BroadcastPeerPhase
    request: NodeRequestTicket
    dial: DialTicket
    dialing, closing: bool
    started: MonoTime
  AssuranceBroadcaster* = object ## Noncopyable stable controller cannot collect or join a foreign worker or native connection.
    policy: AssuranceBroadcastPolicy
    phase: AssuranceBroadcastPhase
    plan: AssuranceSchedule
    window: AssuranceWindow
    proof: ProofWorkerTicket
    active: bool
    started, jobStarted: MonoTime
    deadlineMs: int64
    lastTarget: uint32
    request: ReadRequest
    peers: seq[BroadcastPeer]
    cursor: int
    usedRequests, usedDials, usedBytes: uint64
    attempted, acknowledged, rounds: uint64
func assuranceBroadcastPolicy*(planning: AssuranceScheduleLimits,
    signing: AssurancePossessionLimits, period: uint64, requests, dials: ElementLimit,
    bytes: ByteLimit, parallel: range[1..64] = 8,
    peerTimeoutMs: range[1..120000] = 1000,
    jobTimeoutMs: range[1..120000] = 2000): AssuranceBroadcastPolicy =
  ## Validate finite independent budgets before any roster copying, private import or native activation.
  if not planning.valid or not signing.valid or period < 3:
    return default(AssuranceBroadcastPolicy)
  if uint64(requests) == 0 or uint64(requests) > 1023 or uint64(dials) > 1023:
    return default(AssuranceBroadcastPolicy)
  if uint64(bytes) < 144 or uint64(bytes) > 1023'u64*144:
    return default(AssuranceBroadcastPolicy)
  AssuranceBroadcastPolicy(ready: true, planning: planning, signing: signing,
    period: period, requests: uint64(requests), dials: uint64(dials), bytes: uint64(bytes),
    parallel: parallel, peerTimeout: peerTimeoutMs, jobTimeout: jobTimeoutMs)
func valid*(policy: AssuranceBroadcastPolicy): bool =
  ## Default policies cannot enable a wire selector or worker.
  policy.ready
func phase*(owner: AssuranceBroadcaster): AssuranceBroadcastPhase =
  ## Fixed source-free progress remains safe during another worker's exclusive lease.
  owner.phase
func attempted*(owner: AssuranceBroadcaster): uint64 =
  ## Only actual admitted native requests increment this counter.
  owner.attempted
func acknowledged*(owner: AssuranceBroadcaster): uint64 =
  ## A remote bare FIN acknowledgment is not block inclusion.
  owner.acknowledged
func rounds*(owner: AssuranceBroadcaster): uint64 =
  ## Count fully retired bounded opportunities, including unsuccessful attempts.
  owner.rounds
proc `=copy`*(destination: var AssuranceBroadcaster, source: AssuranceBroadcaster) {.error.}
  ## Copies would duplicate exact cancellation and collection authority.
proc `=dup`*(source: AssuranceBroadcaster): AssuranceBroadcaster {.error.}
  ## Initialization cannot duplicate a live owner either.
proc requireClosed(owner: AssuranceBroadcaster) {.requires: not owner.active and owner.peers.len == 0.} =
  ## Explicit host retirement precedes dropping callback/worker controls.
  discard
proc `=wasMoved`*(owner: var AssuranceBroadcaster) {.nodestroy, requires: not owner.active and
    owner.peers.len == 0.} =
  ## Only a closed owner transfers its acyclic detached children.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.plan)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.peers)
proc `=destroy`*(owner: AssuranceBroadcaster) =
  ## Neither destruction nor default values silently abandon a live lease.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.plan)
  `=destroy`(owner.proof)
  `=destroy`(owner.request)
  `=destroy`(owner.peers)
proc configure*(owner: var AssuranceBroadcaster, services: Services,
    streams: var NodeService, policy: AssuranceBroadcastPolicy): bool =
  ## The healthy installed archive and explicitly imported signer must match the actual TLS owner; receipt remains independent.
  if owner.policy.ready or not policy.ready or not streams.isOpen: return false
  if not streams.isValidator or not services.assuranceSigningMatches(
      streams.localIdentity): return false
  let storage = services.assuranceStorageInfo
  if not storage.opened or storage.faulted: return false
  if not streams.enableAssuranceSending(): return false
  owner.policy = policy
  true
proc retireDial(owner: var AssuranceBroadcaster, streams: var NodeService,
    index: int, force: bool) =
  ## Cancellation requests keep their concurrency charge until actual native retirement.
  if not owner.peers[index].dialing: return
  if not streams.peerConnectionLive(owner.peers[index].dial):
    owner.peers[index].dialing = false
    owner.peers[index].closing = false
  elif not owner.peers[index].closing:
    if force or not streams.peerBusy(owner.peers[index].member.identity):
      owner.peers[index].closing = streams.cancelPeerConnection(owner.peers[index].dial)
proc retire(owner: var AssuranceBroadcaster, streams: var NodeService, force: bool) =
  ## Cancel only exact owned request/dial tokens, preserving every pre-existing connection.
  for index in 0..<owner.peers.len:
    discard streams.cancelRequest(owner.peers[index].request)
    owner.retireDial(streams, index, force)
  owner.phase = AssuranceBroadcastPhase.Retiring
func expired(owner: AssuranceBroadcaster, clock: MonoTime): bool =
  ## A finite monotonic upper bound still retires resources when a caller stops supplying wall time.
  (clock-owner.started).inMilliseconds >= owner.deadlineMs
proc beforePoll*(owner: var AssuranceBroadcaster, services: var Services,
    streams: var NodeService, clock: MonoTime, hasTime: bool, now: AssuranceTime) =
  ## Revoke stale queued output before native callbacks can flush it; foreign canonical leases grant no fresh-send authority.
  if owner.phase == AssuranceBroadcastPhase.Idle: return
  let overdue = owner.expired(clock) or (hasTime and uint64(now) >= uint64(owner.window.closeAt))
  if overdue:
    if owner.active: discard services.cancelStateProof(owner.proof)
    owner.retire(streams, true)
  elif owner.phase in [AssuranceBroadcastPhase.Waiting, AssuranceBroadcastPhase.Sending]:
    if not services.stateProofAvailable or not services.assuranceScheduleCurrent(owner.plan):
      owner.retire(streams, false)
proc finish(owner: var AssuranceBroadcaster) =
  ## Exact collection and physical dial retirement precede dropping public plan/wire storage.
  owner.plan = default(AssuranceSchedule)
  owner.request = default(ReadRequest)
  owner.proof = default(ProofWorkerTicket)
  owner.peers = @[]
  owner.cursor = 0
  owner.phase = AssuranceBroadcastPhase.Idle
  if owner.rounds < high(uint64): inc owner.rounds
proc poll*(owner: var AssuranceBroadcaster, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Collection never admits another job; matching tokens and finite deadlines remain independent of foreign work.
  if owner.phase == AssuranceBroadcastPhase.Idle: return
  if owner.active and not services.stateProofActive(owner.proof):
    owner.active = false
    owner.retire(streams, false) # External joined shutdown cannot leave a stale ticket waiting forever.
  if owner.active:
    let late = owner.expired(clock) or (clock-owner.jobStarted).inMilliseconds >=
        owner.policy.jobTimeout
    if late: discard services.cancelStateProof(owner.proof)
    let completed = services.collectStateProof(owner.proof)
    if completed.kind == ProofWorkerCompletionKind.Uninitialized: return
    owner.active = false
    owner.proof = default(ProofWorkerTicket)
    if late or owner.phase == AssuranceBroadcastPhase.Retiring:
      owner.retire(streams, true)
    elif owner.phase == AssuranceBroadcastPhase.Planning:
      if completed.kind == ProofWorkerCompletionKind.WorkSubmitted:
        let planned = completed.workSubmissionValue
        if planned.kind == WorkJobResultKind.AssuranceScheduled:
          owner.plan = planned.scheduledAssurance
          owner.phase = AssuranceBroadcastPhase.SignReady
        else:
          owner.retire(streams, false) # Failure grants no author set or selection prefix.
      else:
        owner.retire(streams, false) # Foreign/cancelled completions cannot manufacture a plan.
    elif owner.phase == AssuranceBroadcastPhase.Signing:
      if completed.kind == ProofWorkerCompletionKind.AssuranceSigned:
        let signed = completed.assuranceSigningValue
        if signed.error == AssuranceSigningError.None and services.assuranceScheduleCurrent(owner.plan):
          let encoded = services.currentAssuranceBytes(signed.value, ByteLimit(139))
          if encoded.error == AssuranceSigningError.None:
            let request = decodeReadRequest(ReadKind.Assurance, encoded.value)
            if request.error == ReadError.None:
              owner.request = request.value
              owner.phase = AssuranceBroadcastPhase.Waiting
            else:
              owner.retire(streams, false) # Exact framing failure cannot expose a malformed upload.
          else:
            owner.retire(streams, false) # A stale collected signature never revives from detached facts.
        else:
          owner.retire(streams, false) # Missing possession or changed source remains an unsuccessful round.
      else:
        owner.retire(streams, false) # Cancelled/foreign result contains no reusable private authority.
  if owner.phase == AssuranceBroadcastPhase.Retiring:
    owner.retire(streams, owner.expired(clock))
    var live = false
    for peer in owner.peers:
      if peer.dialing: live = true # Physical retirement remains charged after logical cancellation.
    if not owner.active and not live: owner.finish()
    return
  if owner.phase != AssuranceBroadcastPhase.Sending: return
  var pending = false
  for index in 0..<owner.peers.len:
    let phase = owner.peers[index].phase
    if phase == BroadcastPeerPhase.Requested:
      let reply = streams.takeReply(owner.peers[index].request)
      if reply.error == ReadError.None:
        owner.peers[index].phase = BroadcastPeerPhase.Finished
        if owner.acknowledged < high(uint64): inc owner.acknowledged
      elif reply.error != ReadError.Unavailable or (clock-owner.peers[
          index].started).inMilliseconds >= owner.policy.peerTimeout:
        discard streams.cancelRequest(owner.peers[index].request)
        owner.peers[index].phase = BroadcastPeerPhase.Finished
    elif phase == BroadcastPeerPhase.Connecting:
      if not streams.peerConnectionLive(owner.peers[index].dial) or (clock-owner.peers[
          index].started).inMilliseconds >= owner.policy.peerTimeout:
        owner.peers[index].phase = BroadcastPeerPhase.Finished
    if owner.peers[index].phase == BroadcastPeerPhase.Finished:
      owner.retireDial(streams, index, false)
    else:
      pending = true # Unscheduled or active destinations remain inside this same finite opportunity.
  if not pending: owner.retire(streams, false)
proc startPeer(owner: var AssuranceBroadcaster, streams: var NodeService,
    index: int, clock: MonoTime) =
  ## Prefer existing authenticated transport; new dials consume explicit whole-window reservations.
  let member = owner.peers[index].member
  let existing = streams.peerForIdentity(member.identity)
  if existing.error == NodeError.None:
    let bytes = uint64(owner.request.payloadLength)+5
    if owner.usedRequests >= owner.policy.requests or bytes > owner.policy.bytes-owner.usedBytes:
      owner.peers[index].phase = BroadcastPeerPhase.Finished
      return
    let started = streams.request(existing.value, owner.request, ByteLimit(0))
    if started.error in [NodeError.Unavailable, NodeError.LimitExceeded]: return
    if started.error != NodeError.None:
      owner.peers[index].phase = BroadcastPeerPhase.Finished
      return
    owner.peers[index].request = started.value
    owner.peers[index].phase = BroadcastPeerPhase.Requested
    owner.peers[index].started = clock
    inc owner.usedRequests
    owner.usedBytes += bytes
    if owner.attempted < high(uint64): inc owner.attempted
  elif owner.peers[index].phase == BroadcastPeerPhase.Waiting:
    let endpoint = member.endpoint
    if endpoint.error != EndpointError.None or owner.usedDials >= owner.policy.dials:
      owner.peers[index].phase = BroadcastPeerPhase.Finished
      return
    let started = streams.beginPeerConnection(member.identity, endpoint.value)
    if started.error == DialError.Unavailable: return
    if started.error != DialError.None:
      owner.peers[index].phase = BroadcastPeerPhase.Finished
      return
    owner.peers[index].dial = started.value
    owner.peers[index].dialing = true
    owner.peers[index].started = clock
    owner.peers[index].phase = BroadcastPeerPhase.Connecting
    inc owner.usedDials
proc submit*(owner: var AssuranceBroadcaster, services: var Services,
    streams: var NodeService, clock: MonoTime, now: AssuranceTime): bool {.raises.} =
  ## An explicit Common Era observation and idle canonical gate are mandatory for new planning, private signing and native output.
  if not owner.policy.ready or not services.stateProofAvailable: return false
  if owner.phase == AssuranceBroadcastPhase.Idle:
    let selected = assuranceWindow(now, owner.policy.period)
    if selected.error != AssuranceScheduleError.None: return false
    let window = selected.value
    if uint32(window.targetSlot) <= owner.lastTarget: return false
    let admitted = services.beginAssuranceSchedule(streams.localIdentity, window,
        owner.policy.planning)
    if admitted.error == StateProofAdmissionError.Busy: return false
    owner.lastTarget = uint32(window.targetSlot)
    if admitted.error != StateProofAdmissionError.None: return false
    owner.window = window
    owner.started = clock
    owner.deadlineMs = int64(uint64(window.closeAt)-uint64(now))*1000
    owner.jobStarted = clock
    owner.proof = admitted.value
    owner.active = true
    owner.usedRequests = 0
    owner.usedDials = 0
    owner.usedBytes = 0
    owner.phase = AssuranceBroadcastPhase.Planning
    return true
  if owner.expired(clock) or uint64(now) >= uint64(owner.window.closeAt):
    owner.retire(streams, true)
    return false
  if owner.phase == AssuranceBroadcastPhase.SignReady:
    if not services.assuranceScheduleCurrent(owner.plan):
      owner.retire(streams, false)
      return false
    let admitted = services.beginAssuranceSigning(owner.plan.scheduleSelection.value, now,
        owner.policy.signing)
    if admitted.error == AssuranceStorageStartError.Busy: return false
    if admitted.error != AssuranceStorageStartError.None:
      owner.retire(streams, false)
      return false
    owner.proof = admitted.value
    owner.active = true
    owner.jobStarted = clock
    owner.phase = AssuranceBroadcastPhase.Signing
    return true
  if owner.phase == AssuranceBroadcastPhase.Waiting:
    if uint64(now) < uint64(owner.window.sendAt): return false
    if not services.assuranceScheduleCurrent(owner.plan):
      owner.retire(streams, false)
      return false
    let count = owner.plan.scheduleInfo.value.authors
    owner.peers = newSeq[BroadcastPeer](count)
    let local = streams.localIdentity
    for index in 0..<count:
      owner.peers[index].member = owner.plan.scheduleTarget(index).value
      let key = owner.peers[index].member.identity
      if array[32, byte](key) == array[32, byte](local) or array[32, byte](key) == array[32, byte](
          nullValidator().ed25519):
        owner.peers[index].phase = BroadcastPeerPhase.Finished
      else:
        for previous in 0..<index:
          if array[32, byte](key) == array[32, byte](owner.peers[previous].member.identity):
            owner.peers[index].phase = BroadcastPeerPhase.Finished # All original positions remain in the plan; one upload reaches their common identity.
    owner.phase = AssuranceBroadcastPhase.Sending
  if owner.phase == AssuranceBroadcastPhase.Sending:
    if not services.assuranceScheduleCurrent(owner.plan):
      owner.retire(streams, false)
      return false
    var active = 0
    for peer in owner.peers:
      if peer.dialing or peer.phase == BroadcastPeerPhase.Requested: inc active
    let count = owner.peers.len
    for turn in 0..<min(count, 64):
      let index = owner.cursor
      owner.cursor = (owner.cursor+1) mod count
      if owner.peers[index].phase == BroadcastPeerPhase.Connecting:
        owner.startPeer(streams, index, clock) # An owned dial already occupies its reservation.
      elif owner.peers[index].phase == BroadcastPeerPhase.Waiting and active <
          owner.policy.parallel:
        owner.startPeer(streams, index, clock)
        if owner.peers[index].dialing or owner.peers[index].phase ==
            BroadcastPeerPhase.Requested: inc active
  false
proc close*(owner: var AssuranceBroadcaster, services: var Services, streams: var NodeService) =
  ## Join only this exact worker and ask native retirement only for this controller's tokens; the enclosing host then closes transport.
  if owner.active and services.stateProofActive(owner.proof): services.stopStateProofs()
  owner.active = false
  if owner.phase != AssuranceBroadcastPhase.Idle:
    owner.retire(streams, true)
    owner.peers = @[]
    owner.finish()
  owner.lastTarget = 0
  owner.policy = default(AssuranceBroadcastPolicy)
