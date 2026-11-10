# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional CE135 receipt and delivery require fresh managed verification, bounded detached retention and exact native ownership.
## Native callbacks retain raw bytes; this source-free controller owns only exact tickets, policy and pending candidates.

import std/[monotimes, times]
import ./services
import ./work_guarantee_pool
import ../jamnp-s/[node, connections, endpoints, read_client, read_stream, report_cache, work_distribution]
import ../codec/bounded
import ../codec/state/safrole

type
  WorkDistributionPolicy* = object ## Explicit CPU, storage, concurrency and deadline policy leaves omission disabled; deliver=false selects receipt only.
    ready: bool
    limits: WorkDistributionLimits
    entries: int
    bytes: ByteLimit
    timeout, peerTimeout, parallel: int
    deliver: bool
  WorkDeliveryPhase* {.pure.} = enum ## Idle/finished rounds claim neither all-recipient success nor canonical inclusion.
    Idle, Waiting, Checking, Sending, Retiring
  DeliveryPeerPhase {.pure.} = enum ## Self and already acknowledged identities need no new native request.
    Waiting, Connecting, Requested, Skipped, Acknowledged, Refused
  DeliveryPeer = object ## Fixed verified metadata and exact host/native controls carry no canonical source or signing alias.
    record: StateValidator
    phase: DeliveryPeerPhase
    request: NodeRequestTicket
    dial: DialTicket
    dialing, closingDial: bool
    started: MonoTime
  WorkDistributionDispatcher* = object ## Noncopyable exact namespace ownership cannot collect or join a different controller's work.
    policy: WorkDistributionPolicy
    pool: WorkGuaranteePool
    held, active, cancelled: bool
    ticket: NodeReadTicket
    request: ReadRequest
    token: WorkDistributionToken
    started: MonoTime
    received: uint64
    deliveryPhase: WorkDeliveryPhase
    deliveryRequest: ReadRequest
    deliveryToken: WorkDistributionToken
    lastSession: WorkSessionToken
    deliveryStarted: MonoTime
    deliveryInfo: WorkDistributionInfo
    peers: seq[DeliveryPeer]
    acknowledged: seq[StateEdKey]
    cursor: int
    refreshDelivery, preferIncoming: bool
    attempted, acknowledgedCount, refused, rounds: uint64

func workDistributionPolicy*(limits: WorkDistributionLimits,
    entries: range[1..MaxPendingGuarantees], bytes: ByteLimit,
    timeoutMs: range[1..120000] = 30000, peerTimeoutMs: range[1..120000] = 5000,
    parallel: range[1..64] = 8, deliver = true): WorkDistributionPolicy =
  ## Retention must accommodate one maximum accepted payload; native framing keeps its separate hard ceiling.
  let wire = uint64(limits.wireBytes)
  if wire == 0 or wire > uint64(MaxReadReplyBytes): return default(WorkDistributionPolicy)
  if uint64(bytes) < wire or uint64(bytes) > 32'u64*1024*1024: return default(WorkDistributionPolicy)
  if uint64(limits.targets) == 0 or uint64(limits.targets) > 2046: return default(WorkDistributionPolicy)
  WorkDistributionPolicy(ready: true, limits: limits, entries: entries, bytes: bytes,
      timeout: timeoutMs, peerTimeout: peerTimeoutMs, parallel: parallel, deliver: deliver)

func valid*(policy: WorkDistributionPolicy): bool =
  ## Default policy does not activate native receipt or allocate retention capacity.
  policy.ready

func received*(owner: WorkDistributionDispatcher): uint64 =
  ## Count only fresh, retained incoming guarantees whose live transport accepted the bare FIN.
  owner.received

func pendingCount*(owner: WorkDistributionDispatcher): int =
  ## Detached candidate occupancy is observable during any foreign canonical lease.
  owner.pool.len

func pendingBytes*(owner: WorkDistributionDispatcher): int =
  ## Exact canonical payload bytes exclude native input and report-cache framing.
  owner.pool.byteLength

proc pendingPayload*(owner: WorkDistributionDispatcher, ordinal: int): seq[byte] {.requires:
    ordinal >= 0 and ordinal < owner.pool.len.} =
  ## A later block/assurer consumer must freshly qualify this independently copied candidate.
  owner.pool.payloadAt(ordinal)

func deliveryPhase*(owner: WorkDistributionDispatcher): WorkDeliveryPhase =
  ## Fixed outgoing state remains observable while a foreign job owns canonical graphs.
  owner.deliveryPhase

func attempted*(owner: WorkDistributionDispatcher): uint64 =
  ## Count actual admitted native CE135 requests, including later refusal or cancellation.
  owner.attempted

func acknowledged*(owner: WorkDistributionDispatcher): uint64 =
  ## Count only complete remote bare-FIN responses; self-retention never increments this metric.
  owner.acknowledgedCount

func refused*(owner: WorkDistributionDispatcher): uint64 =
  ## Endpoint, connection and request refusals are distinct from transport acknowledgment.
  owner.refused

func rounds*(owner: WorkDistributionDispatcher): uint64 =
  ## Finished bounded rounds may include unavailable recipients; this is not an all-delivered counter.
  owner.rounds

func demandConnections*(owner: WorkDistributionDispatcher): int =
  ## Controller-owned dial reservations include busy/closing connections until exact native retirement is observed.
  result = 0
  for peer in owner.peers:
    if peer.dialing: inc result

proc `=copy`*(destination: var WorkDistributionDispatcher,
    source: WorkDistributionDispatcher) {.error.}
  ## Duplicate control would allow competing cancellation and claim retirement.

proc `=dup`*(source: WorkDistributionDispatcher): WorkDistributionDispatcher {.error.}
  ## Initialization cannot duplicate worker/stream authority either.

proc `=wasMoved`*(owner: var WorkDistributionDispatcher) {.nodestroy, requires:
    not owner.held and not owner.active and owner.deliveryPhase == WorkDeliveryPhase.Idle.} =
  ## Every retained child transfers only after explicit retirement of exact native/CPU controls.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.pool)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.token)
  `=wasMoved`(owner.deliveryRequest)
  `=wasMoved`(owner.deliveryToken)
  `=wasMoved`(owner.lastSession)
  `=wasMoved`(owner.peers)
  `=wasMoved`(owner.acknowledged)
  owner.held = false
  owner.active = false

proc requireClosed(owner: WorkDistributionDispatcher) {.requires:
    not owner.held and not owner.active and owner.deliveryPhase == WorkDeliveryPhase.Idle.} =
  ## A destructor cannot silently abandon or join a canonical borrower.
  discard

proc `=destroy`*(owner: WorkDistributionDispatcher) =
  ## Only source-free owners retire after the required explicit controller close.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.pool)
  `=destroy`(owner.request)
  `=destroy`(owner.token)
  `=destroy`(owner.deliveryRequest)
  `=destroy`(owner.deliveryToken)
  `=destroy`(owner.lastSession)
  `=destroy`(owner.peers)
  `=destroy`(owner.acknowledged)

proc configure*(owner: var WorkDistributionDispatcher, streams: var NodeService,
    policy: WorkDistributionPolicy): bool =
  ## Configure storage before opening native admission; no private signing key is required to receive a guarantee.
  if owner.policy.ready or not policy.ready or owner.held or owner.active: return false
  let entries = policy.entries
  if entries < 1 or entries > MaxPendingGuarantees: return false
  let capacity = range[1..MaxPendingGuarantees](entries)
  if not streams.enableDistributionStreams(): return false
  if not owner.pool.configure(capacity, policy.bytes): return false
  owner.policy = policy
  owner.preferIncoming = true
  true

proc clearClaim(owner: var WorkDistributionDispatcher) =
  ## Matching collection or joined revocation precedes host-only raw/token retirement.
  owner.held = false
  owner.active = false
  owner.cancelled = false
  owner.ticket = default(NodeReadTicket)
  owner.request = default(ReadRequest)
  owner.token = default(WorkDistributionToken)

proc reject(owner: var WorkDistributionDispatcher, streams: var NodeService) =
  ## Refusal closes only the claimed native stream and never manufactures a successful empty response.
  discard streams.reject(owner.ticket)
  owner.clearClaim()

proc pollIncoming(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, reports: var ReportCache, clock: MonoTime, now: StateTime) =
  ## Collection and source-free retirement precede CPU arbitration; this activation never submits a new job.
  if not owner.policy.ready: return
  owner.pool.expire(now)
  if not owner.held: return
  let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
  let live = streams.readLive(owner.ticket)
  if not owner.active:
    if expired or not live: owner.reject(streams)
    return
  if not services.workDistributionActive(owner.token):
    owner.reject(streams) # External joined shutdown revoked the old namespace, not a foreign worker.
    return
  if (expired or not live) and not owner.cancelled:
    owner.cancelled = services.cancelWorkDistribution(owner.token)
  let completed = services.collectWorkDistribution(owner.token)
  if completed.kind == WorkDistributionCompletionKind.Uninitialized: return
  owner.active = false
  owner.token = default(WorkDistributionToken)
  if expired or not live or owner.cancelled:
    owner.reject(streams)
    return
  if completed.kind != WorkDistributionCompletionKind.Completed:
    owner.reject(streams) # Actual verification failures cannot disclose a successful FIN.
    return
  let info = completed.distributionInfo
  if not services.workDistributionCurrent(info, now):
    return # Preserve the original native deadline and raw bytes for a fresh CPU qualification.
  if not owner.pool.canRemember(info):
    owner.reject(streams)
    return
  if reports.remember(completed.distributionReport) != ReportCacheError.None:
    owner.reject(streams)
    return
  if not owner.pool.remember(completed):
    owner.reject(streams)
    return
  let reply = captureReadReply(owner.request, [])
  if reply.error != ReadError.None:
    owner.reject(streams)
    return
  if streams.respond(owner.ticket, reply.value) == ReadError.None:
    if owner.received < high(uint64): inc owner.received
    owner.clearClaim()
  else:
    owner.reject(streams) # Retained candidate may remain locally useful despite a native reset or output refusal.

proc submitIncoming(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime, now: StateTime): bool {.raises.} =
  ## One complete filtered request waits under its original deadline; all source capture aliases retire inside Services before publication.
  if not owner.policy.ready or owner.active or owner.deliveryPhase == WorkDeliveryPhase.Checking or
      not services.stateProofAvailable: return false
  if not owner.held:
    let task = streams.takeRead(ReadKind.Guarantee)
    if task.error != NodeError.None: return false
    owner.ticket = task.value.ticket
    owner.request = task.value.request
    owner.started = clock
    owner.held = true
  if not streams.readLive(owner.ticket) or (clock-owner.started).inMilliseconds >=
      owner.policy.timeout:
    owner.reject(streams)
    return true
  let admitted = services.beginWorkDistribution(owner.request, now, owner.policy.limits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.reject(streams)
    return true
  owner.token = admitted.value
  owner.active = true
  owner.cancelled = false
  true

proc beginLocal*(owner: var WorkDistributionDispatcher, services: Services,
    session: WorkSessionToken, clock: MonoTime): bool =
  ## Offer an exact retained primary completion once; byte caches contain no worker-shared source/signer graph.
  if not owner.policy.ready or not owner.policy.deliver: return false
  if owner.deliveryPhase != WorkDeliveryPhase.Idle or sameWorkSession(owner.lastSession,
      session): return false
  if services.workSessionPhase(session) != WorkSessionPhase.Guaranteed: return false
  owner.lastSession = session
  let length = services.workExchangeInfo(session).guaranteeBytes
  if length <= 0 or uint64(length) > uint64(owner.policy.limits.wireBytes): return false
  let request = decodeReadRequest(ReadKind.Guarantee, services.workGuaranteePayload(session))
  if request.error != ReadError.None: return false
  owner.deliveryRequest = request.value
  owner.deliveryStarted = clock
  owner.acknowledged = @[]
  owner.deliveryPhase = WorkDeliveryPhase.Waiting
  true

proc retireDeliveryDial(owner: var WorkDistributionDispatcher, streams: var NodeService,
    index: int, force: bool) =
  ## A close request is not physical retirement: retain the exact token and concurrency charge until the native owner releases it.
  if not owner.peers[index].dialing: return
  if not streams.peerConnectionLive(owner.peers[index].dial):
    owner.peers[index].dialing = false
    owner.peers[index].closingDial = false
    return
  let idle = not streams.peerBusy(owner.peers[index].record.ed25519)
  if not owner.peers[index].closingDial and (force or idle):
    owner.peers[index].closingDial = streams.cancelPeerConnection(owner.peers[index].dial)

proc cancelDeliveryPeers(owner: var WorkDistributionDispatcher, streams: var NodeService,
    force = false) =
  ## Only exact owned native requests/dials may be cancelled; pre-existing authenticated connections retain their original owner.
  for index in 0..<owner.peers.len:
    discard streams.cancelRequest(owner.peers[index].request)
    owner.retireDeliveryDial(streams, index, force)

proc retireDelivery(owner: var WorkDistributionDispatcher, streams: var NodeService,
    refresh: bool) =
  ## Refresh never re-signs or changes the original slot; acknowledgment history remains until the whole round finishes.
  owner.cancelDeliveryPeers(streams)
  owner.refreshDelivery = refresh
  owner.deliveryPhase = WorkDeliveryPhase.Retiring

proc clearDelivery(owner: var WorkDistributionDispatcher) =
  ## Exact collection/retirement precedes dropping independently owned wire/record/history storage.
  owner.deliveryRequest = default(ReadRequest)
  owner.deliveryToken = default(WorkDistributionToken)
  owner.peers = @[]
  owner.acknowledged = @[]
  owner.deliveryInfo = default(WorkDistributionInfo)
  owner.refreshDelivery = false
  owner.cursor = 0
  owner.deliveryPhase = WorkDeliveryPhase.Idle

proc beforePoll*(owner: var WorkDistributionDispatcher, services: Services,
    streams: var NodeService, now: StateTime) =
  ## Revoke stale queued sends before native callbacks can flush them; foreign source leases permit only fixed clock checks.
  if owner.deliveryPhase != WorkDeliveryPhase.Sending: return
  if uint32(now) > uint32(owner.deliveryInfo.lastSlot):
    owner.retireDelivery(streams, false)
    return
  if uint32(now) != uint32(owner.deliveryInfo.observed):
    owner.retireDelivery(streams, true)
  elif services.stateProofAvailable:
    if not services.workDistributionCurrent(owner.deliveryInfo, now): owner.retireDelivery(streams, true)

func knownAcknowledgment(owner: WorkDistributionDispatcher, key: StateEdKey): bool =
  ## Bounded distinct identities survive fresh roster plans without resetting delivery at the first recipient.
  for prior in owner.acknowledged:
    if array[32, byte](prior) == array[32, byte](key): return true
  false

proc refusePeer(owner: var WorkDistributionDispatcher, index: int) =
  ## One terminal peer refusal never manufactures an acknowledgment or mutates another peer's native controls.
  owner.peers[index].phase = DeliveryPeerPhase.Refused
  if owner.refused < high(uint64): inc owner.refused

proc pollDelivery(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, reports: var ReportCache, clock: MonoTime, now: StateTime) =
  ## Matching collection and bounded source-free I/O retirement never admit another CPU job here.
  if owner.deliveryPhase == WorkDeliveryPhase.Idle: return
  let expired = (clock-owner.deliveryStarted).inMilliseconds >= owner.policy.timeout
  if owner.deliveryPhase == WorkDeliveryPhase.Checking:
    if not services.workDistributionActive(owner.deliveryToken):
      owner.retireDelivery(streams, false)
      return
    if expired: discard services.cancelWorkDistribution(owner.deliveryToken)
    let completed = services.collectWorkDistribution(owner.deliveryToken)
    if completed.kind == WorkDistributionCompletionKind.Uninitialized: return
    owner.deliveryToken = default(WorkDistributionToken)
    if expired or completed.kind != WorkDistributionCompletionKind.Completed:
      owner.retireDelivery(streams, false)
      return
    let info = completed.distributionInfo
    if not services.workDistributionCurrent(info, now):
      owner.deliveryPhase = WorkDeliveryPhase.Waiting
      return
    if not info.withinCredentialWindow or not owner.pool.canRemember(info):
      owner.retireDelivery(streams, false)
      return
    if reports.remember(completed.distributionReport) != ReportCacheError.None or
        not owner.pool.remember(completed):
      owner.retireDelivery(streams, false)
      return
    owner.deliveryInfo = info
    owner.peers = newSeq[DeliveryPeer](info.targets)
    owner.cursor = 0
    let local = streams.localIdentity
    for index in 0..<owner.peers.len:
      let target = completed.distributionTarget(index)
      owner.peers[index].record = target
      let self = array[32, byte](target.ed25519) == array[32, byte](local)
      if self or owner.knownAcknowledgment(target.ed25519): owner.peers[
          index].phase = DeliveryPeerPhase.Skipped
    owner.deliveryPhase = WorkDeliveryPhase.Sending
  if owner.deliveryPhase == WorkDeliveryPhase.Retiring:
    owner.cancelDeliveryPeers(streams, expired)
    var dialing = false
    for peer in owner.peers:
      if peer.dialing: dialing = true
    if dialing: return
    owner.peers = @[]
    if owner.refreshDelivery and not expired:
      owner.refreshDelivery = false
      owner.deliveryPhase = WorkDeliveryPhase.Waiting
    else:
      if owner.rounds < high(uint64): inc owner.rounds
      owner.clearDelivery()
    return
  if expired:
    owner.retireDelivery(streams, false)
    return
  if owner.deliveryPhase != WorkDeliveryPhase.Sending: return
  var pending = false
  for index in 0..<owner.peers.len:
    let phase = owner.peers[index].phase
    if phase == DeliveryPeerPhase.Requested:
      let completed = streams.takeReply(owner.peers[index].request)
      if completed.error == ReadError.None:
        if owner.acknowledged.len >= 4092:
          owner.retireDelivery(streams, false)
          return # A deep reorganization cannot grow acknowledgment history without bound.
        owner.acknowledged.add(owner.peers[index].record.ed25519)
        owner.peers[index].phase = DeliveryPeerPhase.Acknowledged
        if owner.acknowledgedCount < high(uint64): inc owner.acknowledgedCount
      elif completed.error != ReadError.Unavailable or (clock-owner.peers[
          index].started).inMilliseconds >= owner.policy.peerTimeout:
        discard streams.cancelRequest(owner.peers[index].request)
        owner.refusePeer(index)
    elif phase == DeliveryPeerPhase.Connecting:
      let live = streams.peerConnectionLive(owner.peers[index].dial)
      if not live or (clock-owner.peers[index].started).inMilliseconds >= owner.policy.peerTimeout:
        owner.refusePeer(index) # Exact owned dials retire when idle or at the original overall deadline.
    if owner.peers[index].phase in [DeliveryPeerPhase.Acknowledged, DeliveryPeerPhase.Refused,
        DeliveryPeerPhase.Skipped]:
      owner.retireDeliveryDial(streams, index, false)
    if owner.peers[index].phase in [DeliveryPeerPhase.Waiting, DeliveryPeerPhase.Connecting,
        DeliveryPeerPhase.Requested]: pending = true
  if not pending: owner.retireDelivery(streams, false)

proc requestDeliveryPeer(owner: var WorkDistributionDispatcher, streams: var NodeService,
    index: int, clock: MonoTime) =
  ## Only the managed verifier's fixed record selects authenticated key and metadata endpoint.
  let target = owner.peers[index].record
  let existing = streams.peerForIdentity(target.ed25519)
  if existing.error == NodeError.None:
    let started = streams.request(existing.value, owner.deliveryRequest, ByteLimit(0))
    if started.error in [NodeError.Unavailable, NodeError.LimitExceeded]: return
    if started.error != NodeError.None:
      owner.refusePeer(index)
      return
    owner.peers[index].request = started.value
    owner.peers[index].started = clock
    owner.peers[index].phase = DeliveryPeerPhase.Requested
    if owner.attempted < high(uint64): inc owner.attempted
    return
  if owner.peers[index].phase == DeliveryPeerPhase.Connecting: return
  let endpoint = validatorEndpoint(array[128, byte](target.metadata))
  if endpoint.error != EndpointError.None:
    owner.refusePeer(index)
    return
  let dial = streams.beginPeerConnection(target.ed25519, endpoint.value)
  if dial.error == DialError.Unavailable: return
  if dial.error != DialError.None:
    owner.refusePeer(index)
    return
  owner.peers[index].dial = dial.value
  owner.peers[index].dialing = true
  owner.peers[index].started = clock
  owner.peers[index].phase = DeliveryPeerPhase.Connecting

proc submitDelivery(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime, now: StateTime): bool {.raises.} =
  ## One local CPU turn alternates with incoming work; new native queues require an available fresh canonical stamp.
  if owner.active: return false
  case owner.deliveryPhase
  of WorkDeliveryPhase.Waiting:
    let admitted = services.beginWorkDistribution(owner.deliveryRequest, now, owner.policy.limits)
    if admitted.error == StateProofAdmissionError.Busy: return false
    if admitted.error != StateProofAdmissionError.None:
      owner.retireDelivery(streams, false)
      return false
    owner.deliveryToken = admitted.value
    owner.deliveryPhase = WorkDeliveryPhase.Checking
    return true
  of WorkDeliveryPhase.Sending:
    if not services.workDistributionCurrent(owner.deliveryInfo, now):
      owner.retireDelivery(streams, true)
      return false
    var active = 0
    for peer in owner.peers:
      if peer.dialing or peer.phase in [DeliveryPeerPhase.Connecting,
          DeliveryPeerPhase.Requested]: inc active
    let count = owner.peers.len
    for inspected in 0..<min(64, count):
      let index = owner.cursor
      owner.cursor = (owner.cursor+1) mod count
      let phase = owner.peers[index].phase
      if phase == DeliveryPeerPhase.Connecting:
        owner.requestDeliveryPeer(streams, index, clock)
      elif phase == DeliveryPeerPhase.Waiting and active < owner.policy.parallel:
        owner.requestDeliveryPeer(streams, index, clock)
        if owner.peers[index].phase in [DeliveryPeerPhase.Connecting,
            DeliveryPeerPhase.Requested]: inc active
  else: discard # Checking/retiring/idle phases cannot submit or flush another round's controls.
  false

proc poll*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, reports: var ReportCache, clock: MonoTime, now: StateTime) =
  ## Source-free receipt and delivery collection share one exact managed namespace without stealing another lease.
  if not owner.policy.ready: return
  owner.pollIncoming(services, streams, reports, clock, now)
  owner.pollDelivery(services, streams, reports, clock, now)

proc submit*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime, now: StateTime): bool {.raises.} =
  ## A continuously ready local/incoming pair alternates closed worker admission within the outer application arbiter.
  if not owner.policy.ready or not services.stateProofAvailable: return false
  if owner.preferIncoming and owner.submitIncoming(services, streams, clock, now):
    owner.preferIncoming = false
    return true
  if owner.submitDelivery(services, streams, clock, now):
    owner.preferIncoming = true
    return true
  if owner.submitIncoming(services, streams, clock, now):
    owner.preferIncoming = false
    return true
  false

proc close*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService) =
  ## Joining requires successful exact cancellation; stale/default controls never interrupt a foreign lease.
  if owner.active:
    if services.cancelWorkDistribution(owner.token): services.stopStateProofs()
  if owner.deliveryPhase == WorkDeliveryPhase.Checking:
    if services.cancelWorkDistribution(owner.deliveryToken): services.stopStateProofs()
  owner.cancelDeliveryPeers(streams, true)
  owner.clearDelivery()
  owner.lastSession = default(WorkSessionToken)
  if owner.held: discard streams.reject(owner.ticket)
  owner.clearClaim()
  owner.pool.clear()
  owner.policy = default(WorkDistributionPolicy)
