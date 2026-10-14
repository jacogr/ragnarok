## Small project-maintained LSQUIC adapter. One standard-library selector owns nonblocking UDP and transport deadlines.
## Native callbacks borrow this stack owner synchronously; no futures, callback closures or dependency patches are used.
import std/[nativesockets, selectors, os]
import posix

const BridgeHeader = "../../interoperability/quic/transport_bridge.h"
const CertHeader = "../../interoperability/quic/cert_fields.h"

type
  # Explicit proof profiles keep short test deadlines and load admission separate from normal peer settings.
  Ipv6Profile* = enum
    RetainedPeer = 3, CrashRecovery = 4, SaturatedService = 5
  # Read-only C byte element makes callback signatures match the shared const uint8_t ABI exactly.
  ConstByte* {.importc: "const uint8_t", header: BridgeHeader, pure, final.} = object
  # Opaque LSQUIC stream handle; its lifetime ends at the native close callback.
  NativeStream* = distinct pointer
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
    engine: pointer
    socket: SocketHandle
    socketOpen: bool
    selector: Selector[int]
    registered, selectorOwned, ipv6: bool
    user: pointer
    verify: VerifyCallback
    stream: StreamCallback
    buffer: array[2048, byte]
    stopping, failed: bool

# Nominal handle equality permits slot lookup without exposing transport internals.
proc `==`*(left, right: NativeStream): bool {.borrow.}
# Strict primitive DER extraction; the returned fields own their bounded bytes.
proc parseCert*(der: ptr byte, length: csize_t, fields: ptr CertFields): cint {.importc: "rq_parse_cert",
    header: CertHeader, cdecl, raises: [].}
# Construct the shared native engine/TLS owner; strings are borrowed only during this call.
proc transportNew(soak, server: cint, port: uint16, cert, key, alpn: cstring, user: pointer,
    verify: VerifyCallback, send: SendCallback, stream: StreamCallback): pointer {.importc: "rq_transport_new",
        header: BridgeHeader, cdecl, raises: [].}
# Retain an IPv6 engine across reconnects; the native caller still owns UDP readiness and TLS identity policy.
proc transportNew6(profile, server: cint, port: uint16, cert, key, alpn: cstring, user: pointer,
    verify: VerifyCallback, send: SendCallback, stream: StreamCallback): pointer {.importc: "rq_transport_new_ipv6_profile",
        header: BridgeHeader, cdecl, raises: [].}
# Inspect a live stream's initiator without retaining any connection pointer.
proc nativeLocal(engine: pointer, stream: NativeStream): cint {.importc: "rq_stream_local",
    header: BridgeHeader, cdecl, raises: [].}
# Dial one loopback peer through the retained native engine.
proc nativeConnect(engine: pointer, port: uint16): cint {.importc: "rq_connect",
    header: BridgeHeader, cdecl, raises: [].}
# Queue close while the socket still sends transport packets; callers then poll a short drain interval.
proc nativeDisconnect(engine: pointer) {.importc: "rq_disconnect", header: BridgeHeader, cdecl,
    raises: [].}
# Observe connection lifecycle without retaining a raw native connection pointer.
proc nativeMetric(engine: pointer, metric: cint): uint64 {.importc: "rq_peer_metric",
    header: BridgeHeader, cdecl, raises: [].}
# Consume one borrowed complete UDP datagram synchronously.
proc packetIn(engine: pointer, bytes: ptr byte, length: csize_t,
    port: uint16): cint {.importc: "rq_packet_in", header: BridgeHeader, cdecl, raises: [].}
# Progress LSQUIC callbacks and pending packet writes on the selector thread.
proc process(engine: pointer) {.importc: "rq_process", header: BridgeHeader, cdecl, raises: [].}
# Return the native relative timer deadline in microseconds.
proc nextTick(engine: pointer): int64 {.importc: "rq_next_tick", header: BridgeHeader, cdecl,
    raises: [].}
# Report pending/authenticated/rejected status independently of application success.
proc nativeStatus(engine: pointer): cint {.importc: "rq_status", header: BridgeHeader, cdecl,
    raises: [].}
# Destroy native state synchronously, delivering final stream closes while owners remain alive.
proc transportFree(engine: pointer) {.importc: "rq_transport_free", header: BridgeHeader, cdecl,
    raises: [].}
# Create one bidirectional stream after authentication; application state is assigned by its open callback.
proc nativeOpen(engine: pointer) {.importc: "rq_open_stream", header: BridgeHeader, cdecl, raises: [].}
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

# Build only IPv4 loopback addresses; endpoint scope matches the existing bounded proof.
proc loopback(port: uint16): Sockaddr_in {.raises: [].} =
  result.sin_family = typeof(result.sin_family)(posix.AF_INET)
  result.sin_port = posix.htons(port)
  result.sin_addr.s_addr = posix.htonl(0x7f000001'u32)
  # BSD socket addresses include their byte size; Linux has no sin_len member.
  when defined(macosx): cast[ptr uint8](addr result)[] = uint8(sizeof(result))

# Build family-sized loopback storage for synchronous socket calls; no address pointer escapes.
proc socketAddress(ipv6: bool, port: uint16): Sockaddr_storage {.raises: [].} =
  # IPv6 metadata uses a full 128-bit address; this proof deliberately routes only ::1.
  if ipv6:
    let a = cast[ptr Sockaddr_in6](addr result)
    a.sin6_family = typeof(a.sin6_family)(posix.AF_INET6)
    a.sin6_port = posix.htons(port)
    a.sin6_addr = in6addr_loopback
    when defined(macosx): cast[ptr uint8](a)[] = uint8(sizeof(Sockaddr_in6)) # BSD address length.
  else:
    cast[ptr Sockaddr_in](addr result)[] = loopback(port) # Preserve the IPv4 matrix unchanged.

# Select the OS address extent before a syscall, never the padded storage size.
proc addressSize(ipv6: bool): SockLen {.raises: [].} =
  SockLen(if ipv6: sizeof(Sockaddr_in6) else: sizeof(Sockaddr_in))

# Determine request/reply direction per stream, independently of QUIC connection direction.
proc locallyOpened*(owner: Transport, stream: NativeStream): bool {.raises: [].} =
  nativeLocal(owner.engine, stream) == 1

# Invoke native-language identity policy without retaining a TLS-owned DER pointer.
proc verifyForward(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  let owner = cast[ptr Transport](user)
  # Shutdown cannot start another identity-validation operation.
  if owner.stopping: return 0
  owner.verify(owner.user, der, length)

# Forward synchronous stream events while preserving the peer's distinct owner pointer.
proc streamForward(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  let owner = cast[ptr Transport](user)
  owner.stream(owner.user, stream, event)

# Send C-owned bytes synchronously through nonblocking UDP; no borrowed packet memory escapes this callback.
proc sendPacket(user: pointer, bytes: ptr ConstByte, length: csize_t, port: uint16): cint {.cdecl,
    raises: [].} =
  let owner = cast[ptr Transport](user)
  # Destruction may invoke callbacks after readiness has stopped; never touch a retired socket.
  if owner.stopping or not owner.socketOpen: return 0
  # Transport datagram capacity proves narrowing before the OS call.
  if length > csize_t(owner.buffer.len): owner.failed = true; return 0
  var destination = socketAddress(owner.ipv6, port)
  let sent = posix.sendto(owner.socket, bytes, int(length), 0,
      cast[ptr SockAddr](addr destination), addressSize(owner.ipv6))
  # Only a complete datagram is successful; partial/error sends must not fabricate packet delivery.
  if sent == int(length): return 1
  let error = osLastError()
  # Readiness/interrupt races are retryable; persistent OS failures settle the bounded attempt.
  if sent < 0 and error.int notin [EAGAIN.int, EWOULDBLOCK.int, EINTR.int]: owner.failed = true
  0

# Retire selector/socket before native destruction; synchronous close callbacks still borrow the live peer/adapter.
proc closeTransport*(owner: var Transport) =
  owner.stopping = true
  # A registered descriptor must be removed before its number can be recycled by the OS.
  if owner.registered:
    owner.selector.unregister(owner.socket)
    owner.registered = false
  # Each successfully created selector/socket has exactly one release owner.
  if owner.selector != nil:
    if owner.selectorOwned: owner.selector.close() # Borrowed dispatchers outlive both endpoint retirements.
    owner.selector = nil
  if owner.socketOpen:
    nativesockets.close(owner.socket)
    owner.socketOpen = false
  # Destruction delivers final native stream closes before the owning peer leaves scope.
  if owner.engine != nil:
    transportFree(owner.engine)
    owner.engine = nil

# Create one nonblocking endpoint using only the pinned native library and standard Nim facilities.
proc openTransport*(owner: var Transport, server, soak: bool, port: uint16,
    cert, key, alpn: string, user: pointer, verify: VerifyCallback, stream: StreamCallback,
        multi = false, ipv6 = false, dispatcher: Selector[int] = nil,
            profile = RetainedPeer): bool =
  # Refuse to overwrite live resources; a fully retired stack owner can start another endpoint.
  if owner.engine != nil or owner.socketOpen or owner.selector != nil: return false
  owner = Transport()
  owner.ipv6 = ipv6
  owner.user = user
  owner.verify = verify
  owner.stream = stream
  try:
    owner.socket = createNativeSocket((if ipv6: nativesockets.AF_INET6 else: nativesockets.AF_INET),
        SOCK_DGRAM, IPPROTO_UDP)
    # A failed socket has no descriptor or selector to release.
    if owner.socket == osInvalidSocket: return false
    owner.socketOpen = true
    owner.socket.setBlocking(false)
    var local = socketAddress(ipv6, if server: port else: 0'u16)
    # Bind before announcing readiness; the engine needs the actual ephemeral client port.
    if posix.bindSocket(owner.socket, cast[ptr SockAddr](addr local), addressSize(ipv6)) != 0:
      closeTransport(owner)
      return false
    var size = addressSize(ipv6)
    # Read the assigned endpoint without allocating a networking wrapper object.
    if getsockname(owner.socket, cast[ptr SockAddr](addr local), addr size) != 0:
      closeTransport(owner)
      return false
    owner.selectorOwned = dispatcher == nil
    owner.selector = if owner.selectorOwned: newSelector[int]() else: dispatcher
    owner.selector.registerHandle(owner.socket, {Event.Read}, 0)
    owner.registered = true
    let actualPort = posix.ntohs(if ipv6: cast[ptr Sockaddr_in6](addr local).sin6_port else: cast[
        ptr Sockaddr_in](addr local).sin_port)
    # IPv6 mesh owners retain single-peer engines; legacy IPv4/service modes keep their original limits.
    if ipv6:
      owner.engine = transportNew6(cint(profile), cint(server), actualPort, cert.cstring,
          key.cstring, alpn.cstring, addr owner, verifyForward, sendPacket, streamForward)
    else:
      owner.engine = transportNew((if multi: 2.cint else: cint(soak)), cint(server), actualPort,
          cert.cstring, key.cstring, alpn.cstring, addr owner, verifyForward, sendPacket, streamForward)
    # Failed TLS/native setup must release the already-bound I/O resources as well.
    if owner.engine == nil:
      closeTransport(owner)
      return false
    true
  except CatchableError:
    # Selector/socket setup errors retire every resource created before failure.
    closeTransport(owner)
    false

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

# Drain at most 64 datagrams per ready socket so other endpoints and timers cannot starve.
proc drain(owner: var Transport): bool =
  # Bounded synchronous reads reuse storage until each native packet call returns.
  for packet in 0..<64:
    var source: Sockaddr_storage
    var size = addressSize(owner.ipv6)
    let received = posix.recvfrom(owner.socket, addr owner.buffer[0], owner.buffer.len, 0,
        cast[ptr SockAddr](addr source), addr size)
    # Interrupts retry; would-block retires this readiness notification, other OS errors settle the endpoint.
    if received < 0:
      let error = osLastError()
      if error.int == EINTR.int: continue # No delivered bytes.
      if error.int in [EAGAIN.int, EWOULDBLOCK.int]: break # Ready queue drained.
      owner.failed = true
      return false
    var allowed = false
    var port: uint16
    # Validate family and full loopback address before attributing a source port to the transport.
    if owner.ipv6:
      let a = cast[ptr Sockaddr_in6](addr source)
      allowed = a.sin6_family == typeof(a.sin6_family)(posix.AF_INET6) and IN6_IS_ADDR_LOOPBACK(
          addr a.sin6_addr) != 0
      port = posix.ntohs(a.sin6_port)
    else:
      let a = cast[ptr Sockaddr_in](addr source)
      allowed = a.sin_family == typeof(a.sin_family)(posix.AF_INET) and a.sin_addr.s_addr ==
          posix.htonl(0x7f000001'u32)
      port = posix.ntohs(a.sin_port)
    # Empty or out-of-scope datagrams cannot fabricate native peer activity.
    if received > 0 and allowed:
      discard packetIn(owner.engine, addr owner.buffer[0], csize_t(received), port)
      process(owner.engine)
  not owner.failed

# Progress one timer/readiness cycle for a standalone endpoint.
proc pollTransport*(owner: var Transport, maximumMs = 10): bool =
  # Retired or failed endpoints cannot restart native work.
  if owner.stopping or owner.failed: return false
  let delay = min(clamp(maximumMs, 0, 10), int(clamp((nextTick(owner.engine) + 999) div 1000, 1'i64, 10'i64)))
  var ready: array[1, ReadyKey]
  let count = owner.selector.selectInto(delay, ready)
  # Socket readiness and native deadlines share the same thread.
  if count > 0:
    if Event.Error in ready[0].events: owner.failed = true; return false # Explicit descriptor failure.
    if not drain(owner): return false # Receive failure settles this endpoint.
  process(owner.engine)
  not owner.failed

# One selector dispatches both retained role engines; endpoint stack addresses must remain stable throughout.
proc pollPair*(incoming, outgoing: var Transport): bool =
  # Both sockets must borrow the same live dispatcher; do not silently introduce two blocking loops.
  if incoming.stopping or outgoing.stopping or incoming.failed or outgoing.failed or
      incoming.selector != outgoing.selector: return false
  let delay = int(clamp((min(nextTick(incoming.engine), nextTick(outgoing.engine)) + 999) div 1000,
      1'i64, 10'i64))
  var ready: array[2, ReadyKey]
  let count = incoming.selector.selectInto(delay, ready)
  # Process each ready descriptor once, preserving bounded work for its sibling.
  for index in 0..<count:
    let owner = if ready[index].fd == int(incoming.socket): addr incoming else: addr outgoing
    if Event.Error in ready[index].events: owner.failed = true; return false # Descriptor failure is terminal.
    if not drain(owner[]): return false # A failed receive cannot be hidden by the other engine.
  process(incoming.engine)
  process(outgoing.engine)
  not incoming.failed and not outgoing.failed

# Probe idle/ready descriptor retirement directly on the installed selector backend, with no LSQUIC engine.
proc ioSelfTest*() =
  # Repeated registration/teardown must not retain descriptors or stale readiness into the next owner scope.
  for iteration in 0..<256:
    let socket = createNativeSocket(nativesockets.AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    doAssert socket != osInvalidSocket
    socket.setBlocking(false)
    var local = loopback(0)
    doAssert posix.bindSocket(socket, cast[ptr SockAddr](addr local), SockLen(sizeof(local))) == 0
    var size = SockLen(sizeof(local))
    doAssert getsockname(socket, cast[ptr SockAddr](addr local), addr size) == 0
    let selector = newSelector[int]()
    selector.registerHandle(socket, {Event.Read}, 0)
    var ready: array[1, ReadyKey]
    # Half the cases deliver a datagram before registration retirement; others remain idle.
    if iteration mod 2 == 0:
      var payload = 99'u8
      doAssert posix.sendto(socket, addr payload, 1, 0, cast[ptr SockAddr](addr local), size) == 1
      doAssert selector.selectInto(10, ready) == 1
    selector.unregister(socket)
    nativesockets.close(socket)
    doAssert selector.selectInto(0, ready) == 0
    selector.close()
  echo "Nim I/O selftest: 256 idle/ready UDP registration retirements passed"
