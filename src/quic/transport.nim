## Maintained LSQUIC adapter. One bounded POSIX dispatcher services nonblocking UDP and deadlines.
## Native callbacks borrow this stack owner synchronously; no futures, callback closures or dependency patches are used.
import std/assertions
import ./io
export io.newDispatcher, io.close

const BridgeHeader = "transport_bridge.h"
const CertHeader = "cert_fields.h"

type
  # Explicit proof profiles keep short test deadlines and load admission separate from normal peer settings.
  Ipv6Profile* = enum
    RetainedPeer = 3, CrashRecovery = 4, SaturatedService = 5
  # Read-only C byte element makes callback signatures match the shared const uint8_t ABI exactly.
  ConstByte* {.importc: "const uint8_t", header: BridgeHeader, pure, final.} = object
  # Opaque LSQUIC stream handle; its lifetime ends at the native close callback.
  NativeStream* = distinct (nil pointer)
  # Certificate observations copy bounded primitive fields; JAM identity policy stays in the peer.
  CertFields* {.importc: "rq_cert_fields", header: CertHeader, bycopy.} = object
    edKey* {.importc: "ed_key".}, edSignature* {.importc: "ed_signature".}: cint
    sanExtensions* {.importc: "san_extensions".}, sanCount * {.importc: "san_count".},
        sanDns* {.importc: "san_dns".}: cint
    keyLength* {.importc: "public_key_length".}, sanLength * {.importc: "san_length".}: csize_t
    key* {.importc: "public_key".}: array[32, byte]
    san*: array[256, byte]
  # Borrow DER only during synchronous verification; never retain the TLS-owned pointer.
  VerifyCallback* = proc(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl,
      raises: [].}
  # Stream events execute synchronously inside transport processing/destruction, with the peer owner still alive.
  StreamCallback* = proc(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].}
  # The UDP sender consumes a borrowed C packet before returning; zero means retry later.
  SendCallback = proc(user: pointer, bytes: ptr ConstByte, length: csize_t,
      port: uint16): cint {.cdecl, raises: [].}
  # An endpoint owns UDP/engine and owns or borrows its selector; it has no ARC reference back to its peer.
  Transport* = object
    engine: nil pointer
    socket: UdpEndpoint
    selector: nil Dispatcher
    registered, selectorOwned, ipv6: bool
    user: nil pointer
    verify: nil VerifyCallback
    stream: nil StreamCallback
    buffer: array[2048, byte]
    stopping, failed: bool

# Nominal handle equality permits slot lookup without exposing transport internals.
proc `==`*(left, right: NativeStream): bool {.borrow.}
# Strict primitive DER extraction; the returned fields own their bounded bytes.
proc parseCert*(der: ptr byte, length: csize_t, fields: ptr CertFields): cint {.importc: "rq_parse_cert",
    header: CertHeader, cdecl, raises: [].}
# Construct the shared native engine/TLS owner; strings are borrowed only during this call.
proc transportNew(soak, server: cint, port: uint16, cert, key, alpn: cstring, user: pointer,
    verify: VerifyCallback, send: SendCallback, stream: StreamCallback): nil pointer {.importc: "rq_transport_new",
        header: BridgeHeader, cdecl, raises: [].}
# Retain an IPv6 engine across reconnects; the native caller still owns UDP readiness and TLS identity policy.
proc transportNew6(profile, server: cint, port: uint16, cert, key, alpn: cstring, user: pointer,
    verify: VerifyCallback, send: SendCallback, stream: StreamCallback): nil pointer {.importc: "rq_transport_new_ipv6_profile",
        header: BridgeHeader, cdecl, raises: [].}
# Inspect a live stream's initiator without retaining any connection pointer.
proc nativeLocal(engine: nil pointer, stream: NativeStream): cint {.importc: "rq_stream_local",
    header: BridgeHeader, cdecl, raises: [].}
# Dial one loopback peer through the retained native engine.
proc nativeConnect(engine: nil pointer, port: uint16): cint {.importc: "rq_connect",
    header: BridgeHeader, cdecl, raises: [].}
# Queue close while the socket still sends transport packets; callers then poll a short drain interval.
proc nativeDisconnect(engine: nil pointer) {.importc: "rq_disconnect", header: BridgeHeader, cdecl,
    raises: [].}
# Observe connection lifecycle without retaining a raw native connection pointer.
proc nativeMetric(engine: nil pointer, metric: cint): uint64 {.importc: "rq_peer_metric",
    header: BridgeHeader, cdecl, raises: [].}
# Consume one borrowed complete UDP datagram synchronously.
proc packetIn(engine: nil pointer, bytes: ptr byte, length: csize_t,
    port: uint16): cint {.importc: "rq_packet_in", header: BridgeHeader, cdecl, raises: [].}
# Progress LSQUIC callbacks and pending packet writes on the selector thread.
proc process(engine: nil pointer) {.importc: "rq_process", header: BridgeHeader, cdecl, raises: [].}
# Return the native relative timer deadline in microseconds.
proc nextTick(engine: nil pointer): int64 {.importc: "rq_next_tick", header: BridgeHeader, cdecl,
    raises: [].}
# Report pending/authenticated/rejected status independently of application success.
proc nativeStatus(engine: nil pointer): cint {.importc: "rq_status", header: BridgeHeader, cdecl,
    raises: [].}
# Destroy native state synchronously, delivering final stream closes while owners remain alive.
proc transportFree(engine: nil pointer) {.importc: "rq_transport_free", header: BridgeHeader, cdecl,
    raises: [].}
# Create one bidirectional stream after authentication; application state is assigned by its open callback.
proc nativeOpen(engine: nil pointer) {.importc: "rq_open_stream", header: BridgeHeader, cdecl,
    raises: [].}
# Read accepted stream bytes; -2 is would-block, zero is FIN and other negative values are transport errors.
proc streamRead*(stream: NativeStream, bytes: ptr byte,
    length: csize_t): int64 {.importc: "rq_stream_read", header: BridgeHeader, cdecl, raises: [].}
# Write borrowed bytes synchronously; accepted bytes are copied into native transport storage.
proc streamWrite*(stream: NativeStream, bytes: ptr byte,
    length: csize_t): int64 {.importc: "rq_stream_write", header: BridgeHeader, cdecl, raises: [].}
# Subscribe or unsubscribe to readable stream callbacks without creating an I/O task.
proc wantRead*(stream: NativeStream, want: cint) {.importc: "rq_stream_want_read",
    header: BridgeHeader, cdecl, raises: [].}
# Subscribe only while an owned application write has unsent bytes.
proc wantWrite*(stream: NativeStream, want: cint) {.importc: "rq_stream_want_write",
    header: BridgeHeader, cdecl, raises: [].}
# Flush accepted bytes independently of application FIN.
proc streamFlush*(stream: NativeStream): cint {.importc: "rq_stream_flush", header: BridgeHeader,
    cdecl, raises: [].}
# Compare live stream owners synchronously, proving isolation across different connections without borrowing a connection handle.
proc samePeer*(a, b: NativeStream): cint {.importc: "rq_stream_same_peer", header: BridgeHeader,
    cdecl, raises: [].}
# Half-close writing while keeping response reads available.
proc streamFin*(stream: NativeStream) {.importc: "rq_stream_fin", header: BridgeHeader, cdecl,
    raises: [].}
# Finish validated reading explicitly; LSQUIC EOF alone does not retire its application read owner.
proc readDone*(stream: NativeStream) {.importc: "rq_stream_read_done", header: BridgeHeader, cdecl,
    raises: [].}
# Abort the affected stream; release its application buffers only when native close is delivered.
proc streamAbort*(stream: NativeStream) {.importc: "rq_stream_abort", header: BridgeHeader, cdecl,
    raises: [].}

# Determine request/reply direction per stream, independently of QUIC connection direction.
proc locallyOpened*(owner: Transport, stream: NativeStream): bool {.raises: [].} =
  nativeLocal(owner.engine, stream) == 1

# Invoke native-language identity policy without retaining a TLS-owned DER pointer.
proc verifyForward(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  let owner = cast[ptr Transport](user)
  # Shutdown cannot start another identity-validation operation.
  if owner.stopping: return 0
  let verify = owner.verify
  let peer = owner.user
  if verify == nil or peer == nil: return 0 # Default/retired owners have no identity operation.
  verify(peer, der, length)

# Forward synchronous stream events while preserving the peer's distinct owner pointer.
proc streamForward(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  let owner = cast[ptr Transport](user)
  let callback = owner.stream
  let peer = owner.user
  if callback != nil and peer != nil: callback(peer, stream, event) # Only initialized peer owners receive events.

# Send C-owned bytes synchronously through nonblocking UDP; no borrowed packet memory escapes this callback.
proc sendPacket(user: pointer, bytes: ptr ConstByte, length: csize_t, port: uint16): cint {.cdecl,
    raises: [].} =
  let owner = cast[ptr Transport](user)
  # Destruction callbacks cannot touch a retired endpoint or retain packet memory.
  if owner.stopping or not owner.socket.isOpen: return 0
  # Validate narrowing before passing the C-owned buffer to the synchronous OS adapter.
  if length > csize_t(owner.buffer.len): owner.failed = true; return 0
  let sent = owner.socket.send(cast[pointer](bytes), int(length), port)
  if sent == int(length): return 1 # Only a complete datagram counts as delivered.
  if sent == -1: owner.failed = true # Would-block/interrupt remains retryable.
  0

# Retire selector/socket before native destruction; synchronous close callbacks still borrow the live peer/adapter.
proc closeTransport*(owner: var Transport) =
  owner.stopping = true
  # A registered descriptor must be removed before its number can be recycled by the OS.
  if owner.registered:
    let dispatcher = owner.selector
    if dispatcher != nil: dispatcher.unregister(owner.socket) # Registration retires before descriptor close.
    owner.registered = false
  # Each successfully created selector/socket has exactly one release owner.
  if owner.selector != nil:
    let dispatcher = owner.selector
    if dispatcher != nil and owner.selectorOwned: dispatcher.close() # Borrowed dispatchers outlive endpoint retirement.
    owner.selector = nil
  owner.socket.close() # Idempotent close follows readiness retirement.
  # Destruction delivers final native stream closes before the owning peer leaves scope.
  if owner.engine != nil:
    transportFree(owner.engine)
    owner.engine = nil

# Create one nonblocking endpoint using only the pinned native library and standard Nim facilities.
proc openTransport*(owner: var Transport, server, soak: bool, port: uint16,
    cert, key, alpn: string, user: pointer, verify: VerifyCallback, stream: StreamCallback,
        multi = false, ipv6 = false, dispatcher: nil Dispatcher = nil,
            profile = RetainedPeer): bool =
  # Refuse to overwrite live resources; a fully retired stack owner can start another endpoint.
  if owner.engine != nil or owner.socket.isOpen or owner.selector != nil: return false
  owner = Transport()
  owner.ipv6 = ipv6
  owner.user = user
  owner.verify = verify
  owner.stream = stream
  # Each setup failure has one owner for endpoint and dispatcher retirement.
  if not owner.socket.open(ipv6, if server: port else: 0'u16): return false
  owner.selectorOwned = dispatcher == nil
  owner.selector = if dispatcher == nil: newDispatcher() else: dispatcher
  let active = owner.selector
  if active == nil or not active.register(owner.socket):
    closeTransport(owner)
    return false
  owner.registered = true
  let actualPort = owner.socket.port
  # Keep terminating-zero string storage alive until synchronous native setup returns.
  var certText = cert
  var keyText = key
  var alpnText = alpn
  let certPointer = certText.toCString()
  let keyPointer = keyText.toCString()
  let alpnPointer = alpnText.toCString()
  # IPv6 mesh owners retain single-peer engines; legacy IPv4/service modes keep their original limits.
  if ipv6:
    owner.engine = transportNew6(cint(profile), cint(server), actualPort, certPointer,
        keyPointer, alpnPointer, addr owner, verifyForward, sendPacket, streamForward)
  else:
    owner.engine = transportNew((if multi: 2.cint else: cint(soak)), cint(server), actualPort,
        certPointer, keyPointer, alpnPointer, addr owner, verifyForward, sendPacket, streamForward)
  # Failed TLS/native setup must release the already-bound I/O resources as well.
  if owner.engine == nil:
    closeTransport(owner)
    return false
  true

# Report failure without dereferencing an uninitialized engine.
proc transportStatus*(owner: Transport): int {.raises: [].} =
  # Native authentication status is meaningful only while this owner is active.
  if owner.failed or owner.engine == nil: return -1
  int(nativeStatus(owner.engine))

# Start one outgoing connection after the caller has retained expected identity bytes.
proc connectTransport*(owner: var Transport, port: uint16): bool {.raises: [].} =
  nativeConnect(owner.engine, port) != 0

# Open a bidirectional stream; callbacks populate native-language framing state synchronously.
proc openStream*(owner: var Transport) {.raises: [].} =
  nativeOpen(owner.engine)

# Close the sole dialed peer without destroying this endpoint or its readiness owner.
proc disconnectTransport*(owner: var Transport) {.raises: [].} =
  nativeDisconnect(owner.engine)

# Copy bounded endpoint counters; no native handle or TLS storage escapes this observation.
proc peerMetric*(owner: Transport, metric: int): uint64 {.raises: [].} =
  nativeMetric(owner.engine, cint(metric))

# Lifetime close callbacks, including unsuccessful attempts; pair with authentication evidence for telemetry.
proc closedConnections*(owner: Transport): uint64 {.raises: [].} =
  peerMetric(owner, 2) # rq_peer_metric selector 2: retired connection handles.

# Lifetime successful native handshakes; retained even if a connection closes in the same poll.
proc authenticatedConnections*(owner: Transport): uint64 {.raises: [].} =
  peerMetric(owner, 4) # rq_peer_metric selector 4: completed authentication.

# Drain at most 64 datagrams per ready socket so other endpoints and timers cannot starve.
proc drain(owner: var Transport): bool =
  # Bounded synchronous reads reuse storage until each native packet call returns.
  for packet in 0..<64:
    var port: uint16 = 0
    let received = owner.socket.receive(owner.buffer, port)
    # Retryable races yield to the next bounded dispatcher/timer iteration.
    if received == -2: break
    if received < 0:
      owner.failed = true
      return false
    # Empty or out-of-scope datagrams cannot fabricate native peer activity.
    if received > 0:
      discard packetIn(owner.engine, addr owner.buffer[0], csize_t(received), port)
      process(owner.engine)
  not owner.failed

# Progress one timer/readiness cycle for a standalone endpoint.
proc pollTransport*(owner: var Transport, maximumMs = 10): bool =
  # Retired or failed endpoints cannot restart native work.
  if owner.stopping or owner.failed or owner.engine == nil: return false
  let delay = min(clamp(maximumMs, 0, 10), int(clamp((nextTick(owner.engine) + 999) div 1000, 1'i64, 10'i64)))
  let dispatcher = owner.selector
  if dispatcher == nil: return false # Retired/uninitialized dispatchers own no wait.
  var ready = default(array[2, Ready])
  let count = dispatcher.wait(delay, ready)
  if count < 0: owner.failed = true; return false # OS/dispatcher failure is explicit.
  # Socket readiness and native deadlines share the same thread.
  if count > 0:
    if ready[0].failed: owner.failed = true; return false # Explicit descriptor failure.
    if not drain(owner): return false # Receive failure settles this endpoint.
  process(owner.engine)
  not owner.failed

# One selector dispatches both retained role engines; endpoint stack addresses must remain stable throughout.
proc pollPair*(incoming, outgoing: var Transport): bool =
  # Both sockets must borrow the same live dispatcher; do not silently introduce two blocking loops.
  if incoming.stopping or outgoing.stopping or incoming.failed or outgoing.failed or
      incoming.engine == nil or outgoing.engine == nil or
      incoming.selector != outgoing.selector: return false
  let delay = int(clamp((min(nextTick(incoming.engine), nextTick(outgoing.engine)) + 999) div 1000,
      1'i64, 10'i64))
  let dispatcher = incoming.selector
  if dispatcher == nil: return false # A shared wait requires live metadata.
  var ready = default(array[2, Ready])
  let count = dispatcher.wait(delay, ready)
  if count < 0: incoming.failed = true; outgoing.failed = true; return false # Both owners stop on wait failure.
  # Process each ready descriptor once, preserving bounded work for its sibling.
  for index in 0..<count:
    let owner = if ready[index].descriptor == incoming.socket.descriptor: addr incoming else: addr outgoing
    if ready[index].failed: owner.failed = true; return false # Descriptor failure is terminal.
    if not drain(owner[]): return false # A failed receive cannot be hidden by the other engine.
  process(incoming.engine)
  process(outgoing.engine)
  not incoming.failed and not outgoing.failed

# Replay readiness retirement without TLS/native callbacks; the isolated suite adds IPv6/shared cases.
proc ioSelfTest*() =
  io.retirementSelfTest(false)

# Copy the actual bound UDP port for local telemetry; no socket ownership escapes.
proc localPort*(owner: Transport): uint16 = owner.socket.port
