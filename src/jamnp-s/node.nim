# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable authenticated node stream owner. Native callbacks retain only protocol bytes/facts;
## host code collects fixed read tasks and supplies frozen replies after managed CPU work.
import std/[assertions, monotimes, times]
import ./[connections, admission, announcements, announcement_stream, read_stream, read_client, streams]
import ../chain/[provider, genesis]
import ../codec/[bounded, header, assurances]
import ../quic/transport
import ../codec/state/[safrole, consensus]

type
  NodeError* {.pure.} = enum ## Default/refused operations expose neither a partial task nor a source.
    Uninitialized, None, InvalidConfig, InvalidSource, NoFinality, BackendFailure,
    Unavailable, LimitExceeded, Exhausted
  NodeResult*[T] = object ## Only complete private success carries an owned result.
    case status: NodeError
    of None: completed: T
    else: discard         # Failure carries only a reason.
  NodeReadTicket* = object ## Fixed peer generation and nonwrapping serial contain no borrowed native pointer.
    peer: NodePeer
    serial: uint64
    index: int
  NodeRequestTicket* = object ## Outbound request authority is scoped to peer generation and a nonwrapping reserved frame serial.
    peer: NodePeer
    serial: uint64
    index: int
  NodeReadTask* = object ## A copied fixed request can cross a host/worker boundary without canonical state.
    ticket: NodeReadTicket
    request: ReadRequest
  NodeClaims* = object ## Detached authenticated source identity plus untrusted peer claims, never adoption authority.
    ready: bool
    peer: NodePeer
    stream: NativeStreamId
    claims: PeerAnnouncements
  FrameKind {.pure.} = enum ## Closing retains its original class and buffers until actual native retirement.
    Empty, Selecting, Read, Persistent, Client
  Frame = object ## Fixed global slots remain stable through all native stream callbacks.
    handle: NativeStream
    peer: NodePeer
    number: NativeStreamId
    kind: FrameKind
    closing, inputHandshake: bool
    started, activity, claimActivity, inputStarted, outputStarted: MonoTime
    offset: int
    serial, inputBytes, outputBytes, replyBytes, sentVersion: uint64
    read: ReadRoute
    client: ReadClientRoute
    announcement: AnnouncementRoute
  Peer = object ## Connection-lifetime watermark forbids rollback to a delayed lower UP0 ID.
    used, seen, queued, readQueued: bool
    readIndex: int
    peer: NodePeer
    highest: NativeStreamId
    connected, queuedAt: MonoTime
  LocalContext = object ## Fresh encoded bytes/fixed identities share no ARC owner with a canonical header/map.
    handshake: AnnouncementHandshake
    limits: AnnouncementLimits
    body: seq[byte]
  NodeService* = object ## Explicit noncopyable aggregate owns one connection actor and fixed protocol slots.
    opened, stopping: bool
    failure: NodeError
    callbacks, sweep, processCursor, peerCursor, broadcastCursor, readCursor: int
    serial, version, inputUsed, handshakeUsed, outputUsed, replyUsed, clientUsed: uint64
    now: MonoTime
    node: NodeConnections
    peers: seq[Peer]
    frames: seq[Frame]
    local: LocalContext
    limits: SafroleStateConfig

const MaxNodeReads = 64
const InputBudget = 32'u64*1024*1024
const HandshakeBudget = 16'u64*1024*1024
const OutputBudget = 32'u64*1024*1024
const ReplyBudget = 32'u64*1024*1024
const ClientBudget = 32'u64*1024*1024

proc `=copy`*(destination: var NodeService, source: NodeService) {.error: "NodeService owns stable native callbacks".}
  ## A copied parent would leave native callbacks borrowing the original storage.
proc `=dup`*(source: NodeService): NodeService {.error.}
  ## Initialization cannot duplicate this aggregate's native connection ownership.
proc `=wasMoved`*(owner: var NodeService) {.nodestroy, requires: not owner.opened.} =
  ## Only a completely retired owner may move, including every child and byte buffer.
  `=wasMoved`(owner.node)
  `=wasMoved`(owner.peers)
  `=wasMoved`(owner.frames)
  `=wasMoved`(owner.local)
  owner.opened = false
  owner.stopping = false
  owner.failure = NodeError.Uninitialized
  owner.callbacks = 0
  owner.sweep = 0
  owner.processCursor = 0
  owner.peerCursor = 0
  owner.broadcastCursor = 0
  owner.readCursor = 0
  owner.serial = 0
  owner.version = 0
  owner.inputUsed = 0
  owner.handshakeUsed = 0
  owner.outputUsed = 0
  owner.replyUsed = 0
  owner.clientUsed = 0
  owner.now = default(MonoTime)
  owner.limits = default(SafroleStateConfig)
proc requireClosed(owner: NodeService) {.requires: not owner.opened.} =
  ## Native engines retire explicitly while all enclosing callback state is still alive.
  discard
proc `=destroy`*(owner: NodeService) =
  ## Destruction never abandons live callbacks or silently cancels a foreign host's CPU lease.
  requireClosed(owner)
  `=destroy`(owner.node)
  `=destroy`(owner.peers)
  `=destroy`(owner.frames)
  `=destroy`(owner.local)
func error*[T](outcome: NodeResult[T]): NodeError =
  ## Inspect the private operation tag.
  outcome.status
func value*[T](outcome: NodeResult[T]): T {.requires: outcome.status == NodeError.None.} =
  ## Extract only a complete admitted result.
  outcome.completed
func ticket*(task: NodeReadTask): NodeReadTicket =
  ## Worker retirement uses copied facts, never a native stream pointer.
  task.ticket
func request*(task: NodeReadTask): ReadRequest =
  ## The request is fixed-size immutable transport data with no canonical graph.
  task.request
func valid*(source: NodeClaims): bool =
  ## Default source snapshots carry no authenticated source identity.
  source.ready
func peer*(source: NodeClaims): NodePeer {.requires: source.ready.} =
  ## Source identity remains tied to the original authenticated connection generation.
  source.peer
func stream*(source: NodeClaims): NativeStreamId {.requires: source.ready.} =
  ## Combine this persistent stream ID with the peer token when comparing source incarnations.
  source.stream
proc claims*(source: NodeClaims): PeerAnnouncements {.requires: source.ready.} =
  ## Claims remain detached untrusted metadata even after their original connection closes.
  source.claims
func error*(owner: NodeService): NodeError =
  ## Observe scalar failure state without touching canonical or native storage.
  owner.failure
func isOpen*(owner: NodeService): bool =
  ## Stopped/closed actors grant no new request or peer authority.
  owner.opened and not owner.stopping
proc localPort*(owner: NodeService): uint16 =
  ## The owned listener retains its actual port through the active lifetime.
  if owner.opened: owner.node.localPort else: 0'u16
proc peerCount*(owner: NodeService): int =
  ## Return current authenticated logical reservations, excluding pending replacement connections.
  if owner.opened: owner.node.peerCount else: 0
func peerIndex(owner: NodeService, peer: NodePeer): int =
  ## Only an exact generation can find a current connection record.
  for index in 0..<owner.peers.len:
    if owner.peers[index].used and owner.peers[index].peer == peer: return index
  -1
proc frameIndex(owner: NodeService, peer: NodePeer, stream: NativeStream): int =
  ## Borrowed handle equality is scoped to the authenticated peer's still-live callback mapping.
  for index in 0..<owner.frames.len:
    if owner.frames[index].kind != FrameKind.Empty and owner.frames[index].handle == stream and
        owner.frames[index].peer == peer: return index
  -1
func frameCount(owner: NodeService, peer: NodePeer, kind: FrameKind): int =
  ## Closing frames retain their budget until native close, preventing rapid reset/reopen overcommit.
  result = 0
  for index in 0..<owner.frames.len:
    if owner.frames[index].kind == kind and owner.frames[index].peer == peer: inc result
func reads(owner: NodeService): int =
  ## Global read slots are independent of each peer's selector and persistent reservations.
  result = 0
  for index in 0..<owner.frames.len:
    if owner.frames[index].kind in [FrameKind.Read, FrameKind.Client]: inc result
func localStream(peer: NodePeer, number: NativeStreamId): bool =
  ## IETF bit zero names client/server initiation independently of the connection's local direction.
  ((uint64(number) and 1) == 0) == peer.initiated
proc releaseFrame(owner: var NodeService, index: int) =
  ## Final native retirement revokes tickets and refunds exactly the owned frame's byte charges.
  let frame = addr owner.frames[index]
  if frame.kind == FrameKind.Client:
    assert frame.inputBytes <= owner.clientUsed
    owner.clientUsed -= frame.inputBytes
  elif frame.inputHandshake:
    assert frame.inputBytes <= owner.handshakeUsed
    owner.handshakeUsed -= frame.inputBytes
  else:
    assert frame.inputBytes <= owner.inputUsed
    owner.inputUsed -= frame.inputBytes
  assert frame.outputBytes <= owner.outputUsed and frame.replyBytes <= owner.replyUsed
  owner.outputUsed -= frame.outputBytes
  owner.replyUsed -= frame.replyBytes
  frame[] = default(Frame)
proc closeFrame(owner: var NodeService, index: int) =
  ## Cancel only this stream; frame buffers and charged credit remain owned through native close.
  let frame = addr owner.frames[index]
  if frame.kind == FrameKind.Empty or frame.closing: return
  frame.closing = true
  if frame.kind == FrameKind.Client and frame.handle == NativeStream(nil):
    let peerPosition = owner.peerIndex(frame.peer)
    if peerPosition >= 0 and owner.peers[peerPosition].readQueued and owner.peers[
        peerPosition].readIndex == index:
      assert owner.callbacks == 0
      discard owner.node.cancelStreamOpens(frame.peer) # Public native cancellation suppresses delayed open callbacks before this slot is reusable.
      owner.peers[peerPosition].readQueued = false
    owner.releaseFrame(index) # A cancelled queued intent or already-retired complete stream owns no live native handle.
    return
  wantRead(frame.handle, 0)
  wantWrite(frame.handle, 0)
  streamAbort(frame.handle)
proc accountClient(owner: var NodeService, index: int) =
  ## Detached input wire is charged until host collection or actual failed/cancelled retirement.
  let frame = addr owner.frames[index]
  let bytes = uint64(frame.client.bufferedBytes)
  if bytes > frame.inputBytes or frame.client.writtenBytes >
      frame.offset: frame.activity = owner.now
  frame.offset = frame.client.writtenBytes
  assert frame.inputBytes <= owner.clientUsed
  owner.clientUsed -= frame.inputBytes
  assert bytes <= ClientBudget-owner.clientUsed
  owner.clientUsed += bytes
  frame.inputBytes = bytes
proc accountAnnouncement(owner: var NodeService, index: int) =
  ## One host thread updates buffer deltas after a bounded route event/processing activation.
  let frame = addr owner.frames[index]
  let input = uint64(frame.announcement.pendingInputBytes)
  let offset = frame.announcement.writtenBytes
  if input > frame.inputBytes or offset > frame.offset: frame.activity = owner.now
  if input > 0 and frame.inputBytes == 0: frame.inputStarted = owner.now
  frame.offset = offset
  let output = uint64(frame.announcement.pendingOutputBytes)
  if output > 0 and frame.outputBytes == 0: frame.outputStarted = owner.now
  if frame.inputHandshake:
    assert frame.inputBytes <= owner.handshakeUsed
    owner.handshakeUsed -= frame.inputBytes
    assert input <= HandshakeBudget-owner.handshakeUsed
    owner.handshakeUsed += input
  else:
    assert frame.inputBytes <= owner.inputUsed
    owner.inputUsed -= frame.inputBytes
    assert input <= InputBudget-owner.inputUsed
    owner.inputUsed += input
  frame.inputBytes = input
  assert frame.outputBytes <= owner.outputUsed
  owner.outputUsed -= frame.outputBytes
  assert output <= OutputBudget-owner.outputUsed
  owner.outputUsed += output
  frame.outputBytes = output
proc bindPersistent(owner: var NodeService, index: int, local: bool): bool =
  ## Record the highest observed UP0 ID before any parsing; a bad replacement never revives old claims.
  let frame = addr owner.frames[index]
  let position = owner.peerIndex(frame.peer)
  if position < 0 or not persistentInitiator(frame.number) or not owner.node.announcements(
      frame.peer): return false
  let info = addr owner.peers[position]
  if local: info.queued = false # A refused observed open must not leave an unfulfillable pending intent.
  if info.seen and not preferPersistent(frame.number, info.highest): return false
  info.seen = true
  info.highest = frame.number
  info.connected = owner.now # Replacement handshakes receive their own bounded grace period.
  for prior in 0..<owner.frames.len:
    if prior != index and owner.frames[prior].kind == FrameKind.Persistent and owner.frames[
        prior].peer == frame.peer:
      owner.closeFrame(prior) # Revoke lower source eligibility before the new handshake can be observed.
  if owner.frameCount(frame.peer, FrameKind.Persistent) >= 2: return false
  let encoded = encodeHandshake(owner.local.handshake, owner.local.limits)
  if encoded.error != AnnouncementError.None: return false
  let needed = uint64(encoded.value.len)+5 # E4 plus optional selector; reserve conservatively for either side.
  if needed > OutputBudget-owner.outputUsed: return false
  if frame.announcement.bindStream(frame.handle, local, owner.local.handshake,
      owner.local.limits) != AnnouncementError.None: return false
  if not local and frame.announcement.acceptKind(0) != AnnouncementError.None: return false
  frame.kind = FrameKind.Persistent
  frame.inputHandshake = true
  frame.sentVersion = owner.version # The initial handshake already advertised the current leaf/finality facts.
  info.queued = false
  owner.accountAnnouncement(index)
  true
proc admissible(user: pointer, peer: NodePeer, stream: NativeStream): bool {.raises: [].} =
  ## Inspect only: the connection actor claims its raw route before the open callback owns buffers.
  let owner = cast[ptr NodeService](user)
  if owner.stopping or not owner.opened: return false
  let number = stream.streamId
  if (uint64(number) and 2) != 0: return false # Canonical methods and UP0 require bidirectional streams.
  let position = owner[].peerIndex(peer)
  if position < 0: return false
  if localStream(peer, number):
    if owner.peers[position].readQueued:
      let index = owner.peers[position].readIndex
      return index >= 0 and index < owner.frames.len and owner.frames[index].kind ==
          FrameKind.Client and owner.frames[index].peer == peer
    return peer.initiated and owner.peers[position].queued and owner.node.announcements(peer) and
        owner[].frameCount(peer, FrameKind.Persistent) < 2
  owner[].frameCount(peer, FrameKind.Selecting) ==
      0 # Every peer retains a selector reservation even while read slots are saturated.
proc peerEvent(user: pointer, peer: NodePeer, event: NodePeerEvent) {.raises: [].} =
  ## No canonical state or byte parser is touched by authenticated peer lifecycle observations.
  let owner = cast[ptr NodeService](user)
  inc owner.callbacks
  defer: dec owner.callbacks
  var position = owner[].peerIndex(peer)
  if event == NodePeerEvent.Ready:
    if owner.stopping:
      discard owner.node.disconnect(peer)
      return
    if position < 0:
      for index in 0..<owner.peers.len:
        if not owner.peers[index].used:
          position = index
          break
    if position < 0:
      discard owner.node.disconnect(peer)
      return # Logical capacity must not force unbounded application record allocation.
    owner.peers[position] = Peer(used: true, peer: peer, connected: owner.now)
  else:
    if position >= 0: owner.peers[position] = default(Peer)
    for index in 0..<owner.frames.len:
      if owner.frames[index].kind != FrameKind.Empty and owner.frames[index].peer == peer:
        if owner.frames[index].kind == FrameKind.Client and owner.frames[index].handle ==
            NativeStream(nil):
          owner[].releaseFrame(index) # Queued/complete retired client slots receive no later application callback for this closed generation.
        else:
          owner.frames[index].closing = true # Physical native retirement remains responsible for active stream storage.
proc streamEvent(user: pointer, peer: NodePeer, stream: NativeStream, event: cint) {.raises: [].} =
  ## Bounded selector/framing callbacks own no canonical graph or worker/source lease.
  let owner = cast[ptr NodeService](user)
  inc owner.callbacks
  defer: dec owner.callbacks
  var position = owner[].frameIndex(peer, stream)
  if event == 0:
    let peerPosition = owner[].peerIndex(peer)
    if localStream(peer, stream.streamId) and peerPosition >= 0 and owner.peers[
        peerPosition].readQueued:
      let index = owner.peers[peerPosition].readIndex
      owner.peers[peerPosition].readQueued = false
      let frame = addr owner.frames[index]
      frame.handle = stream
      frame.number = stream.streamId
      if frame.client.bindStream(stream) != ReadError.None: owner[].closeFrame(index)
      return # Exactly one serialized local intent matches this native open, including delayed library fulfillment.
    for index in 0..<owner.frames.len:
      if owner.frames[index].kind == FrameKind.Empty:
        position = index
        break
    if position < 0:
      streamAbort(stream)
      return
    owner.frames[position] = Frame(handle: stream, peer: peer, number: stream.streamId,
      kind: FrameKind.Selecting, started: owner.now, activity: owner.now)
    if localStream(peer, stream.streamId):
      if not owner[].bindPersistent(position, true): owner[].closeFrame(position)
    else:
      wantRead(stream, 1)
    return
  if position < 0: return # Refused/unmapped streams retain no application frame to touch.
  let frame = addr owner.frames[position]
  if event == 3:
    if frame.kind == FrameKind.Persistent:
      let peerPosition = owner[].peerIndex(peer)
      if peerPosition >= 0: owner.peers[peerPosition].connected = owner.now
    if frame.kind == FrameKind.Client:
      frame.client.event(stream, event)
      frame.handle = NativeStream(nil)
      if frame.client.ready and not frame.closing and owner.node.active(
          peer): return # Complete bytes outlive native retirement until host collection.
    elif frame.kind == FrameKind.Read: frame.read.event(stream, event)
    elif frame.kind == FrameKind.Persistent: discard frame.announcement.event(stream, event)
    owner[].releaseFrame(position)
    return
  if event == 4:
    if frame.kind == FrameKind.Client: frame.client.event(stream, event)
    elif frame.kind == FrameKind.Read: frame.read.event(stream, event)
    elif frame.kind == FrameKind.Persistent: discard frame.announcement.event(stream, event)
    let alreadyClosing = frame.closing
    frame.closing = true
    wantRead(stream, 0)
    wantWrite(stream, 0)
    if not alreadyClosing: streamAbort(stream) # A directional reset still requires explicit retirement of our application directions.
    return
  if frame.closing: return
  if owner.stopping:
    owner[].closeFrame(position)
    return
  case frame.kind
  of FrameKind.Selecting:
    if event != 1: return
    var kind = 0'u8
    let count = streamRead(stream, addr kind, 1)
    if count == -2: return
    if count != 1:
      owner[].closeFrame(position)
      return
    if kind == 0:
      if not owner[].bindPersistent(position, false): owner[].closeFrame(position)
    elif kind in [128'u8, 129'u8, 131'u8, 132'u8, 136'u8, 142'u8, 143'u8]:
      if kind == 142'u8 and not owner.node.isValidator:
        owner[].closeFrame(position)
        return # CE142 targets validators; a valid certificate or builder suffix cannot manufacture this role.
      if kind in [131'u8, 132'u8] and (not owner.node.isValidator or not owner.node.isValidator(peer)):
        owner[].closeFrame(position)
        return # Ticket protocols require both authenticated validator roles before any proof work or larger fixed input is admitted.
      let inboundReads = owner[].frameCount(peer, FrameKind.Read)
      let outboundReads = owner[].frameCount(peer, FrameKind.Client)
      if owner[].reads >= MaxNodeReads or inboundReads+outboundReads >= 2:
        owner[].closeFrame(position)
        return
      if frame.read.bindReadStream(stream, ReadKind(kind), kindConsumed = true) != ReadError.None:
        owner[].closeFrame(position)
        return
      frame.kind = FrameKind.Read
    else:
      owner[].closeFrame(position) # Other protocol families require their own validated runtime handlers.
  of FrameKind.Client:
    frame.client.event(stream, event, ByteLimit(ClientBudget-owner.clientUsed))
    owner[].accountClient(position)
  of FrameKind.Read:
    let before = frame.read.receivedBytes
    frame.read.event(stream, event)
    if frame.read.receivedBytes > before or frame.read.writtenBytes >
        frame.offset: frame.activity = owner.now
    frame.offset = frame.read.writtenBytes
  of FrameKind.Persistent:
    if frame.inputBytes == 0: frame.inputHandshake = not frame.announcement.active
    let budget = if frame.inputHandshake: HandshakeBudget-owner.handshakeUsed else: InputBudget-owner.inputUsed
    discard frame.announcement.event(stream, event, ByteLimit(budget))
    owner[].accountAnnouncement(position)
  of FrameKind.Empty: discard # Native close already revoked this physical route.
func announced(snapshot: BlockSnapshot): AnnouncedBlock =
  ## Copy source facts; no canonical header/map owner survives through this value.
  AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](snapshot.blockHash)), slot: HeaderSlot(snapshot.slot))
proc context(view: ChainView, limits: SafroleStateConfig): NodeResult[LocalContext] =
  ## Explicitly selected local finality is required; best head and peer claims imply none.
  let head = view.bestBlock
  let finalized = view.finalizedBlock
  if head.error != GenesisError.None: return NodeResult[LocalContext](
      status: NodeError.InvalidSource)
  if finalized.error != GenesisError.None: return NodeResult[LocalContext](
      status: NodeError.NoFinality)
  if finalized.value.slot > head.value.slot: return NodeResult[LocalContext](
      status: NodeError.InvalidSource)
  let policy = AnnouncementLimits(leaves: ElementLimit(64), bytes: ByteLimit(1048576),
    header: HeaderConfig(cores: limits.validators.cores, authorValidators: ValidatorCount(uint64(
        limits.validators.validators)),
      epochSlots: limits.epochSlots, maxBytes: ByteLimit(1048540)))
  var handshake = AnnouncementHandshake(finalized: announced(finalized.value))
  if array[32, byte](head.value.blockHash) != array[32, byte](finalized.value.blockHash):
    handshake.leaves = @[announced(head.value)]
  let encoded = encodeHandshake(handshake, policy)
  let body = encodeAnnouncement(head.value.header, handshake.finalized, policy)
  if encoded.error != AnnouncementError.None or body.error !=
      AnnouncementError.None: return NodeResult[LocalContext](status: NodeError.InvalidSource)
  NodeResult[LocalContext](status: NodeError.None, completed: LocalContext(handshake: handshake,
    limits: policy, body: body.value)) # Only fresh encoded bytes and fixed claim data escape.
proc close*(owner: var NodeService) {.requires: owner.callbacks == 0.} =
  ## Retire all engines/callbacks before dropping protocol buffers; host joins canonical jobs separately.
  owner.stopping = true
  owner.node.close()
  for index in 0..<owner.frames.len:
    assert owner.frames[index].kind == FrameKind.Empty, "every borrowed stream must receive native close"
  owner.frames = @[]
  owner.peers = @[]
  owner.local = default(LocalContext)
  owner.node = default(NodeConnections)
  owner.opened = false
  assert owner.inputUsed == 0 and owner.handshakeUsed == 0 and owner.outputUsed == 0 and
      owner.replyUsed == 0 and owner.clientUsed == 0
proc stop*(owner: var NodeService) =
  ## Callback-safe intent revokes new work; it does not join or release a host's canonical read lease.
  owner.stopping = true
  owner.node.stop()
proc open*(owner: var NodeService, config: ConnectionConfig, view: ChainView,
    limits: SafroleStateConfig): NodeError {.requires: owner.callbacks == 0.} =
  ## Capture all canonical facts before installing stable native callbacks and fixed protocol capacity.
  if owner.opened: return NodeError.InvalidConfig
  let cores = uint64(limits.validators.cores)
  if cores < 2 or cores > 341: return NodeError.InvalidConfig
  let capacity = int(cores*9)+int(config.builders)+int(config.others)
  let frames = capacity*3+MaxNodeReads # Checked profile/budgets prove at most10807 slots before allocation.
  if int(config.streams) < frames: return NodeError.InvalidConfig
  let captured = context(view, limits)
  if captured.error != NodeError.None: return captured.error
  owner.local = captured.value
  owner.limits = limits
  owner.sweep = 0
  owner.processCursor = 0
  owner.peerCursor = 0
  owner.broadcastCursor = 0
  owner.readCursor = 0
  owner.frames = newSeq[Frame](frames)
  owner.peers = newSeq[Peer](capacity)
  owner.now = getMonoTime()
  owner.stopping = false
  owner.failure = NodeError.None
  owner.version = 1
  owner.opened = true
  let opened = owner.node.open(config, view.finalizedBlock, limits, streamEvent, peerEvent,
    addr owner,
    admissionCallback = admissible)
  if opened != ConnectionError.None:
    owner.close()
    owner.failure = case opened
      of ConnectionError.InvalidConfig, ConnectionError.InvalidIdentity: NodeError.InvalidConfig
      of ConnectionError.InvalidTopology: NodeError.InvalidSource
      else: NodeError.BackendFailure # No failed low-level owner escapes factory cleanup.
    return owner.failure
  NodeError.None
proc advance*(owner: var NodeService, view: ChainView, now: StateTime): NodeResult[EpochUpdate] =
  ## Host updates truthfully selected metadata under its graph gate, independently of native polling.
  if not owner.isOpen: return NodeResult[EpochUpdate](status: NodeError.Unavailable)
  if owner.version == high(uint64): return NodeResult[EpochUpdate](status: NodeError.Exhausted)
  let captured = context(view, owner.limits)
  if captured.error != NodeError.None: return NodeResult[EpochUpdate](status: captured.error)
  let advanced = owner.node.advance(view, now)
  if advanced.error != AdmissionError.None: return NodeResult[EpochUpdate](
      status: NodeError.InvalidSource)
  owner.local = captured.value
  inc owner.version
  NodeResult[EpochUpdate](status: NodeError.None, completed: advanced.value)

proc peerAt*(owner: NodeService, ordinal: int): NodeResult[NodePeer] =
  ## Ordinals enumerate current peers only; the returned token still requires active-generation checks.
  if not owner.isOpen or ordinal < 0: return NodeResult[NodePeer](status: NodeError.Unavailable)
  var found = 0
  for index in 0..<owner.peers.len:
    if owner.peers[index].used and owner.node.active(owner.peers[index].peer):
      if found == ordinal: return NodeResult[NodePeer](status: NodeError.None,
          completed: owner.peers[index].peer)
      inc found
  NodeResult[NodePeer](status: NodeError.Unavailable)
proc peerForIdentity*(owner: NodeService, identity: StateEdKey): NodeResult[NodePeer] =
  ## Find an actual live authenticated generation without requiring announcement-grid eligibility.
  if not owner.isOpen: return NodeResult[NodePeer](status: NodeError.Unavailable)
  for index in 0..<owner.peers.len:
    if owner.peers[index].used:
      let peer = owner.peers[index].peer
      let matches = array[32, byte](peer.identity) == array[32, byte](identity)
      if matches and owner.node.active(peer):
        return NodeResult[NodePeer](status: NodeError.None, completed: peer)
  NodeResult[NodePeer](status: NodeError.Unavailable)
proc source*(owner: NodeService, peer: NodePeer): NodeResult[NodeClaims] =
  ## Capture only the greatest live UP0 incarnation's claims; they never certify a state root or finality.
  if not owner.isOpen or not owner.node.active(peer): return NodeResult[NodeClaims](
      status: NodeError.Unavailable)
  let position = owner.peerIndex(peer)
  if position < 0 or not owner.peers[position].seen: return NodeResult[NodeClaims](
      status: NodeError.Unavailable)
  for index in 0..<owner.frames.len:
    if owner.frames[index].kind == FrameKind.Persistent and not owner.frames[index].closing and
        owner.frames[index].peer == peer and uint64(owner.frames[index].number) == uint64(
            owner.peers[position].highest):
      let captured = owner.frames[index].announcement.snapshot
      if captured.available: return NodeResult[NodeClaims](status: NodeError.None,
        completed: NodeClaims(ready: true, peer: peer,
        stream: owner.frames[index].number, claims: captured.value))
  NodeResult[NodeClaims](status: NodeError.Unavailable)
proc requestLive*(owner: NodeService, ticket: NodeRequestTicket): bool =
  ## Native completion may already be retired, but stale/foreign generations never target reused slots.
  if not owner.isOpen or ticket.serial == 0 or ticket.index < 0 or ticket.index >=
      owner.frames.len: return false
  let frame = addr owner.frames[ticket.index]
  frame.kind == FrameKind.Client and not frame.closing and frame.serial == ticket.serial and
      frame.peer == ticket.peer and owner.node.active(ticket.peer)
proc request*(owner: var NodeService, peer: NodePeer, request: ReadRequest,
    maximum = ByteLimit(MaxReadReplyBytes)): NodeResult[
        NodeRequestTicket] {.requires: owner.callbacks == 0.} =
  ## Reserve a bounded read on the existing authenticated connection; only one local open intent per peer is outstanding.
  if not owner.isOpen or not owner.node.active(peer): return NodeResult[NodeRequestTicket](
      status: NodeError.Unavailable)
  if not request.valid: return NodeResult[NodeRequestTicket](status: NodeError.InvalidConfig)
  if request.kind in [ReadKind.TicketProxy, ReadKind.TicketDistribution]:
    if not owner.node.isValidator or not owner.node.isValidator(peer):
      return NodeResult[NodeRequestTicket](status: NodeError.InvalidSource) # Outbound ticket uploads have the same both-validator role boundary.
  let peerPosition = owner.peerIndex(peer)
  if peerPosition < 0: return NodeResult[NodeRequestTicket](status: NodeError.Unavailable)
  if owner.peers[peerPosition].queued or owner.peers[peerPosition].readQueued: return NodeResult[
      NodeRequestTicket](status: NodeError.Unavailable)
  if owner.node.announcements(peer) and owner.source(peer).error !=
      NodeError.None: return NodeResult[NodeRequestTicket](status: NodeError.Unavailable)
  if owner.reads >= MaxNodeReads or owner.frameCount(peer, FrameKind.Read)+owner.frameCount(peer,
      FrameKind.Client) >= 2:
    return NodeResult[NodeRequestTicket](status: NodeError.LimitExceeded)
  if owner.serial == high(uint64): return NodeResult[NodeRequestTicket](status: NodeError.Exhausted)
  var index = -1
  for candidate in 0..<owner.frames.len:
    if owner.frames[candidate].kind == FrameKind.Empty:
      index = candidate
      break # Fixed global slots include queued clients before any raw native route is claimed.
  if index < 0: return NodeResult[NodeRequestTicket](status: NodeError.LimitExceeded)
  var route = default(ReadClientRoute)
  if route.configure(request, maximum) != ReadError.None: return NodeResult[NodeRequestTicket](
      status: NodeError.InvalidConfig)
  inc owner.serial
  owner.frames[index] = Frame(kind: FrameKind.Client, peer: peer, serial: owner.serial,
    started: owner.now, activity: owner.now, client: route)
  owner.peers[peerPosition].readQueued = true
  owner.peers[peerPosition].readIndex = index
  if not owner.node.queueStream(peer):
    owner.peers[peerPosition].readQueued = false
    owner.releaseFrame(index)
    return NodeResult[NodeRequestTicket](status: NodeError.Unavailable)
  NodeResult[NodeRequestTicket](status: NodeError.None, completed: NodeRequestTicket(peer: peer,
      serial: owner.serial, index: index))
proc takeReply*(owner: var NodeService, ticket: NodeRequestTicket): ReadClientResult {.requires: owner.callbacks == 0.} =
  ## Collection transfers only a complete untrusted wire; physical reservations survive until native close.
  if not owner.requestLive(ticket): return clientFailure(ReadError.InvalidStream)
  let reply = owner.frames[ticket.index].client.take()
  if reply.error != ReadError.None: return reply
  owner.accountClient(ticket.index)
  owner.frames[ticket.index].closing = true
  if owner.frames[ticket.index].handle == NativeStream(nil): owner.releaseFrame(ticket.index)
  reply
proc cancelRequest*(owner: var NodeService, ticket: NodeRequestTicket): bool {.requires: owner.callbacks == 0.} =
  ## Queued cancellation removes both host/native pending opens; active cancellation waits for real native retirement.
  if not owner.requestLive(ticket): return false
  owner.closeFrame(ticket.index)
  true
func sourcePeer*(ticket: NodeReadTicket): NodePeer =
  ## Copied historical source still requires a live generation before followup; it never causes reconnection.
  ticket.peer
proc peerLive*(owner: NodeService, peer: NodePeer): bool =
  ## Followup may use only the original still-authenticated reservation.
  owner.isOpen and owner.node.active(peer)
func isValidator*(owner: NodeService): bool =
  ## Local accepted role is detached from canonical graph access.
  owner.isOpen and owner.node.isValidator
proc isValidator*(owner: NodeService, peer: NodePeer): bool =
  ## Recipient checks preserve current transport generation and gated roster membership.
  owner.isOpen and owner.node.isValidator(peer)
func localIdentity*(owner: NodeService): StateEdKey {.requires: owner.isOpen.} =
  ## Copy the actual validated local transport identity into a detached CPU recipient contract.
  owner.node.localIdentity
func connectivityEpoch*(owner: NodeService): uint32 {.requires: owner.isOpen.} =
  ## Packet certainty requires this accepted epoch to match finalized state and the observed local clock.
  owner.node.connectivityEpoch
proc preimageNeighbour*(owner: NodeService, peer: NodePeer): bool =
  ## Gossip requires both real validator roles and the accepted epoch-gated grid; ordinary UP0 eligibility is insufficient.
  owner.isOpen and owner.node.isValidator and owner.node.isValidator(peer) and
      owner.node.announcements(peer)
proc takeRead(owner: var NodeService, filtered: bool, kind: ReadKind): NodeResult[
    NodeReadTask] {.requires: owner.callbacks == 0.} =
  ## Rotate physical slots so a reused low slot cannot overtake an older waiting request at worker admission.
  if not owner.isOpen: return NodeResult[NodeReadTask](status: NodeError.Unavailable)
  for inspected in 0..<owner.frames.len:
    let index = owner.readCursor
    owner.readCursor = (owner.readCursor+1) mod owner.frames.len
    if owner.frames[index].kind != FrameKind.Read or owner.frames[index].closing: continue
    if not owner.node.active(owner.frames[index].peer): continue
    if filtered and owner.frames[index].read.selectedKind != kind: continue
    let request = owner.frames[index].read.takeRequest()
    if request.error != ReadError.None: continue # Incomplete, already taken and reset frames cannot create duplicate jobs.
    if owner.serial == high(uint64):
      owner.stop()
      return NodeResult[NodeReadTask](status: NodeError.Exhausted)
    inc owner.serial
    owner.frames[index].serial = owner.serial
    owner.frames[index].claimActivity = owner.frames[index].activity
    owner.frames[index].activity = owner.now
    let ticket = NodeReadTicket(peer: owner.frames[index].peer, serial: owner.serial, index: index)
    return NodeResult[NodeReadTask](status: NodeError.None, completed: NodeReadTask(ticket: ticket,
        request: request.value))
  NodeResult[NodeReadTask](status: NodeError.Unavailable)
proc takeRead*(owner: var NodeService): NodeResult[NodeReadTask] {.requires: owner.callbacks == 0.} =
  ## General worker admission retains the existing rotating ready-request order.
  owner.takeRead(false, ReadKind.Blocks)
proc takeRead*(owner: var NodeService, kind: ReadKind): NodeResult[
    NodeReadTask] {.requires: owner.callbacks == 0.} =
  ## Detached responders may inspect one method without taking unrelated canonical work while its graph is leased.
  owner.takeRead(true, kind)
proc readLive*(owner: NodeService, ticket: NodeReadTicket): bool =
  ## Stale/foreign/closed tickets contain no native pointer and cannot target a reused slot.
  if not owner.isOpen or ticket.serial == 0 or ticket.index < 0 or ticket.index >=
      owner.frames.len: return false
  owner.frames[ticket.index].kind == FrameKind.Read and not owner.frames[ticket.index].closing and
    owner.frames[ticket.index].serial == ticket.serial and owner.frames[ticket.index].peer ==
        ticket.peer and owner.node.active(ticket.peer)
proc deferRead*(owner: var NodeService, ticket: NodeReadTicket): bool {.requires: owner.callbacks == 0.} =
  ## Revoke this exact claim immediately; restoring its prior activity prevents repeated cache misses extending inactivity.
  if not owner.readLive(ticket): return false
  if not owner.frames[ticket.index].read.deferRequest(): return false
  owner.frames[ticket.index].serial = 0
  owner.frames[ticket.index].activity = owner.frames[ticket.index].claimActivity
  true
proc respond*(owner: var NodeService, ticket: NodeReadTicket,
    reply: ReadReply): ReadError {.requires: owner.callbacks == 0.} =
  ## Charge bounded frozen output before copying; worker/canonical owners are already retired by the host.
  if not owner.readLive(ticket): return ReadError.InvalidStream
  let length = uint64(reply.byteLength)
  if length > ReplyBudget-owner.replyUsed: return ReadError.LimitExceeded
  let sent = owner.frames[ticket.index].read.respond(reply)
  if sent == ReadError.None:
    owner.frames[ticket.index].replyBytes = length
    owner.replyUsed += length
    owner.frames[ticket.index].activity = owner.now
  sent
proc reject*(owner: var NodeService, ticket: NodeReadTicket): bool {.requires: owner.callbacks == 0.} =
  ## Host refuses missing/busy data without fabricating an empty successful reply.
  if not owner.readLive(ticket): return false
  owner.closeFrame(ticket.index)
  true
proc poll*(owner: var NodeService, now: MonoTime, maximumMs: range[
    0..1] = 1): bool {.requires: owner.callbacks == 0.} =
  ## Native polling and bounded metadata/byte work continue while a host worker leases canonical state.
  if not owner.isOpen: return false
  if now < owner.now:
    owner.failure = NodeError.InvalidConfig
    owner.stop()
    return false
  owner.now = now
  if not owner.node.poll(now, maximumMs):
    owner.failure = if owner.node.error == ConnectionError.None: NodeError.Unavailable else: NodeError.BackendFailure
    owner.stopping = true
    return false
  var handled = 0
  for inspected in 0..<min(64, owner.frames.len):
    let index = owner.processCursor
    owner.processCursor = (owner.processCursor+1) mod owner.frames.len
    if owner.frames[index].kind == FrameKind.Persistent and not owner.frames[index].closing and
        owner.frames[index].announcement.messageReady:
      owner.frames[index].announcement.process() # Only detached peer bytes, never canonical headers/maps.
      owner.accountAnnouncement(index)
      if owner.frames[index].announcement.failed: owner.closeFrame(index)
      inc handled
      if handled == 4: break
  for inspected in 0..<min(64, owner.frames.len):
    let index = owner.sweep
    owner.sweep = (owner.sweep+1) mod owner.frames.len
    if owner.frames[index].kind == FrameKind.Empty or owner.frames[index].closing: continue
    let frame = addr owner.frames[index]
    let stalledRead = now-frame.activity > initDuration(seconds = 30)
    let expiredRead = now-frame.started > initDuration(seconds = 120)
    if not owner.node.active(frame.peer):
      owner.closeFrame(index)
    elif frame.kind == FrameKind.Selecting and now-frame.started > initDuration(seconds = 5):
      owner.closeFrame(index)
    elif frame.kind == FrameKind.Client and frame.handle == NativeStream(nil) and
        not frame.client.ready and now-frame.started > initDuration(seconds = 5):
      owner.closeFrame(index) # Public cancellation also removes a native-delayed open without orphaning its reservation.
    elif frame.kind in [FrameKind.Read, FrameKind.Client] and (stalledRead or expiredRead):
      owner.closeFrame(index) # A cancelled job still retains its host lease until Done/join.
    elif frame.kind == FrameKind.Persistent:
      if not owner.node.announcements(frame.peer) or frame.announcement.failed or
          (not frame.announcement.active and now-frame.started > initDuration(seconds = 5)) or
          (frame.inputBytes > 0 and now-frame.inputStarted > initDuration(seconds = 60)) or
          (frame.outputBytes > 0 and now-frame.outputStarted > initDuration(seconds = 60)):
        owner.closeFrame(index)
  var opened = 0
  for inspected in 0..<min(64, owner.peers.len):
    let index = owner.peerCursor
    owner.peerCursor = (owner.peerCursor+1) mod owner.peers.len
    if not owner.peers[index].used or not owner.node.active(owner.peers[index].peer): continue
    let info = addr owner.peers[index]
    if not owner.node.announcements(info.peer):
      info.queued = false
      continue # Grid-ineligible peers retain read eligibility but cannot occupy UP0 sources.
    if owner.source(info.peer).error != NodeError.None and now-info.connected > initDuration(seconds = 5):
      discard owner.node.disconnect(info.peer)
      info.queued = false
      continue
    if info.peer.initiated and not info.queued and not info.readQueued and owner.frameCount(
        info.peer, FrameKind.Persistent) == 0:
      if owner.node.queueStream(info.peer):
        info.queued = true
        info.queuedAt = now
        info.connected = now
        inc opened
        if opened == 4: break
  var announced = 0
  for inspected in 0..<min(64, owner.frames.len):
    let index = owner.broadcastCursor
    owner.broadcastCursor = (owner.broadcastCursor+1) mod owner.frames.len
    let frame = addr owner.frames[index]
    if frame.kind != FrameKind.Persistent or frame.closing or not frame.announcement.active or
        frame.sentVersion == owner.version or frame.outputBytes != 0: continue
    let needed = uint64(owner.local.body.len)+4
    let announcementLimit = OutputBudget-1048576
    if owner.outputUsed > announcementLimit or needed >
        announcementLimit-owner.outputUsed: continue # Reserve every local handshake independently of header backpressure.
    if frame.announcement.announce(owner.local.body) == AnnouncementError.None:
      frame.sentVersion = owner.version
      owner.accountAnnouncement(index)
      inc announced
      if announced == 4: break
  true
