# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Main-thread bounded possession-delivery scheduling retains fixed claims and exact native ticket authority only.
## The application rechecks canonical request and retained hash-checked content before dispatch; acknowledgments confer no state authority.
import std/[assertions, monotimes, times]
import ./[node, connections, read_stream, read_client, preimage_announcement]
import ../codec/bounded
import ../codec/state/requests

const MaxPreimageGossip* = 8 ## Match bounded content retention without growing with untrusted announcements.
const MaxGossipPeers = 3581 ## Three maximum validator rosters and both bounded guest classes.

type
  GossipIdentity = ref object ## Retained namespace prevents foreign/reopened schedulers accepting an old row token.
    marker: uint8
  Delivery = object ## One authenticated generation has finite retry and no canonical ownership.
    peer: NodePeer
    attempts: int
    done: bool
    retry: MonoTime
  GossipRow = object ## Fixed service/hash/length facts accompany bounded recipient observations.
    generation: uint64
    notice: PreimageAnnouncement
    peers: seq[Delivery]
    cursor: int
  GossipCandidate* = object ## Opaque row generation prevents delayed application checks targeting an evicted/reused row.
    owner: nil GossipIdentity
    row: int
    generation: uint64
    notice: PreimageAnnouncement
  PreimageGossip* = object ## Noncopyable cancellation authority must be explicitly retired before destruction.
    identity: nil GossipIdentity
    rows: array[MaxPreimageGossip, GossipRow]
    next: uint64
    cursor, count: int
    active: bool
    ticket: NodeRequestTicket
    activeRow, activePeer: int
    started: MonoTime
    delivered: uint64
proc `=copy`*(destination: var PreimageGossip, source: PreimageGossip) {.error.}
  ## Duplicating a scheduler would duplicate cancellation authority over its live stream.
proc `=dup`*(source: PreimageGossip): PreimageGossip {.error.}
  ## Initialization cannot duplicate the owner either.
proc `=wasMoved`*(owner: var PreimageGossip) {.nodestroy, requires: not owner.active.} =
  ## A retired scheduler can transfer only detached fixed claims and ARC peer namespaces.
  `=wasMoved`(owner.identity)
  `=wasMoved`(owner.rows)
  `=wasMoved`(owner.ticket)
  owner.active = false
  owner.count = 0
proc requireClosed(owner: PreimageGossip) {.requires: not owner.active.} =
  ## Destruction never abandons an exact outstanding native request.
  discard
proc `=destroy`*(owner: PreimageGossip) =
  ## Explicit close retires native authority before ARC observations leave scope.
  requireClosed(owner)
  `=destroy`(owner.identity)
  `=destroy`(owner.rows)
  `=destroy`(owner.ticket)
func len*(owner: PreimageGossip): int =
  ## Detached intent count is safe while a foreign graph lease is active.
  owner.count
func sending*(owner: PreimageGossip): bool =
  ## One active native ticket includes withheld acknowledgment FIN and queued local opens.
  owner.active
func deliveredCount*(owner: PreimageGossip): uint64 =
  ## Saturating diagnostics count successful acknowledgment collections, not remote adoption.
  owner.delivered
func valid*(candidate: GossipCandidate): bool =
  ## Defaults cannot select a row or authorize dispatch.
  candidate.owner != nil and candidate.generation != 0
func notice*(candidate: GossipCandidate): PreimageAnnouncement {.requires: candidate.valid.} =
  ## Return fixed untrusted claim facts for the application's fresh possession/request checks.
  candidate.notice
func live(owner: PreimageGossip, candidate: GossipCandidate): bool =
  ## Both ordinal and nonwrapping row generation precede any mutable access.
  if not candidate.valid or candidate.owner != owner.identity: return false
  if candidate.row < 0 or candidate.row >= MaxPreimageGossip: return false
  owner.rows[candidate.row].generation == candidate.generation
proc clearActive(owner: var PreimageGossip) =
  ## Caller has collected or cancelled the exact native request.
  owner.active = false
  owner.ticket = default(NodeRequestTicket)
  owner.started = default(MonoTime)
proc remove(owner: var PreimageGossip, streams: var NodeService, index: int) =
  ## Eviction cancels an active announcement before reusing its row or peer indexes.
  if owner.active and owner.activeRow == index:
    discard streams.cancelRequest(owner.ticket)
    owner.clearActive()
  if owner.rows[index].generation != 0:
    owner.rows[index] = default(GossipRow)
    dec owner.count
proc close*(owner: var PreimageGossip, streams: var NodeService) =
  ## Only exact owned network tickets are cancelled; no Services worker or canonical alias exists here.
  for index in 0..<MaxPreimageGossip: owner.remove(streams, index)
  owner.identity = nil
  owner.next = 0
  owner.cursor = 0
  owner.delivered = 0
proc offer*(owner: var PreimageGossip, streams: var NodeService, notice: PreimageAnnouncement,
    acknowledged = default(NodePeer)): bool =
  ## Queue only fixed claim facts; dispatch still requires the host's fresh canonical/content checks.
  if not notice.valid: return false
  if owner.identity == nil: owner.identity = GossipIdentity(marker: 1)
  var selected = -1
  for index in 0..<MaxPreimageGossip:
    if owner.rows[index].generation != 0 and sameAnnouncement(owner.rows[index].notice, notice):
      selected = index
      break # Duplicate possession cannot reset delivered peer observations or retry budgets.
  if selected < 0:
    if owner.next == high(uint64): return false
    for index in 0..<MaxPreimageGossip:
      if owner.rows[index].generation == 0:
        selected = index
        break
    if selected < 0:
      selected = 0
      for index in 1..<MaxPreimageGossip:
        if owner.rows[index].generation < owner.rows[selected].generation: selected = index
      owner.remove(streams, selected) # Oldest retained intent yields before fixed capacity is exceeded.
    inc owner.next
    owner.rows[selected] = GossipRow(generation: owner.next, notice: notice)
    inc owner.count
  if streams.peerLive(acknowledged):
    for index in 0..<owner.rows[selected].peers.len:
      if owner.rows[selected].peers[index].peer == acknowledged:
        owner.rows[selected].peers[index].done = true
        if owner.active and owner.activeRow == selected and owner.activePeer == index:
          discard streams.cancelRequest(owner.ticket)
          owner.clearActive() # A separate acknowledged publication already established delivery for this generation.
        return true
    if owner.rows[selected].peers.len < MaxGossipPeers:
      owner.rows[selected].peers.add(Delivery(peer: acknowledged, done: true))
  true
proc candidate*(owner: var PreimageGossip): GossipCandidate =
  ## Rotate at most eight rows; the application must recheck this exact candidate before dispatch.
  if owner.active: return default(GossipCandidate)
  for offset in 0..<MaxPreimageGossip:
    let index = (owner.cursor+offset) mod MaxPreimageGossip
    if owner.rows[index].generation != 0:
      owner.cursor = (index+1) mod MaxPreimageGossip
      return GossipCandidate(owner: owner.identity, row: index, generation: owner.rows[
          index].generation, notice: owner.rows[index].notice)
  default(GossipCandidate)
proc reject*(owner: var PreimageGossip, streams: var NodeService,
    candidate: GossipCandidate): bool =
  ## Withdrawal, eviction or failed current-state checks retire only the checked row generation.
  if not owner.live(candidate): return false
  owner.remove(streams, candidate.row)
  true
proc poll*(owner: var PreimageGossip, streams: var NodeService, clock: MonoTime) =
  ## Observe one exact acknowledgment while canonical state may be exclusively leased elsewhere.
  if not owner.active: return
  let completed = streams.takeReply(owner.ticket)
  let expired = clock < owner.started or (clock-owner.started).inMilliseconds >= 120000
  if completed.error == ReadError.Unavailable and not expired: return
  let row = owner.activeRow
  let position = owner.activePeer
  if expired or completed.error != ReadError.None: discard streams.cancelRequest(owner.ticket)
  if not expired and completed.error == ReadError.None:
    owner.rows[row].peers[position].done = true
    if owner.delivered < high(uint64): inc owner.delivered
  else:
    owner.rows[row].peers[position].done = owner.rows[row].peers[position].attempts >= 3
    owner.rows[row].peers[position].retry = clock+initDuration(seconds = 30)
  owner.clearActive()
proc dispatch*(owner: var PreimageGossip, streams: var NodeService,
    candidate: GossipCandidate, clock: MonoTime): bool =
  ## Caller just checked retained whole content and the canonical outstanding request outside native callbacks.
  if owner.active or not owner.live(candidate) or not streams.isValidator: return false
  let row = candidate.row
  let ordinal = owner.rows[row].cursor
  let recipient = streams.peerAt(ordinal)
  if recipient.error != NodeError.None:
    owner.rows[row].cursor = 0
    return false # Changed peer order is retraversed without retaining ordinal authority.
  if ordinal < MaxGossipPeers: inc owner.rows[row].cursor
  else: owner.rows[row].cursor = 0
  let peer = recipient.value
  if not streams.preimageNeighbour(peer): return false
  var position = -1
  for index in 0..<owner.rows[row].peers.len:
    if owner.rows[row].peers[index].peer == peer:
      position = index
      break
  if position < 0:
    if owner.rows[row].peers.len >= MaxGossipPeers:
      for index in 0..<owner.rows[row].peers.len:
        if not streams.peerLive(owner.rows[row].peers[index].peer):
          owner.rows[row].peers[index] = Delivery(peer: peer)
          position = index
          break # One stale generation yields its fixed observation slot to the fresh authenticated peer.
      if position < 0: return false
    else:
      position = owner.rows[row].peers.len
      owner.rows[row].peers.add(Delivery(peer: peer))
  if owner.rows[row].peers[position].done or clock < owner.rows[row].peers[
      position].retry: return false
  let admitted = streams.request(peer, candidate.notice.request, ByteLimit(0))
  if admitted.error != NodeError.None: return false # Native quota pressure retains intent and consumes no retry attempt.
  inc owner.rows[row].peers[position].attempts
  owner.active = true
  owner.activeRow = row
  owner.activePeer = position
  owner.ticket = admitted.value
  owner.started = clock
  true
