# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded source-free CE145 delivery preserves original signed records across original-grid forwarding and known successor broadcast. One exact native request/dial retires before another target takes ownership; no canonical state or signing key enters this host scheduler.
import std/[monotimes, times]
import ./[node, connections, endpoints, read_stream, read_client, audits, judgment_receipt, audit_participation]
import ../codec/[bounded, disputes]
import ../codec/state/safrole

const MaxJudgmentDeliveries = 3072 ## Three maximum1023-position recipient cohorts fit with fixed accounting slack.
type
  JudgmentDeliveryMode* {.pure.} = enum ## Relays preserve the original signature; produced judgments additionally reach all presently known succeeding author sets.
    Relayed, Produced
  JudgmentGossipPolicy* = object ## Whole row storage and lifetime per-record native work are explicit finite reservations.
    ready: bool
    message: AuditLimits
    entries, attempts, timeout, retry: int
    bytes: ByteLimit
    requests, dials: uint64
  Delivery = object ## Fixed copied recipient metadata and finite retry observations carry no native callback pointer.
    member: AuditParticipant
    attempts: int
    done, acknowledged: bool
    retry: MonoTime
    refresh: uint64
  GossipRow = object ## Expansion/deduplication is incremental; immutable public plans contain no leased private source alias.
    used: bool
    record: QualifiedJudgment
    request: ReadRequest
    plan: AuditParticipationPlan
    mode: JudgmentDeliveryMode
    peers: seq[Delivery]
    cursor, planCursor, scan: int
    candidateReady: bool
    requests, dials, reservation, refresh: uint64
  JudgmentGossip* = object ## Stable noncopyable owner holds exact cancellation authority for one physical delivery at a time.
    policy: JudgmentGossipPolicy
    rows: seq[GossipRow]
    bytes: uint64
    cursor: int
    active, requested, dialing, closing, finishing: bool
    row, peer: int
    request: NodeRequestTicket
    dial: DialTicket
    dialIdentity: StateEdKey
    started: MonoTime
    attempted, acknowledged, minimumEpoch: uint64
func judgmentGossipPolicy*(message: AuditLimits, entries: range[1..32768], bytes: ByteLimit,
    requestsPerRecord: range[1..12288] = 12288, dialsPerRecord: range[0..12288] = 3072,
    attempts: range[1..4] = 4, timeoutMs: range[1..120000] = 1000,
    retryMs: range[1..120000] = 1000): JudgmentGossipPolicy =
  ## At most four attempts per identity/plan and finite lifetime row quotas bound network work even across repeated genuine topology refreshes.
  if not message.valid or uint64(message.bytes) < 306 or sizeof(Delivery) > 512:
    return default(JudgmentGossipPolicy)
  if uint64(bytes) == 0 or uint64(bytes) > 64'u64*1024*1024*1024:
    return default(JudgmentGossipPolicy)
  JudgmentGossipPolicy(ready: true, message: message, entries: entries, bytes: bytes,
    requests: uint64(requestsPerRecord), dials: uint64(dialsPerRecord), attempts: attempts,
    timeout: timeoutMs, retry: retryMs)
func valid*(policy: JudgmentGossipPolicy): bool =
  ## Omission activates no delivery queue or outgoing wire.
  policy.ready
proc `=copy`*(destination: var JudgmentGossip, source: JudgmentGossip) {.error.}
  ## Duplicate ownership could cancel another scheduler's exact native stream or demand connection.
proc `=dup`*(source: JudgmentGossip): JudgmentGossip {.error.}
  ## Construction cannot duplicate live cancellation authority.
proc requireClosed(owner: JudgmentGossip) {.requires: not owner.active and not owner.requested and
    not owner.dialing.} =
  ## Explicit close requests exact native cancellation before scheduler storage retires.
  discard
proc `=wasMoved`*(owner: var JudgmentGossip) {.nodestroy, requires: not owner.active and
    not owner.requested and not owner.dialing.} =
  ## Only source-free closed storage moves; native callbacks belong exclusively to NodeService.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.rows)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.dial)
  `=wasMoved`(owner.dialIdentity)
proc `=destroy`*(owner: JudgmentGossip) =
  ## No implicit destructor abandons an exact outstanding native request or dial.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.rows)
  `=destroy`(owner.request)
  `=destroy`(owner.dial)
  `=destroy`(owner.dialIdentity)
func attempted*(owner: JudgmentGossip): uint64 =
  ## Count actual admitted requests, independently of waiting/busy attempts and remote consensus behavior.
  owner.attempted
func acknowledged*(owner: JudgmentGossip): uint64 =
  ## A remote bare FIN confirms complete receipt only, never report truth, block inclusion or finality.
  owner.acknowledged
func configured*(owner: JudgmentGossip): bool =
  ## Defaults have neither an enabled sender nor any inferred capacity.
  owner.policy.ready
func sending*(owner: JudgmentGossip): bool =
  ## Exact active ownership includes queued requests, physical dial retirement and bounded peer waits.
  owner.active
proc configure*(owner: var JudgmentGossip, policy: JudgmentGossipPolicy): bool =
  ## Configuration cannot erase retained acknowledgments or replace a live scheduler.
  if owner.policy.ready or not policy.ready or owner.active: return false
  owner.policy = policy
  owner.rows = newSeq[GossipRow](policy.entries)
  true
func sameKey(a, b: StateEdKey): bool =
  ## Physical identity deduplication never changes original validator ordinals in the immutable participation plan.
  array[32, byte](a) == array[32, byte](b)
func sameRecord(a, b: QualifiedJudgment): bool =
  ## Supporting-guarantee retries are not new judgment signatures; opposite valid claims remain distinct accountable records.
  sameJudgmentKey(a, b) and a.judgmentRecord.valid == b.judgmentRecord.valid
proc offer*(owner: var JudgmentGossip, record: QualifiedJudgment,
    plan: AuditParticipationPlan, mode: JudgmentDeliveryMode): bool =
  ## Whole worst-case recipient storage and fixed wire credit precede row mutation; later known E+2 plans extend delivery without erasing prior acknowledgments.
  if not owner.policy.ready or not record.valid or not plan.valid: return false
  let info = plan.participationInfo.value
  let raw = record.judgmentRecord
  if uint64(uint32(raw.epoch)) < owner.minimumEpoch: return false
  if info.epoch != uint64(uint32(raw.epoch)) or array[32, byte](info.report) != array[32, byte](
      raw.report): return false
  if info.localValidators == 0: return true # The receiver retains author evidence but is not an original auditor responsible for this epoch's forwarding.
  if raw.valid and mode == JudgmentDeliveryMode.Relayed: return true
  let reservation = info.retainedBytes+65536+uint64(MaxJudgmentDeliveries)*(uint64(sizeof(Delivery))+64)
  var available = -1
  for index in 0..<owner.policy.entries:
    # At most the configured number of original identities are compared; no unbounded report/map lookup occurs on the foreground actor.
    if owner.rows[index].used and sameRecord(owner.rows[index].record, record):
      let sameSource = array[32, byte](owner.rows[index].plan.participationInfo.value.source) ==
          array[32, byte](info.source)
      if sameSource and (owner.rows[index].mode == JudgmentDeliveryMode.Produced or mode ==
          JudgmentDeliveryMode.Relayed): return true
      if owner.rows[index].refresh == high(uint64): return false
      let old = owner.rows[index].reservation
      if reservation > old and reservation-old > uint64(
          owner.policy.bytes)-owner.bytes: return false
      owner.bytes = owner.bytes-old+reservation
      owner.rows[index].reservation = reservation
      owner.rows[index].plan = plan
      if mode == JudgmentDeliveryMode.Produced: owner.rows[index].mode = mode
      inc owner.rows[index].refresh
      owner.rows[index].planCursor = 0
      owner.rows[index].candidateReady = false
      owner.rows[index].scan = 0
      return true
    if not owner.rows[index].used and available < 0: available = index
  let neighbours = if raw.valid: 0 else: info.neighbours
  let successors = if mode == JudgmentDeliveryMode.Produced: info.successors else: 0
  if neighbours+successors == 0: return true # The retained outer obligation can reoffer when genuine later state reveals recipients.
  if available < 0 or reservation > uint64(owner.policy.bytes)-owner.bytes: return false
  let wire = encodeJudgments([raw], owner.policy.message)
  if wire.error != AuditError.None: return false
  let request = decodeReadRequest(ReadKind.Judgment, wire.value)
  if request.error != ReadError.None: return false
  owner.rows[available] = GossipRow(used: true, record: record, request: request.value,
    plan: plan, mode: mode, peers: @[], cursor: 0, planCursor: 0, scan: 0,
    candidateReady: false, requests: 0, dials: 0, reservation: reservation, refresh: 1)
  owner.bytes += reservation
  true
proc expand(owner: var JudgmentGossip, index: int) =
  ## Spend one comparison/extraction per turn so large recipient refreshes cannot stall ordinary native polling.
  if not owner.rows[index].used: return
  let info = owner.rows[index].plan.participationInfo.value
  let neighbours = if owner.rows[index].record.judgmentRecord.valid: 0 else: info.neighbours
  let successors = if owner.rows[index].mode == JudgmentDeliveryMode.Produced: info.successors else: 0
  if not owner.rows[index].candidateReady:
    let next = owner.rows[index].planCursor
    if next >= neighbours+successors: return
    owner.rows[index].candidateReady = true
    owner.rows[index].scan = 0
    inc owner.rows[index].planCursor
    return
  let scan = owner.rows[index].scan
  let next = owner.rows[index].planCursor-1
  let successor = next >= neighbours
  let ordinal = if successor: next-neighbours else: next
  let candidate = owner.rows[index].plan.participantAt(successor, ordinal).value
  if scan < owner.rows[index].peers.len:
    # Same identity already received by any original position/epoch needs no duplicate physical copy; actual source plans still preserve every role position.
    if sameKey(owner.rows[index].peers[scan].member.identity, candidate.identity):
      owner.rows[index].peers[scan].member = candidate
      if owner.rows[index].peers[scan].refresh != owner.rows[index].refresh:
        if not owner.rows[index].peers[scan].acknowledged and owner.rows[index].requests <
            owner.policy.requests:
          owner.rows[index].peers[scan].attempts = 0
          owner.rows[index].peers[scan].done = false
        owner.rows[index].peers[scan].refresh = owner.rows[index].refresh
      owner.rows[index].candidateReady = false
    else: inc owner.rows[index].scan
    return
  if owner.rows[index].peers.len < MaxJudgmentDeliveries:
    owner.rows[index].peers.add(Delivery(member: candidate, attempts: 0, done: false,
      acknowledged: false, retry: default(MonoTime), refresh: owner.rows[index].refresh))
  owner.rows[index].candidateReady = false # A full reserved row cannot allocate another identity; existing accountable records/acknowledgments remain intact.
proc retireDial(owner: var JudgmentGossip, streams: var NodeService, force: bool) =
  ## The fixed actual dial identity survives row refresh and target changes until its exact physical connection retires.
  if not owner.dialing: return
  if not streams.peerConnectionLive(owner.dial):
    owner.dialing = false
    owner.closing = false
    owner.dial = default(DialTicket)
  elif not owner.closing and (force or not streams.peerBusy(owner.dialIdentity)):
    owner.closing = streams.cancelPeerConnection(owner.dial)
proc finishAttempt(owner: var JudgmentGossip, streams: var NodeService, clock: MonoTime,
    acknowledged: bool) =
  ## Cancel only owned native request/dial authority. A failed bounded attempt is not a successful delivery.
  if owner.requested: discard streams.cancelRequest(owner.request)
  owner.requested = false
  owner.request = default(NodeRequestTicket)
  let row = owner.row
  let peer = owner.peer
  if acknowledged:
    owner.rows[row].peers[peer].done = true
    owner.rows[row].peers[peer].acknowledged = true
    if owner.acknowledged < high(uint64): inc owner.acknowledged
  else:
    owner.rows[row].peers[peer].retry = clock+initDuration(milliseconds = owner.policy.retry)
    if owner.rows[row].peers[peer].attempts >= owner.policy.attempts:
      owner.rows[row].peers[peer].done = true
  owner.finishing = true
  owner.retireDial(streams, false)
  if not owner.dialing: owner.active = false
proc startPeer(owner: var JudgmentGossip, streams: var NodeService, clock: MonoTime) =
  ## Prefer an existing authenticated generation; an owned demand dial is separately bounded and never replaces/cancels a pre-existing connection.
  let row = owner.row
  let peer = owner.peer
  let member = owner.rows[row].peers[peer].member
  let existing = streams.peerForIdentity(member.identity)
  if existing.error == NodeError.None:
    if owner.rows[row].requests >= owner.policy.requests:
      owner.rows[row].peers[peer].done = true
      owner.finishAttempt(streams, clock, false)
      return
    let request = streams.request(existing.value, owner.rows[row].request, ByteLimit(0))
    if request.error in [NodeError.Unavailable, NodeError.LimitExceeded]: return
    if request.error != NodeError.None:
      owner.finishAttempt(streams, clock, false)
      return
    owner.request = request.value
    owner.requested = true
    inc owner.rows[row].requests
    if owner.attempted < high(uint64): inc owner.attempted
  elif not owner.dialing:
    if member.endpoint.error != EndpointError.None or owner.rows[row].dials >= owner.policy.dials:
      owner.finishAttempt(streams, clock, false)
      return
    let dial = streams.beginPeerConnection(member.identity, member.endpoint.value)
    if dial.error == DialError.Unavailable: return
    if dial.error != DialError.None:
      owner.finishAttempt(streams, clock, false)
      return
    owner.dial = dial.value
    owner.dialIdentity = member.identity
    owner.dialing = true
    owner.closing = false
    inc owner.rows[row].dials
proc poll*(owner: var JudgmentGossip, streams: var NodeService, clock: MonoTime) =
  ## One exact native completion and at most64 bounded row turns preserve foreground fairness independently of Services worker leases.
  if not owner.policy.ready or not streams.isOpen: return
  if owner.active:
    let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
    if owner.finishing:
      owner.retireDial(streams, expired)
      if not owner.dialing: owner.active = false
      return
    if owner.requested:
      let reply = streams.takeReply(owner.request)
      if reply.error == ReadError.None:
        owner.requested = false
        owner.request = default(NodeRequestTicket)
        owner.finishAttempt(streams, clock, true)
      elif reply.error != ReadError.Unavailable or expired:
        owner.finishAttempt(streams, clock, false)
      return
    if expired:
      owner.finishAttempt(streams, clock, false)
      owner.retireDial(streams, true)
      return
    owner.startPeer(streams, clock)
    return
  for turn in 0..<64:
    # Each step touches one row and at most one deduplication comparison/recipient. Row/peer cursors advance without copying any private source graph.
    let row = owner.cursor
    owner.cursor = (owner.cursor+1) mod owner.policy.entries
    if not owner.rows[row].used: continue
    owner.expand(row)
    let count = owner.rows[row].peers.len
    if count == 0: continue
    let peer = owner.rows[row].cursor
    owner.rows[row].cursor = (peer+1) mod count
    if owner.rows[row].peers[peer].done or clock < owner.rows[row].peers[peer].retry: continue
    if sameKey(owner.rows[row].peers[peer].member.identity, streams.localIdentity):
      owner.rows[row].peers[peer].done = true
      continue
    owner.active = true
    owner.row = row
    owner.peer = peer
    owner.requested = false
    owner.dialing = false
    owner.closing = false
    owner.finishing = false
    owner.started = clock
    inc owner.rows[row].peers[peer].attempts
    owner.startPeer(streams, clock)
    return
proc expireBefore*(owner: var JudgmentGossip, streams: var NodeService, floor: uint64) =
  ## Exact cancellation releases only a retired record's owned stream and temporary connection.
  if floor <= owner.minimumEpoch: return
  owner.minimumEpoch = floor
  if not owner.policy.ready: return
  for row in 0..<owner.policy.entries:
    # Fixed rows preserve active/acknowledged delivery state for all surviving records.
    if not owner.rows[row].used or uint64(uint32(owner.rows[row].record.judgmentRecord.epoch)) >= floor:
      continue
    if owner.active and owner.row == row:
      if owner.requested: discard streams.cancelRequest(owner.request)
      if owner.dialing: discard streams.cancelPeerConnection(owner.dial)
      owner.active = false
      owner.requested = false
      owner.dialing = false
      owner.request = default(NodeRequestTicket)
      owner.dial = default(DialTicket)
    owner.bytes -= owner.rows[row].reservation
    owner.rows[row] = default(GossipRow)
proc close*(owner: var JudgmentGossip, streams: var NodeService) =
  ## Native NodeService owns callback buffers independently; exact cancellation precedes dropping only this scheduler's detached records and tokens.
  if owner.requested: discard streams.cancelRequest(owner.request)
  if owner.dialing: discard streams.cancelPeerConnection(owner.dial)
  owner.active = false
  owner.requested = false
  owner.dialing = false
  owner.closing = false
  owner.finishing = false
  owner.request = default(NodeRequestTicket)
  owner.dial = default(DialTicket)
  owner.dialIdentity = default(StateEdKey)
  owner.rows = @[]
  owner.policy = default(JudgmentGossipPolicy)
  owner.bytes = 0
  owner.cursor = 0
  owner.minimumEpoch = 0
