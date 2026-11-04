# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Timed proxy broadcast owns bounded exact native requests and detached checked proofs, never a canonical graph or CPU lease.
import std/[assertions, monotimes, times]
import ./[node, connections, read_stream, read_client, ticket_packet, ticket_validation, ticket_pool]
import ../codec/[bounded, header, tickets]
import ../codec/state/[safrole, trie]

const
  MaxTicketRecipients = 1023 ## Three positions per core in the largest supported full profile.
  MaxTicketForwards* = 16    ## Leave the shared64-request budget available to other protocol families.

type
  ForwardRow = object ## One byte per recipient encodes0/2/4 ready,1/3/5 in-flight and6 terminal (acknowledged or three failures).
    proof: CheckedNetworkTicket
    status: array[MaxTicketRecipients, byte]
    cursor: int
  ForwardExchange = object ## Exact queued/live native authority remains charged until collection or cancellation.
    active: bool
    ticket: NodeRequestTicket
    row, recipient: int
    started: MonoTime
  TicketForwarding* = object ## Noncopyable scheduler must explicitly retire all native cancellation authority before destruction.
    rows: seq[ForwardRow] # Allocated once to the checked actual population bound; never resized while exchanges are active.
    exchanges: array[MaxTicketForwards, ForwardExchange]
    recipients: seq[StateEdKey] # Keep roster geometry off the foreground thread stack too.
    local: StateEdKey
    included: seq[WinningTicketId]
    count, population, limit, cursor, active: int
    configured: bool
    context, lastBlock, lastRoot: array[32, byte]
    epoch, duration: uint32
    applied, first, finish, observed: uint64
    delivered: uint64
proc `=copy`*(destination: var TicketForwarding, source: TicketForwarding) {.error.}
  ## A second owner must not cancel or collect the same native requests.
proc `=dup`*(source: TicketForwarding): TicketForwarding {.error.}
  ## Initialization cannot duplicate native authority either.
proc `=wasMoved`*(owner: var TicketForwarding) {.nodestroy, requires: owner.active == 0.} =
  ## Only retired native requests permit moving detached proof and namespace storage.
  `=wasMoved`(owner.rows)
  `=wasMoved`(owner.recipients)
  `=wasMoved`(owner.exchanges)
  `=wasMoved`(owner.included)
  owner.count = 0
  owner.configured = false
proc requireClosed(owner: TicketForwarding) {.requires: owner.active == 0.} =
  ## Destruction is not an implicit cancellation of a live protocol exchange.
  discard
proc `=destroy`*(owner: TicketForwarding) =
  ## Explicit close retires native authority before checked proofs and peer namespaces leave scope.
  requireClosed(owner)
  `=destroy`(owner.rows)
  `=destroy`(owner.recipients)
  `=destroy`(owner.exchanges)
  `=destroy`(owner.included)
func len*(owner: TicketForwarding): int =
  ## Count retained deduplicated forwarding intents, including completed broadcasts until inclusion/expiry.
  owner.count
func sending*(owner: TicketForwarding): int =
  ## Observe charged exchanges independently of Services graph access.
  owner.active
func acknowledged*(owner: TicketForwarding): uint64 =
  ## Acknowledgments are delivery observations, never proof of canonical inclusion.
  owner.delivered
proc clearExchange(owner: var TicketForwarding, index: int) =
  ## Caller has collected or cancelled exactly this native request.
  owner.exchanges[index] = default(ForwardExchange)
  dec owner.active
proc close*(owner: var TicketForwarding, streams: var NodeService) =
  ## No foreign native request or Services CPU lease is touched.
  for index in 0..<MaxTicketForwards:
    if owner.exchanges[index].active:
      discard streams.cancelRequest(owner.exchanges[index].ticket)
      owner.clearExchange(index)
  for index in 0..<owner.count: owner.rows[index] = default(ForwardRow)
  owner.rows = @[]
  owner.recipients = @[]
  owner.count = 0
  owner.population = 0
  owner.included = @[]
  owner.cursor = 0
  owner.configured = false
proc remove(owner: var TicketForwarding, streams: var NodeService, row: int) =
  ## Dense-row removal updates every owned exchange before another index can denote a different proof.
  for index in 0..<MaxTicketForwards:
    if owner.exchanges[index].active and owner.exchanges[index].row == row:
      discard streams.cancelRequest(owner.exchanges[index].ticket)
      owner.clearExchange(index)
  let last = owner.count-1
  if row != last:
    owner.rows[row] = move(owner.rows[last])
    for index in 0..<MaxTicketForwards:
      if owner.exchanges[index].active and owner.exchanges[index].row == last:
        owner.exchanges[index].row = row
  owner.rows[last] = default(ForwardRow)
  dec owner.count
  owner.cursor = 0
proc expire*(owner: var TicketForwarding, streams: var NodeService, now: StateTime) =
  ## Clock-only retirement is safe during an unrelated immutable canonical CPU lease.
  if not owner.configured: return
  let observed = uint64(uint32(now))
  if observed < owner.observed or uint32(now) div owner.duration != owner.epoch or observed >= owner.finish:
    owner.close(streams)
    return
  owner.observed = observed
proc advance*(owner: var TicketForwarding, streams: var NodeService, source: TicketSource,
    now: StateTime, applied: StateTime): bool =
  ## Caller owns the graph gate; only fixed copied facts survive this selected-source activation.
  if not source.allowsTime(now, streams.connectivityEpoch):
    owner.close(streams)
    return false
  let duration = source.epochLength
  let epoch = source.epoch
  let first = uint64(uint32(applied))+uint64(max(duration div 20, 1'u32))
  let finish = uint64(epoch)*uint64(duration)+uint64(source.lotteryTail div 2)
  if uint32(applied) div duration != epoch or first >= finish or uint64(uint32(now)) >= finish:
    owner.close(streams)
    return false
  let context = source.contextHash
  if not owner.configured or owner.context != context or owner.applied != uint64(uint32(applied)):
    owner.close(streams)
    owner.context = context
    owner.applied = uint64(uint32(applied))
    owner.first = first
    owner.finish = finish
    owner.duration = duration
    owner.epoch = epoch
    owner.local = streams.localIdentity
    owner.population = source.currentCount
    let pending = source.pendingCount
    assert pending > 0 and pending <= MaxPendingNetworkTickets div 2
    owner.limit = pending*2 # Validate the bound before multiplying the actual population.
    owner.rows = newSeq[ForwardRow](owner.limit)
    owner.recipients = newSeq[StateEdKey](owner.population)
    assert owner.population <= MaxTicketRecipients and owner.limit <= MaxPendingNetworkTickets
    for index in 0..<owner.population: owner.recipients[index] = source.currentAt(index)
    owner.configured = true
    owner.lastBlock = default(array[32, byte])
    owner.lastRoot = default(array[32, byte])
  owner.observed = uint64(uint32(now))
  let blockHash = array[32, byte](source.sourceBlock)
  let root = array[32, byte](source.stateRoot)
  if owner.lastBlock != blockHash or owner.lastRoot != root:
    owner.included = source.includedIdentifiers # Independent copied IDs cannot race ARC ownership with a proof worker.
    var index = owner.count
    while index > 0:
      dec index
      if source.includes(owner.rows[index].proof.identifier): owner.remove(streams, index)
    owner.lastBlock = blockHash
    owner.lastRoot = root
  true
proc offer*(owner: var TicketForwarding, proof: CheckedNetworkTicket): bool =
  ## A distributed ticket cannot create proxy intent; the sealed context and proxy identity are rechecked at actual send.
  if not owner.configured or not proof.valid: return false
  if proof.delivery != TicketDelivery.Proxy or proof.contextHash != owner.context: return false
  if array[32, byte](proof.proxy) != array[32, byte](owner.local): return false
  let id = array[32, byte](proof.identifier)
  for included in owner.included:
    if array[32, byte](included) == id: return false
  for index in 0..<owner.count:
    if array[32, byte](owner.rows[index].proof.identifier) == id: return true
  if owner.count >= owner.limit: return false
  owner.rows[owner.count] = ForwardRow(proof: proof)
  inc owner.count
  true
proc poll*(owner: var TicketForwarding, streams: var NodeService, clock: MonoTime) =
  ## Collect at most16 exact native exchanges without touching finalized state or a shared worker.
  for index in 0..<MaxTicketForwards:
    if not owner.exchanges[index].active: continue
    let completed = streams.takeReply(owner.exchanges[index].ticket)
    let expired = clock < owner.exchanges[index].started or
      (clock-owner.exchanges[index].started).inMilliseconds >= 120000
    if completed.error == ReadError.Unavailable and not expired: continue
    let row = owner.exchanges[index].row
    let recipient = owner.exchanges[index].recipient
    assert row >= 0 and row < owner.count
    let status = owner.rows[row].status[recipient]
    assert status in [1'u8, 3, 5]
    if not expired and completed.error == ReadError.None:
      owner.rows[row].status[recipient] = 6
      if owner.delivered < high(uint64): inc owner.delivered
    else:
      discard streams.cancelRequest(owner.exchanges[index].ticket)
      owner.rows[row].status[recipient] = status+1 # Three failed complete exchanges exhaust only this proof/recipient pair.
    owner.clearExchange(index)
proc dispatch*(owner: var TicketForwarding, streams: var NodeService, now: StateTime,
    clock: MonoTime): bool =
  ## A fresh advance must precede this call; at most32 recipient checks and one admitted request bound main-loop work.
  if not owner.configured or owner.count == 0 or owner.population == 0 or owner.active >= MaxTicketForwards:
    return false
  if owner.observed != uint64(uint32(now)) or uint64(uint32(now)) < owner.first or
      uint64(uint32(now)) >= owner.finish or not streams.isValidator: return false
  for step in 0..<32:
    let row = owner.cursor
    owner.cursor = (owner.cursor+1) mod owner.count
    let ordinal = owner.rows[row].cursor
    owner.rows[row].cursor = (ordinal+1) mod owner.population
    let due = owner.first+uint64(ordinal)*(owner.finish-owner.first) div uint64(owner.population)
    if uint64(uint32(now)) < due or owner.rows[row].status[ordinal] notin [0'u8, 2, 4]: continue
    let key = owner.recipients[ordinal]
    let local = streams.localIdentity
    if array[32, byte](key) == default(array[32, byte]) or array[32, byte](key) == array[32, byte](local):
      owner.rows[row].status[ordinal] = 6
      continue # Vacant and local positions require no loopback transport.
    if array[32, byte](owner.rows[row].proof.proxy) != array[32, byte](local): return false
    let peer = streams.peerForIdentity(key)
    if peer.error != NodeError.None: continue
    let request = decodeReadRequest(ReadKind.TicketDistribution, owner.rows[
        row].proof.packet.packetBytes)
    assert request.error == ReadError.None
    let admitted = streams.request(peer.value, request.value, ByteLimit(0))
    if admitted.error != NodeError.None: continue # Shared quota pressure consumes no cryptographic or transmission attempt.
    for index in 0..<MaxTicketForwards:
      if not owner.exchanges[index].active:
        inc owner.rows[row].status[ordinal]
        owner.exchanges[index] = ForwardExchange(active: true, ticket: admitted.value, row: row,
            recipient: ordinal, started: clock)
        inc owner.active
        return true
    assert false # The charged count proved an unused exchange slot before Native admission.
  false
