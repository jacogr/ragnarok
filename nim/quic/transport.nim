## Small project-maintained LSQUIC adapter. One standard-library selector owns nonblocking UDP and transport deadlines.
## Native callbacks borrow this stack owner synchronously; no futures, callback closures or dependency patches are used.
import std/[nativesockets, selectors, os]
import posix

const BridgeHeader = "../../interoperability/quic/transport_bridge.h"
const CertHeader = "../../interoperability/quic/cert_fields.h"

type
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
  # A single endpoint owns socket, selector and native engine; it has no ARC references back to its peer.
  Transport* = object
    engine: pointer
    socket: SocketHandle
    socketOpen: bool
    selector: Selector[int]
    registered: bool
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
# Dial one loopback peer through the retained native engine.
proc nativeConnect(engine: pointer, port: uint16): cint {.importc: "rq_connect",
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
# Half-close writing while keeping response reads available.
proc streamFin*(stream: NativeStream) {.importc: "rq_stream_fin", header: BridgeHeader, cdecl,
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
  var destination = loopback(port)
  let sent = posix.sendto(owner.socket, bytes, int(length), 0,
      cast[ptr SockAddr](addr destination), SockLen(sizeof(destination)))
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
    owner.selector.close()
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
    cert, key, alpn: string, user: pointer, verify: VerifyCallback, stream: StreamCallback): bool =
  # Refuse to overwrite live resources; a fully retired stack owner can start another endpoint.
  if owner.engine != nil or owner.socketOpen or owner.selector != nil: return false
  owner = Transport()
  owner.user = user
  owner.verify = verify
  owner.stream = stream
  try:
    owner.socket = createNativeSocket(nativesockets.AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    # A failed socket has no descriptor or selector to release.
    if owner.socket == osInvalidSocket: return false
    owner.socketOpen = true
    owner.socket.setBlocking(false)
    var local = loopback(if server: port else: 0'u16)
    # Bind before announcing readiness; the engine needs the actual ephemeral client port.
    if posix.bindSocket(owner.socket, cast[ptr SockAddr](addr local), SockLen(sizeof(local))) != 0:
      closeTransport(owner)
      return false
    var size = SockLen(sizeof(local))
    # Read the assigned endpoint without allocating a networking wrapper object.
    if getsockname(owner.socket, cast[ptr SockAddr](addr local), addr size) != 0:
      closeTransport(owner)
      return false
    owner.selector = newSelector[int]()
    owner.selector.registerHandle(owner.socket, {Event.Read}, 0)
    owner.registered = true
    owner.engine = transportNew(cint(soak), cint(server), posix.ntohs(local.sin_port), cert.cstring,
        key.cstring, alpn.cstring, addr owner, verifyForward, sendPacket, streamForward)
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

# Progress one timer/readiness cycle; receive buffers and callback owners stay alive through all native calls.
proc pollTransport*(owner: var Transport, maximumMs = 10): bool =
  # Closed or failed endpoints cannot restart readiness or native processing.
  if owner.stopping or owner.failed: return false
  let delay = min(clamp(maximumMs, 0, 10), int(clamp((nextTick(owner.engine) + 999) div 1000, 1'i64, 10'i64)))
  var ready: array[1, ReadyKey]
  let count = owner.selector.selectInto(delay, ready)
  # Read all currently available datagrams with bounded synchronous syscalls, then service native timers.
  if count > 0:
    # Selector errors settle the endpoint instead of spinning on an invalid descriptor.
    if Event.Error in ready[0].events: owner.failed = true; return false
    # Bound datagram work so a continuously readable socket cannot starve lifecycle/transport deadlines.
    for packet in 0..<64:
      var source: Sockaddr_in
      var size = SockLen(sizeof(source))
      let received = posix.recvfrom(owner.socket, addr owner.buffer[0], owner.buffer.len, 0,
          cast[ptr SockAddr](addr source), addr size)
      # Would-block ends this drain; interruptions retry without retaining another operation owner.
      if received < 0:
        let error = osLastError()
        if error.int == EINTR.int: continue # Interrupted reads have no delivered bytes.
        if error.int in [EAGAIN.int, EWOULDBLOCK.int]: break # The readiness queue is drained.
        owner.failed = true
        return false
      # Only nonempty datagrams from the proof's loopback address enter LSQUIC.
      if received > 0 and source.sin_addr.s_addr == posix.htonl(0x7f000001'u32):
        discard packetIn(owner.engine, addr owner.buffer[0], csize_t(received), posix.ntohs(
            source.sin_port))
        process(owner.engine)
  process(owner.engine)
  not owner.failed

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
