# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable bounded validator connection owner. Canonical topology is copied before callbacks;
## networking owns no complete state graph. Raw streams and peer lifecycle events remain synchronous.
import std/[assertions, monotimes, times]
import ./[admission, topology, identity, endpoints, protocol, alpn, network]
import ../quic/[transport, address, io]
import ../chain/[genesis, provider, parameters]
import ../codec/state/[safrole, consensus]

type
  ConnectionError* {.pure.} = enum ## Failed setup leaves every native owner retired.
    Uninitialized, None, InvalidConfig, InvalidIdentity, InvalidTopology, BackendFailure
  ConnectionKind {.pure.} = enum ## A native slot and outgoing engine index occupy different namespaces.
    Incoming, Outgoing
  ConnectionPhase {.pure.} = enum ## Pending replacement has physical ownership but no second policy lease.
    Empty, Connecting, Pending, Active, Closing
  NodePeer* = object ## Copied facts contain no pointer and are checked against the current native generation.
    kind: ConnectionKind
    position: int
    handle: PeerHandle
    key: StateEdKey
  NodePeerEvent* {.pure.} = enum ## Remote close evidence differs from explicit owner retirement.
    Ready, Closed, Retired
  NodeStreamCallback* = proc(user: pointer, peer: NodePeer, stream: NativeStream,
      event: cint) {.nimcall, raises: [].} ## Borrow streams only synchronously; pending opens cancel on Closed/Retired.
  NodeStreamAdmission* = proc(user: pointer, peer: NodePeer, stream: NativeStream): bool {.nimcall,
      raises: [].}
    ## Inspect quotas before claiming a raw route; do not allocate stream-owned state until the open callback.
  NodePeerCallback* = proc(user: pointer, peer: NodePeer, event: NodePeerEvent) {.nimcall, raises: [].}
    ## Lifecycle callbacks may queue work/request closure, but must not recursively poll or retire the owner.
  ConnectionConfig* = object ## Caller-owned bounded startup input is copied before the first native borrow.
    certificate*, privateKey*, protocol*: string
    binding*: NetworkAddress
    port*: uint16
    builders*, others*: GuestConnectionBudget
    streams*: range[1..16384]
  ConnectionState = object ## One physical connection may await promotion while its older policy owner closes.
    phase: ConnectionPhase
    key: StateEdKey
    builder, announced, wantClose, closeSent: bool
    logical: int
    handle: PeerHandle
    started, closingAt: MonoTime
  Location = object ## Current logical policy slot maps to one exact native owner.
    occupied: bool
    kind: ConnectionKind
    position: int
  Route = object ## Stream close keeps its original peer facts even after connection ownership ends.
    stream: NativeStream
    peer: NodePeer
  Target = object ## Mutable retry clocks own copied address candidates, never pointers into a canonical map.
    key: StateEdKey
    routes: seq[NetworkEndpoint]
    route: int
    missing, nextAttempt: MonoTime
  Dialer = object ## The fixed outer sequence never moves/resizes while native callbacks borrow these addresses.
    owner: nil ptr NodeConnections
    position: int
    transport: Transport
    opened, failed: bool
    connection: ConnectionState
  NodeConnections* = object ## Explicit noncopyable ownership spans the listener, stable dialers and shared selector.
    opened, stopping, localValidator: bool
    failure: ConnectionError
    callbackDepth, timerCursor, dialCursor, openRead, openWrite, openCount: int
    maximum: int
    config: ConnectionConfig
    limits: SafroleStateConfig
    local: StateEdKey
    policy: ValidatorAdmission
    dispatcher: nil Dispatcher
    listener: Transport
    incoming: seq[ConnectionState]
    dialers: seq[Dialer]
    locations: seq[Location]
    routes: seq[Route]
    targets: seq[Target]
    opens: seq[NodePeer]
    now: MonoTime
    user: nil pointer
    streamCallback: nil NodeStreamCallback
    peerCallback: nil NodePeerCallback
    admissionCallback: nil NodeStreamAdmission

const RetryMs = 250
const FallbackMs = 5000
const DialTimeoutMs = 5000
const CloseTimeoutMs = 1000

proc `=copy`(destination: var Dialer, source: Dialer) {.error.}
  ## The enclosing stable-address contract is independent of the child's unavailable copy hooks.
proc `=dup`(source: Dialer): Dialer {.error.}
  ## Native callbacks must never point into a duplicated outgoing owner.
proc `=copy`*(destination: var NodeConnections, source: NodeConnections) {.error.}
  ## Copying would split teardown authority and invalidate every dialer's parent pointer.
proc `=dup`*(source: NodeConnections): NodeConnections {.error.}
  ## Implicit duplication is forbidden along with assignment.
proc `=wasMoved`*(owner: var NodeConnections) {.nodestroy, requires: not owner.opened.} =
  ## Only a fully retired owner may move; all foreign callbacks have ended before fields transfer.
  `=wasMoved`(owner.listener)
  `=wasMoved`(owner.dispatcher)
  `=wasMoved`(owner.config)
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.incoming)
  `=wasMoved`(owner.dialers)
  `=wasMoved`(owner.locations)
  `=wasMoved`(owner.routes)
  `=wasMoved`(owner.targets)
  `=wasMoved`(owner.opens)
  owner.opened = false; owner.stopping = false; owner.localValidator = false
  owner.failure = ConnectionError.Uninitialized
  owner.callbackDepth = 0; owner.timerCursor = 0; owner.dialCursor = 0
  owner.openRead = 0; owner.openWrite = 0; owner.openCount = 0; owner.maximum = 0
  owner.local = default(StateEdKey); owner.limits = default(SafroleStateConfig)
  owner.now = default(MonoTime); owner.user = nil
  owner.streamCallback = nil; owner.peerCallback = nil; owner.admissionCallback = nil
proc `=destroy`*(owner: NodeConnections) =
  ## Explicit close retires C and stream callbacks before their enclosing contexts disappear.
  assert not owner.opened, "NodeConnections must close before callback storage retires"
  `=destroy`(owner.listener)
  `=destroy`(owner.dialers)
  `=destroy`(owner.dispatcher)
  `=destroy`(owner.config)
  `=destroy`(owner.policy)
  `=destroy`(owner.incoming)
  `=destroy`(owner.locations)
  `=destroy`(owner.routes)
  `=destroy`(owner.targets)
  `=destroy`(owner.opens)
func initConnectionConfig*(certificate, privateKey, protocol: string, port = 0'u16,
    binding = default(NetworkAddress), builders: GuestConnectionBudget = 20,
    others: GuestConnectionBudget = 20, streams: range[1..16384] = 4096): ConnectionConfig =
  ## Preserve a compact default startup path; open validates path/domain/profile before resources exist.
  ConnectionConfig(certificate: certificate, privateKey: privateKey, protocol: protocol,
    port: port, binding: binding, builders: builders, others: others, streams: streams)
func `==`*(left, right: NodePeer): bool =
  ## Compare copied channel generations; equality alone never grants current owner authority.
  left.kind == right.kind and left.position == right.position and left.handle == right.handle and
      array[32, byte](left.key) == array[32, byte](right.key)
func initiated*(peer: NodePeer): bool =
  ## Record which side initiated the connection, independently from individual CE stream initiators.
  peer.kind == ConnectionKind.Outgoing
func identity*(peer: NodePeer): StateEdKey =
  ## Copy historical identity facts; current operations must also validate the peer in its owner.
  peer.key
func same(left, right: StateEdKey): bool =
  ## Keep Ed25519 byte identity distinct from metadata and routing candidates.
  array[32, byte](left) == array[32, byte](right)
func state(owner: NodeConnections, kind: ConnectionKind, position: int): ConnectionState =
  ## Internal locations are created only from checked native/pool coordinates.
  if kind == ConnectionKind.Incoming: owner.incoming[position]
  else: owner.dialers[position].connection
proc setState(owner: var NodeConnections, kind: ConnectionKind, position: int,
    value: ConnectionState) =
  ## Replace only fixed fields; no foreign callback retains a pointer into these records.
  if kind == ConnectionKind.Incoming: owner.incoming[position] = value
  else: owner.dialers[position].connection = value
func token(kind: ConnectionKind, position: int, value: ConnectionState): NodePeer =
  ## Bind copied identity facts to the exact native owner/admission generation.
  NodePeer(kind: kind, position: position, key: value.key, handle: value.handle)
func error*(owner: NodeConnections): ConnectionError =
  ## Distinguish requested stop from a fatal listener/dispatcher failure; defaults are uninitialized.
  owner.failure
proc fail(owner: var NodeConnections) =
  ## Fail closed without destroying callback contexts on the active native stack.
  owner.failure = ConnectionError.BackendFailure
  owner.stopping = true
func isOpen*(owner: NodeConnections): bool =
  ## Partial/refused/retired owners never grant network authority.
  owner.opened
func active*(owner: NodeConnections, peer: NodePeer): bool =
  ## Reused slots, pending/closing peers and reopened owners all reject old copied facts.
  if not owner.opened or owner.stopping or peer.position < 0: return false
  if peer.kind == ConnectionKind.Incoming:
    if peer.position >= owner.incoming.len: return false
  elif peer.position >= owner.dialers.len: return false
  let current = state(owner, peer.kind, peer.position)
  current.phase == ConnectionPhase.Active and current.announced and current.handle ==
      peer.handle and same(current.key, peer.key)
func peerCount*(owner: NodeConnections): int =
  ## Count current policy reservations; pending physical replacements own no duplicate reservation.
  owner.policy.count(PeerClass.Validator)+owner.policy.count(PeerClass.Builder)+owner.policy.count(
      PeerClass.Other)
proc announcements*(owner: NodeConnections, peer: NodePeer): bool =
  ## Grid selection uses the accepted gated topology, never a copied capacity class as privilege.
  if not owner.active(peer): return false
  let current = state(owner, peer.kind, peer.position)
  owner.policy.announcements(PeerSlot(uint64(current.logical)))
proc notify(owner: var NodeConnections, peer: NodePeer, event: NodePeerEvent) =
  ## Callers finish record mutation before exposing synchronous application hooks.
  let callback = owner.peerCallback
  let context = owner.user
  if callback != nil and context != nil:
    assert owner.callbackDepth < 64
    inc owner.callbackDepth
    defer: dec owner.callbackDepth
    callback(context, peer, event) # Queue-only public operations prevent recursive engine driving.
proc markClose(owner: var NodeConnections, kind: ConnectionKind, position: int) =
  ## Intent changes eligibility now; actual native closure/release happens outside the callback batch.
  var current = state(owner, kind, position)
  if current.phase == ConnectionPhase.Empty or current.phase == ConnectionPhase.Closing: return
  current.phase = ConnectionPhase.Closing
  current.wantClose = true
  current.closingAt = owner.now
  setState(owner, kind, position, current)
proc disconnect*(owner: var NodeConnections, peer: NodePeer): bool =
  ## Safe in callbacks: mark only, with no recursive native-engine calls.
  if not owner.active(peer): return false
  markClose(owner, peer.kind, peer.position)
  true
proc queueStream*(owner: var NodeConnections, peer: NodePeer): bool =
  ## Queue bounded copied facts. Peer Closed/Retired cancels all caller pending opens for that peer.
  if not owner.active(peer) or owner.openCount >= owner.opens.len: return false
  owner.opens[owner.openWrite] = peer
  owner.openWrite = (owner.openWrite+1) mod owner.opens.len # Nonzero configured stream budget bounds the ring.
  inc owner.openCount
  true
proc findIdentity(owner: NodeConnections, key: StateEdKey): int =
  ## Logical ownership includes closing peers until their native retirement is observed.
  for index in 0..<owner.locations.len:
    let location = owner.locations[index]
    if location.occupied and same(state(owner, location.kind, location.position).key,
        key): return index
  -1
proc pending(owner: NodeConnections, key: StateEdKey): bool =
  ## At most one preferred physical replacement can wait for an old identity's reservation.
  for index in 0..<owner.incoming.len:
    if owner.incoming[index].phase == ConnectionPhase.Pending and same(owner.incoming[index].key,
        key): return true
  for index in 0..<owner.dialers.len:
    if owner.dialers[index].connection.phase == ConnectionPhase.Pending and same(owner.dialers[
        index].connection.key, key): return true
  false
proc reserve(owner: var NodeConnections, kind: ConnectionKind, position: int,
    key: StateEdKey, builder: bool): int =
  ## Reserve a genuinely free logical slot; physical incoming and outgoing coordinates remain separate.
  for index in 0..<owner.locations.len:
    if not owner.locations[index].occupied:
      let admitted = owner.policy.admitAuthenticated(PeerSlot(uint64(index)), key, builder)
      if admitted.error != AdmissionError.None: return -1 # Refusal preserves both ownership tables.
      owner.locations[index] = Location(occupied: true, kind: kind, position: position)
      return index
  -1
proc replacementAllowed(owner: NodeConnections, key: StateEdKey, incoming: bool): bool =
  ## Preference arbitration applies to required validator pairs, not arbitrary builder duplicate claims.
  let topology = owner.policy.topology
  if not topology.contains(owner.local) or not topology.contains(key): return false
  preferredInitiator(owner.local, key) != incoming
proc release(owner: var NodeConnections, kind: ConnectionKind, position: int,
    observed: bool) =
  ## Call only after actual native close or final engine retirement; clear before notifying user code.
  let current = state(owner, kind, position)
  let peer = token(kind, position, current)
  setState(owner, kind, position, default(ConnectionState))
  if current.logical >= 0 and current.announced:
    assert current.logical < owner.locations.len and owner.locations[current.logical].occupied
    assert owner.policy.release(PeerSlot(uint64(current.logical)))
    owner.locations[current.logical] = default(Location)
    notify(owner, peer, if observed: NodePeerEvent.Closed else: NodePeerEvent.Retired)
  for index in 0..<owner.targets.len:
    if same(owner.targets[index].key, current.key):
      owner.targets[index].missing = owner.now
      owner.targets[index].nextAttempt = owner.now+initDuration(milliseconds = RetryMs)
      break # Retry clocks reset when a real connection ends, not when intent changes.
proc promote(owner: var NodeConnections, kind: ConnectionKind, position: int) =
  ## Authenticate/hold/activate one bounded physical peer without releasing its old lease early.
  if owner.stopping: return # A legal stop request from an earlier Ready hook forbids later promotion.
  var current = state(owner, kind, position)
  if current.phase notin [ConnectionPhase.Connecting, ConnectionPhase.Pending]: return
  if kind == ConnectionKind.Outgoing:
    let found = owner.dialers[position].transport.peerAt(0)
    if found.error != PeerError.None: return # TLS has not yet proved the pinned identity.
    current.handle = found.value
    setState(owner, kind, position, current) # Keep authenticated facts before any duplicate/close branch.
  let existing = findIdentity(owner, current.key)
  if existing >= 0:
    let location = owner.locations[existing]
    if location.kind != kind and replacementAllowed(owner, current.key, kind ==
        ConnectionKind.Incoming):
      if current.phase != ConnectionPhase.Pending and pending(owner, current.key):
        markClose(owner, kind, position)
        return # A second replacement cannot consume unbounded physical state.
      current.phase = ConnectionPhase.Pending
      setState(owner, kind, position, current)
      markClose(owner, location.kind, location.position)
    else:
      markClose(owner, kind, position) # Keep an already-owned preferred or same-direction peer.
    return
  let logical = reserve(owner, kind, position, current.key, current.builder)
  if logical < 0:
    markClose(owner, kind, position)
    return # Desired quota failure never fabricates a Ready notification.
  current.phase = ConnectionPhase.Active
  current.logical = logical
  current.announced = true
  setState(owner, kind, position, current)
  notify(owner, token(kind, position, current), NodePeerEvent.Ready)
proc matches(bytes: ptr ConstByte, length: csize_t, expected: string): bool =
  ## Compare negotiated ALPN bytes only within the borrowed complete span.
  if bytes == nil or length != csize_t(expected.len): return false
  let raw = cast[ptr UncheckedArray[byte]](bytes)
  for index in 0..<expected.len:
    if raw[index] != byte(expected[index]): return false
  true
proc incomingVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## TLS proves possession after maintained Ed25519/SAN identity validation.
  cint(validPeer(cast[ptr byte](der), length, []))
proc outgoingVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Each stable dialer pins its copied roster key independently of endpoint metadata.
  let dialer = cast[ptr Dialer](user)
  let expected = array[32, byte](dialer.connection.key)
  cint(validPeer(cast[ptr byte](der), length, expected))
proc incomingAdmit(user: pointer, slot: cuint, der: ptr ConstByte, length: csize_t,
    selected: ptr ConstByte, selectedLength: csize_t): cint {.cdecl, raises: [].} =
  ## Retain at most one preferred replacement while its older physical owner retires.
  let owner = cast[ptr NodeConnections](user)
  if owner.stopping or slot >= cuint(owner.incoming.len): return 0
  let position = int(slot)
  if owner.incoming[position].phase != ConnectionPhase.Empty: return 0
  var fields {.noinit.}: CertFields
  if der == nil or length == 0 or parseCert(cast[ptr byte](der), length, addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32: return 0
  var raw = default(array[32, byte])
  for index in 0..<32: raw[index] = fields.key[index] # Copy from authenticated TLS storage before callback return.
  let key = StateEdKey(raw)
  if same(key, owner.local) or same(key, nullValidator().ed25519): return 0
  let builder = matches(selected, selectedLength, owner.config.protocol & "/builder")
  if not builder and not matches(selected, selectedLength, owner.config.protocol): return 0
  let existing = findIdentity(owner[], key)
  if existing >= 0:
    let location = owner.locations[existing]
    let previous = state(owner[], location.kind, location.position)
    if location.kind != ConnectionKind.Outgoing or previous.phase != ConnectionPhase.Active or
        not replacementAllowed(owner[], key, true) or pending(owner[], key): return 0
    owner.incoming[position] = ConnectionState(phase: ConnectionPhase.Pending,
      key: key, builder: builder, logical: -1, started: owner.now)
    markClose(owner[], location.kind, location.position)
    return 1 # Physical acceptance grants no second policy lease or application stream access.
  if pending(owner[], key): return 0
  let logical = reserve(owner[], ConnectionKind.Incoming, position, key, builder)
  if logical < 0: return 0
  owner.incoming[position] = ConnectionState(phase: ConnectionPhase.Active, key: key,
    builder: builder, logical: logical, started: owner.now)
  1
proc incomingPeer(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  ## Native promotion mints a generation before Ready; actual close alone releases a live reservation.
  let owner = cast[ptr NodeConnections](user)
  if slot >= cuint(owner.incoming.len): fail(owner[]); return
  let position = int(slot)
  if event == PeerAccepted:
    let found = owner.listener.peerAt(position)
    if found.error != PeerError.None: fail(owner[]); return
    var current = owner.incoming[position]
    if current.phase notin [ConnectionPhase.Active, ConnectionPhase.Pending]: fail(owner[]); return
    current.handle = found.value
    if current.phase == ConnectionPhase.Active: current.announced = true
    owner.incoming[position] = current
    if current.announced: notify(owner[], token(ConnectionKind.Incoming, position, current),
        NodePeerEvent.Ready)
  elif event == PeerClosed:
    release(owner[], ConnectionKind.Incoming, position, true)
  else: fail(owner[]) # A changed primitive event contract cannot silently mint authority.
proc dispatch(owner: var NodeConnections, kind: ConnectionKind, position: int,
    stream: NativeStream, event: cint) =
  ## Keep owner-bound stream routes through reset/close, including engine destruction.
  if event == 0:
    if owner.stopping: streamAbort(stream); return
    if kind == ConnectionKind.Outgoing: promote(owner, kind, position)
    let current = state(owner, kind, position)
    let peer = token(kind, position, current)
    if not owner.active(peer): streamAbort(stream); return
    let found = if kind == ConnectionKind.Incoming: owner.listener.streamPeer(stream)
      else: owner.dialers[position].transport.streamPeer(stream)
    if found.error != PeerError.None or not (found.value == current.handle): streamAbort(stream); return
    var free = -1
    for index in 0..<owner.routes.len:
      if owner.routes[index].stream == default(NativeStream): free = index; break
    if free < 0: streamAbort(stream); return # Bounded stream storage applies before application work.
    let admission = owner.admissionCallback
    let context = owner.user
    if admission != nil and context != nil:
      var allowed = false
      block:
        assert owner.callbackDepth < 64
        inc owner.callbackDepth
        defer: dec owner.callbackDepth
        allowed = admission(context, peer, stream) # Inspect only: no route or application byte owner exists yet.
      if not allowed or owner.stopping or not owner.active(peer):
        streamAbort(stream)
        return # Refused streams cannot consume the route capacity reserved for other peers/UP0.
    owner.routes[free] = Route(stream: stream, peer: peer)
  var route = -1
  for index in 0..<owner.routes.len:
    if owner.routes[index].stream == stream: route = index; break
  if route < 0: return # Refused new streams own no application context to retire later.
  let peer = owner.routes[route].peer
  if event == 3: owner.routes[route] = default(Route) # Clear before user code can queue more work.
  let callback = owner.streamCallback
  let context = owner.user
  if callback == nil or context == nil:
    if event == 0: streamAbort(stream)
    return # Disabled applications do not retain unsolicited stream payloads.
  assert owner.callbackDepth < 64
  inc owner.callbackDepth
  defer: dec owner.callbackDepth
  callback(context, peer, stream, event) # No route access follows a callback that may cancel it.
proc incomingStream(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Resolve the current incoming owner once at open; later close uses retained copied route facts.
  let owner = cast[ptr NodeConnections](user)
  if event == 0:
    let found = owner.listener.streamPeer(stream)
    if found.error != PeerError.None: streamAbort(stream); return
    for position in 0..<owner.incoming.len:
      if owner.incoming[position].handle == found.value:
        dispatch(owner[], ConnectionKind.Incoming, position, stream, event)
        return
    streamAbort(stream) # Unknown ownership never falls back to a global current connection.
  else:
    dispatch(owner[], ConnectionKind.Incoming, 0, stream, event) # Existing routes retain exact peer coordinates.
proc outgoingStream(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## The fixed dialer address remains valid until all engine stream-close callbacks finish.
  let dialer = cast[ptr Dialer](user)
  let owner = dialer.owner
  if owner == nil: streamAbort(stream); return
  dispatch(owner[], ConnectionKind.Outgoing, dialer.position, stream, event)
proc dialAddress(endpoint: NetworkEndpoint): NetworkEndpoint =
  ## IPv4-mapped metadata denotes an IPv4 route while retaining the exact normalized16 bytes.
  let bytes = endpoint.address.bytes
  var mapped = bytes[10] == 255 and bytes[11] == 255
  for index in 0..<10:
    if bytes[index] != 0: mapped = false
  if mapped:
    return networkEndpoint(ipv4Address([bytes[12], bytes[13], bytes[14], bytes[15]]), endpoint.port)
  endpoint
proc rebuild(owner: var NodeConnections) =
  ## Build owned bounded candidates current/next/previous, preserving retry clocks by identity only.
  let topology = owner.policy.topology
  var nextKey = default(StateEdKey)
  let preserve = owner.dialCursor >= 0 and owner.dialCursor < owner.targets.len
  if preserve: nextKey = owner.targets[owner.dialCursor].key # Head updates cannot repeatedly starve later candidates.
  var prepared = newSeq[Target](owner.maximum)
  var count = 0
  for epoch in [ValidatorEpoch.Current, ValidatorEpoch.Next, ValidatorEpoch.Previous]:
    for ordinal in 0..<topology.population(epoch):
      let found = topology.membershipAt(epoch, StateValidatorIndex(uint64(ordinal)))
      assert found.error == TopologyError.None
      let member = found.value
      let key = member.identity
      if same(key, owner.local) or same(key, nullValidator().ed25519): continue
      var position = -1
      for index in 0..<count:
        if same(prepared[index].key, key): position = index; break
      if position < 0:
        assert count < owner.maximum # Three codec-bounded rosters fit the derived3V capacity.
        position = count
        inc count
        prepared[position] = Target(key: key, missing: owner.now, nextAttempt: owner.now)
        for old in 0..<owner.targets.len:
          if same(owner.targets[old].key, key):
            prepared[position].missing = owner.targets[old].missing
            prepared[position].nextAttempt = owner.targets[old].nextAttempt
            prepared[position].route = owner.targets[old].route
            break # No mutable route sequence or canonical map is shared with the new projection.
      if member.endpoint.error == EndpointError.None:
        let endpoint = dialAddress(member.endpoint.value)
        var known = false
        for index in 0..<prepared[position].routes.len:
          if prepared[position].routes[index] == endpoint: known = true; break
        if not known: prepared[position].routes.add(
            endpoint) # Total candidates cannot exceed total roster positions.
  prepared.setLen(count)
  var cursor = 0
  if preserve:
    for index in 0..<prepared.len:
      if same(prepared[index].key, nextKey):
        cursor = index
        break # Preserve the next identity, not an obsolete ordinal.
  owner.targets = prepared
  owner.localValidator = topology.contains(owner.local)
  owner.dialCursor = cursor
proc advance*(owner: var NodeConnections, view: ChainView,
    now: StateTime): AdmissionResult[EpochUpdate] {.requires: owner.callbackDepth == 0.} =
  ## Main-loop canonical handoff never runs inside borrowed native callbacks or worker leases.
  if not owner.opened or owner.stopping: return default(AdmissionResult[EpochUpdate])
  let outcome = owner.policy.advance(view, now, owner.limits)
  if outcome.error != AdmissionError.None or outcome.value != EpochUpdate.Applied: return outcome
  rebuild(owner)
  for index in 0..<owner.locations.len:
    let location = owner.locations[index]
    if location.occupied and (owner.policy.retiring(PeerSlot(uint64(index))) or
        (not owner.localValidator and location.kind == ConnectionKind.Outgoing)):
      markClose(owner, location.kind, location.position) # Delay native close until the readiness batch ends.
  outcome
proc retireDialer(owner: var NodeConnections, position: int, observed: bool) =
  ## Final engine destruction completes stream callbacks before its logical lease or stable pool slot reuses.
  owner.dialers[position].transport.closeTransport()
  owner.dialers[position].opened = false
  owner.dialers[position].failed = false
  release(owner, ConnectionKind.Outgoing, position, observed)
proc close*(owner: var NodeConnections) {.requires: owner.callbackDepth == 0.} =
  ## Keep all enclosing callback contexts alive through stream closure and authoritative engine retirement.
  if not owner.opened: return
  owner.stopping = true
  owner.listener.closeTransport()
  for index in 0..<owner.dialers.len:
    owner.dialers[index].transport.closeTransport()
    owner.dialers[index].opened = false # Foreign pointers retire before any surrounding sequence storage.
  for index in 0..<owner.locations.len:
    let location = owner.locations[index]
    if location.occupied: release(owner, location.kind, location.position, false)
  for index in 0..<owner.routes.len:
    assert owner.routes[index].stream == default(NativeStream), "engine retirement must deliver final stream close"
  let dispatcher = owner.dispatcher
  if dispatcher != nil: dispatcher.close() # Every transport has already unregistered its descriptor.
  owner.dispatcher = nil
  owner.openCount = 0
  owner.policy = default(ValidatorAdmission)
  owner.opened = false
proc stop*(owner: var NodeConnections) =
  ## Safe in application callbacks; the outer loop subsequently calls explicit close outside callbacks.
  owner.stopping = true
func stopped*(owner: NodeConnections): bool =
  ## A stopped owner admits no new streams or physical peers.
  owner.stopping
proc localPort*(owner: NodeConnections): uint16 =
  ## Return the actual listener port after successful bind; defaults have no endpoint.
  if not owner.opened: return 0
  owner.listener.localPort
func validPath(path: string): bool =
  ## Bound copied native path storage and reject C-string truncation before any credential lookup.
  if path.len == 0 or path.len > 4096: return false
  for character in path:
    if character == char(0): return false
  true
proc open*(owner: var NodeConnections, config: ConnectionConfig,
    source: BlockSnapshotResult, limits: SafroleStateConfig,
    streamCallback: nil NodeStreamCallback = nil, peerCallback: nil NodePeerCallback = nil,
    user: nil pointer = nil, admissionCallback: nil NodeStreamAdmission = nil): ConnectionError {.requires: owner.callbackDepth == 0.} =
  ## Capture bounded canonical facts, own fixed callback storage and install native admission before IO.
  if owner.opened or not validPath(config.certificate) or not validPath(config.privateKey) or
      int(config.streams) < 1 or int(config.streams) > 16384: return ConnectionError.InvalidConfig
  if user == nil and (streamCallback != nil or peerCallback !=
      nil or admissionCallback != nil): return ConnectionError.InvalidConfig
  let protocols = serverAlpns(config.protocol)
  if protocols.len != 2: return ConnectionError.InvalidConfig
  let selected = captureValidatorTopology(source, limits)
  if selected.error != TopologyError.None: return ConnectionError.InvalidTopology
  let local = certificateIdentity(config.certificate)
  if local.error != CertificateIdentityError.None: return ConnectionError.InvalidIdentity
  let cores = source.value.chainParameters.get(coreCount)
  if cores < 2 or cores > 341: return ConnectionError.InvalidTopology
  let maximum = int(cores*9) # Checked profile proves1..3069 before constrained parameter conversion/allocation.
  let policy = initValidatorAdmission(selected.value, local.value, maximum, config.builders, config.others)
  if policy.error != AdmissionError.None: return ConnectionError.InvalidTopology
  owner = NodeConnections()
  owner.failure = ConnectionError.None
  owner.config = config
  owner.config.protocol = protocols[0] # Validators offer the base domain; acceptors also reserve builder ALPN.
  owner.local = local.value
  owner.policy = policy.value
  owner.limits = limits
  owner.maximum = maximum
  owner.now = getMonoTime()
  owner.user = user
  owner.streamCallback = streamCallback
  owner.peerCallback = peerCallback
  owner.admissionCallback = admissionCallback
  owner.incoming = newSeq[ConnectionState](owner.policy.capacity)
  owner.locations = newSeq[Location](owner.policy.capacity)
  owner.dialers = newSeq[Dialer](maximum)
  owner.routes = newSeq[Route](int(config.streams))
  owner.opens = newSeq[NodePeer](int(config.streams))
  for index in 0..<maximum:
    owner.dialers[index].owner = addr owner
    owner.dialers[index].position = index # Neither this array nor its parent moves while native callbacks exist.
  owner.dispatcher = newDispatcher(maximum+1)
  owner.opened = true # From here every failed setup path uses the same complete retirement routine.
  let dispatcher = owner.dispatcher
  if dispatcher == nil or not owner.listener.openTransport(true, false, config.port,
      config.certificate, config.privateKey, owner.config.protocol, addr owner, incomingVerify,
      incomingStream, multi = true, dispatcher = dispatcher, acceptedAlpns = protocols,
      localAddress = config.binding, incomingPeers = owner.policy.capacity,
      idleSeconds = 30, keepalive = true):
    owner.close()
    return ConnectionError.BackendFailure
  if not owner.listener.admitPeers(incomingAdmit) or not owner.listener.observePeers(incomingPeer):
    owner.close()
    return ConnectionError.BackendFailure
  rebuild(owner)
  ConnectionError.None
proc outgoingExists(owner: NodeConnections, key: StateEdKey): bool =
  ## One physical outgoing slot per identity bounds both unauthenticated work and replacements.
  for index in 0..<owner.dialers.len:
    if owner.dialers[index].opened and same(owner.dialers[index].connection.key, key): return true
  false
proc dial(owner: var NodeConnections, target: int): bool =
  ## Allocate at most one finite engine for this copied endpoint candidate; no canonical alias escapes.
  var position = -1
  for index in 0..<owner.dialers.len:
    if not owner.dialers[index].opened: position = index; break
  if position < 0: return false
  let routes = owner.targets[target].routes.len
  if routes == 0: return false
  let route = owner.targets[target].route mod routes
  let endpoint = owner.targets[target].routes[route]
  let key = owner.targets[target].key
  owner.targets[target].route = (route+1) mod routes # Each failed retry can try the next advertised membership route.
  owner.targets[target].nextAttempt = owner.now+initDuration(milliseconds = RetryMs)
  let binding = dialBinding(owner.config.binding, endpoint.address)
  if not validDial(binding, endpoint.address): return false
  owner.dialers[position].connection = ConnectionState(phase: ConnectionPhase.Connecting,
    key: key, logical: -1, started: owner.now)
  let dispatcher = owner.dispatcher
  if dispatcher == nil or not owner.dialers[position].transport.openTransport(false, false, 0,
      owner.config.certificate, owner.config.privateKey, owner.config.protocol,
      addr owner.dialers[position], outgoingVerify, outgoingStream, dispatcher = dispatcher,
      localAddress = binding, idleSeconds = 30, keepalive = true):
    owner.dialers[position].connection = default(ConnectionState)
    return false # Factory cleanup leaves the stable unused slot available for another target.
  owner.dialers[position].opened = true
  if not owner.dialers[position].transport.connectTransport(endpoint):
    retireDialer(owner, position, false)
    return false
  true
proc driveClose(owner: var NodeConnections, kind: ConnectionKind, position: int) =
  ## Request native close once; physical ownership stays until its observer or final engine retirement.
  var current = state(owner, kind, position)
  if current.phase != ConnectionPhase.Closing or current.closeSent: return
  if kind == ConnectionKind.Incoming:
    discard owner.listener.disconnectPeer(current.handle)
  elif not owner.dialers[position].transport.disconnectPeer(current.handle):
    owner.dialers[position].transport.disconnectTransport() # Pending TLS still owns this sole outgoing connection.
  current.closeSent = true
  setState(owner, kind, position, current)
proc poll*(owner: var NodeConnections, now: MonoTime, maximumMs: range[0..1] = 1): bool
    {.requires: owner.callbackDepth == 0.} =
  ## One bounded event-loop turn; all engine create/retire work follows the current readiness batch.
  if not owner.opened or owner.stopping: return false
  if now < owner.now:
    owner.failure = ConnectionError.InvalidConfig
    owner.stopping = true
    return false # A caller-supplied backwards monotonic clock cannot drive retry arithmetic.
  owner.now = now
  let dispatcher = owner.dispatcher
  if dispatcher == nil: fail(owner); return false
  var ready = default(array[MaxReadyBatch, Ready])
  let count = dispatcher.waitBatch(int(maximumMs), ready)
  if count < 0: fail(owner); return false
  for index in 0..<count:
    if owner.listener.ownsReady(ready[index]):
      if not owner.listener.processReady(ready[index]): fail(owner); return false
    else:
      for position in 0..<owner.dialers.len:
        if owner.dialers[position].opened and owner.dialers[position].transport.ownsReady(ready[index]):
          if not owner.dialers[position].transport.processReady(ready[index]) or
              not owner.dialers[position].transport.processTimers(): owner.dialers[
                  position].failed = true
          break # Matching exact current-turn ownership never feeds one packet to another engine.
  if not owner.listener.processTimers(): fail(owner); return false
  if owner.stopping: return false
  # Rotate a bounded timer slice independently of socket readiness; packet-driven engines progressed above.
  for step in 0..<min(64, owner.dialers.len):
    let position = owner.timerCursor
    owner.timerCursor = (owner.timerCursor+1) mod owner.dialers.len
    if owner.dialers[position].opened and not owner.dialers[position].failed:
      if not owner.dialers[position].transport.processTimers(): owner.dialers[
          position].failed = true
  var retired = 0
  for position in 0..<owner.dialers.len:
    if owner.dialers[position].opened:
      let before = owner.dialers[position].connection
      if before.phase in [ConnectionPhase.Connecting, ConnectionPhase.Pending]:
        promote(owner, ConnectionKind.Outgoing, position)
      let current = owner.dialers[position].connection
      if current.phase == ConnectionPhase.Connecting and
          (owner.now-current.started).inMilliseconds >= DialTimeoutMs:
        markClose(owner, ConnectionKind.Outgoing, position)
      driveClose(owner, ConnectionKind.Outgoing, position)
      let closing = owner.dialers[position].connection
      let observed = closedConnections(owner.dialers[position].transport) > 0
      let expired = closing.phase == ConnectionPhase.Closing and
        (owner.now-closing.closingAt).inMilliseconds >= CloseTimeoutMs
      if retired < 4 and (owner.dialers[position].failed or observed or expired):
        retireDialer(owner, position, observed)
        inc retired # Engine retirement has an explicit per-turn quota after readiness references expire.
  for position in 0..<owner.incoming.len:
    if owner.incoming[position].phase == ConnectionPhase.Pending:
      promote(owner, ConnectionKind.Incoming, position)
    driveClose(owner, ConnectionKind.Incoming, position)
  if owner.stopping: return false
  # Queue-only application hooks cannot recursively call make_stream; each turn starts at most four requests.
  for step in 0..<min(4, owner.openCount):
    let peer = owner.opens[owner.openRead]
    owner.opens[owner.openRead] = default(NodePeer)
    owner.openRead = (owner.openRead+1) mod owner.opens.len
    dec owner.openCount
    if owner.active(peer):
      let requested = if peer.kind == ConnectionKind.Incoming:
        owner.listener.openPeerStream(peer.handle)
        else: owner.dialers[peer.position].transport.openPeerStream(peer.handle)
      if not requested: markClose(owner, peer.kind,
          peer.position) # Closure cancels all caller pending requests for this peer.
  if not owner.stopping and owner.localValidator and owner.targets.len > 0:
    var started = 0
    for scanned in 0..<owner.targets.len:
      if started == 2: break # TLS setup is bounded independently of UDP packet work.
      let target = owner.dialCursor
      owner.dialCursor = (owner.dialCursor+1) mod owner.targets.len
      let key = owner.targets[target].key
      if owner.targets[target].routes.len == 0 or owner.now < owner.targets[target].nextAttempt or
          findIdentity(owner, key) >= 0 or pending(owner, key) or outgoingExists(owner, key): continue
      if not preferredInitiator(owner.local, key) and
          (owner.now-owner.targets[target].missing).inMilliseconds < FallbackMs: continue
      discard dial(owner, target)
      inc started # Failed route/factory attempts also consume this turn's finite setup budget.
  not owner.stopping
