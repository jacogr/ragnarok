# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two locally generated checked tickets use bounded timed CE131 delivery; self-proxies belong to the separate CE132 scheduler.
## This owner retains no secret, canonical graph or CPU cancellation authority.
import std/[assertions, monotimes, times]
import ./[node, connections, read_stream, read_client, ticket_packet, ticket_validation]
import ../codec/[bounded, header, tickets]
import ../codec/state/[safrole, trie]

const MaxOriginTickets* = 2 ## Pinned network attempts0/1 bound one configured signer's retained epoch output.

type
  OriginRow = object ## A whole checked proof accompanies only its exact bounded Native exchange.
    proof: CheckedNetworkTicket
    active, acknowledged: bool
    attempts: int
    ticket: NodeRequestTicket
    started: MonoTime
  TicketOrigins* = object ## Noncopyable Native collection/cancellation authority must be explicitly retired.
    rows: array[MaxOriginTickets, OriginRow]
    included: seq[WinningTicketId]
    configured: bool
    count, active, cursor: int
    epoch, duration: uint32
    context, lastBlock, lastRoot: array[32, byte]
    local: StateEdKey
    applied, first, finish, observed: uint64
    delivered: uint64
proc `=copy`*(destination: var TicketOrigins, source: TicketOrigins) {.error.}
  ## Copies would duplicate cancellation of the same stream.
proc `=dup`*(source: TicketOrigins): TicketOrigins {.error.}
  ## Initialization must preserve exclusive Native ownership too.
proc `=wasMoved`*(owner: var TicketOrigins) {.nodestroy, requires: owner.active == 0.} =
  ## Detached proof/namespace owners may move only after exact Native retirement.
  `=wasMoved`(owner.rows)
  `=wasMoved`(owner.included)
  owner.count = 0
  owner.configured = false
proc requireClosed(owner: TicketOrigins) {.requires: owner.active == 0.} =
  ## Destruction cannot silently abandon an owned request.
  discard
proc `=destroy`*(owner: TicketOrigins) =
  ## Explicit close precedes proof/peer namespace release.
  requireClosed(owner)
  `=destroy`(owner.rows)
  `=destroy`(owner.included)
func len*(owner: TicketOrigins): int =
  ## Retained completed rows suppress duplicate offers through the same epoch context.
  owner.count
func sending*(owner: TicketOrigins): int =
  ## At most two exact requests are charged to the shared read pool.
  owner.active
func acknowledged*(owner: TicketOrigins): uint64 =
  ## Bare FIN is a delivery observation without canonical inclusion authority.
  owner.delivered
proc clearExchange(owner: var TicketOrigins, index: int) =
  ## Caller already collected/cancelled this exact request.
  owner.rows[index].active = false
  owner.rows[index].ticket = default(NodeRequestTicket)
  dec owner.active
proc remove(owner: var TicketOrigins, streams: var NodeService, index: int) =
  ## Inclusion/context retirement cancels only a request owned by this fixed row.
  if owner.rows[index].active:
    discard streams.cancelRequest(owner.rows[index].ticket)
    owner.clearExchange(index)
  if owner.rows[index].proof.valid:
    owner.rows[index] = default(OriginRow)
    dec owner.count
proc close*(owner: var TicketOrigins, streams: var NodeService) =
  ## Foreign network requests and every Services CPU lease remain untouched.
  for index in 0..<MaxOriginTickets: owner.remove(streams, index)
  owner.included = @[]
  owner.cursor = 0
  owner.configured = false
proc expire*(owner: var TicketOrigins, streams: var NodeService, now: StateTime) =
  ## Scalar clock retirement can run while an unrelated CPU job owns immutable canonical state.
  if not owner.configured: return
  let observed = uint64(uint32(now))
  if observed < owner.observed or uint32(now) div owner.duration != owner.epoch or observed >= owner.finish:
    owner.close(streams)
    return
  owner.observed = observed
proc advance*(owner: var TicketOrigins, streams: var NodeService, source: TicketSource,
    now: StateTime, applied: StateTime): bool =
  ## Refresh under the graph gate and retire all selected-source aliases before the next shared CPU admission.
  if not source.allowsTime(now, streams.connectivityEpoch):
    owner.close(streams)
    return false
  let epoch = source.epoch
  let duration = source.epochLength
  let first = uint64(uint32(applied))+uint64(max(duration div 60, 1'u32))
  let finish = uint64(epoch)*uint64(duration)+uint64(source.lotteryTail div 2)
  if uint32(applied) div duration != epoch or first >= finish or uint64(uint32(now)) >= finish:
    owner.close(streams)
    return false
  let context = source.contextHash
  if not owner.configured or owner.context != context or owner.applied != uint64(uint32(applied)):
    owner.close(streams)
    owner.context = context
    owner.local = streams.localIdentity
    owner.epoch = epoch
    owner.duration = duration
    owner.applied = uint64(uint32(applied))
    owner.first = first
    owner.finish = finish
    owner.lastBlock = default(array[32, byte])
    owner.lastRoot = default(array[32, byte])
    owner.configured = true
  owner.observed = uint64(uint32(now))
  let blockHash = array[32, byte](source.sourceBlock)
  let root = array[32, byte](source.stateRoot)
  if owner.lastBlock != blockHash or owner.lastRoot != root:
    owner.included = source.includedIdentifiers
    for index in 0..<MaxOriginTickets:
      if owner.rows[index].proof.valid and source.includes(owner.rows[index].proof.identifier):
        owner.remove(streams, index)
    owner.lastBlock = blockHash
    owner.lastRoot = root
  true
proc offer*(owner: var TicketOrigins, proof: CheckedNetworkTicket): bool =
  ## Raw packets, finalized IDs, wrong contexts and self-proxy proofs cannot create first-step work.
  if not owner.configured or not proof.valid: return false
  if proof.delivery != TicketDelivery.Proxy or proof.contextHash != owner.context: return false
  if array[32, byte](proof.proxy) == array[32, byte](owner.local): return false
  let id = array[32, byte](proof.identifier)
  for included in owner.included:
    if array[32, byte](included) == id: return false
  for index in 0..<MaxOriginTickets:
    if owner.rows[index].proof.valid and array[32, byte](owner.rows[index].proof.identifier) == id:
      return true # Acknowledged duplicates do not reset retry or delivery state.
  for index in 0..<MaxOriginTickets:
    if not owner.rows[index].proof.valid:
      owner.rows[index] = OriginRow(proof: proof)
      inc owner.count
      return true
  false
proc poll*(owner: var TicketOrigins, streams: var NodeService, clock: MonoTime) =
  ## Observe at most two exact acknowledgments without borrowing secret/source state.
  for index in 0..<MaxOriginTickets:
    if not owner.rows[index].active: continue
    let completed = streams.takeReply(owner.rows[index].ticket)
    let expired = clock < owner.rows[index].started or (clock-owner.rows[
        index].started).inMilliseconds >= 120000
    if completed.error == ReadError.Unavailable and not expired: continue
    if not expired and completed.error == ReadError.None:
      owner.rows[index].acknowledged = true
      if owner.delivered < high(uint64): inc owner.delivered
    else:
      discard streams.cancelRequest(owner.rows[index].ticket) # Native failures retain finite retry ownership only within the same window.
    owner.clearExchange(index)
proc dispatch*(owner: var TicketOrigins, streams: var NodeService, now: StateTime,
    clock: MonoTime): bool =
  ## Fresh source eligibility precedes at most two candidates and one admitted first-step exchange.
  if not owner.configured or owner.observed != uint64(uint32(now)): return false
  if uint64(uint32(now)) < owner.first or uint64(uint32(now)) >= owner.finish or
      not streams.isValidator: return false
  for offset in 0..<MaxOriginTickets:
    let index = (owner.cursor+offset) mod MaxOriginTickets
    if not owner.rows[index].proof.valid or owner.rows[index].active or owner.rows[
        index].acknowledged or owner.rows[index].attempts >= 3: continue
    let peer = streams.peerForIdentity(owner.rows[index].proof.proxy)
    if peer.error != NodeError.None: continue
    let request = decodeReadRequest(ReadKind.TicketProxy, owner.rows[
        index].proof.packet.packetBytes)
    assert request.error == ReadError.None
    let admitted = streams.request(peer.value, request.value, ByteLimit(0))
    if admitted.error != NodeError.None: continue # Quota pressure consumes no transmission attempt.
    owner.rows[index].active = true
    owner.rows[index].ticket = admitted.value
    owner.rows[index].started = clock
    inc owner.rows[index].attempts
    inc owner.active
    owner.cursor = (index+1) mod MaxOriginTickets
    return true
  false
