# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded optional TCP exporter. One owner, no threads, DNS, blocking connect or retained callbacks.
import std/[strutils, oserrors, nativesocket]
import std/posix/posix
import ./wire

type
  # Opaque native address bytes are filled only by inet_pton; no Nim array layout crosses the ABI.
  In6Address {.importc: "struct in6_addr", header: "<netinet/in.h>", bycopy.} = object
  # Public POSIX IPv6 ABI missing from the pinned standard library; C owns layout and sizeof.
  # Zero initialization also clears flow information and the unsupported scope identifier.
  Sockaddr_in6 {.importc: "struct sockaddr_in6", header: "<netinet/in.h>", bycopy.} = object
    sin6_family: TSa_Family
    sin6_port: uint16
    sin6_addr: In6Address
    when defined(macosx):
      # Darwin includes a sockaddr length byte; Linux has no such member.
      sin6_len: uint8
  # Stack-local readiness entry is borrowed only for one zero-timeout poll.
  PollEntry {.importc: "struct pollfd", header: "<poll.h>", bycopy.} = object
    fd: cint
    events, revents: cshort
  # Fixed storage bounds memory regardless of collector speed; copies would duplicate the descriptor.
  Client* = object
    enabled, opened, connecting: bool
    fd: cint
    address: Sockaddr_in
    address6: Sockaddr_in6
    ipv6: bool
    metadata: Metadata
    buffer: array[2048, byte]
    length, offset: int
    retryAt, deadline, statusAt: int64
    nextEvent, lost: uint64
    firstLost, lastLost: Timestamp

# OS interfaces borrow stack addresses and buffers synchronously, including failed calls.
proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
# Connect returns immediately because the descriptor is made nonblocking before use.
proc connectSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
# Readiness never waits and reports connection completion through SO_ERROR below.
proc poll(entries: ptr PollEntry, count: culong, timeout: cint): cint {.importc: "poll",
    header: "<poll.h>".}
# Send copies at most the fixed queued frame prefix into the kernel.
proc sendBytes(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
# Socket option calls expose only fixed scalar option storage.
proc getOption(fd, level, option: cint, value: pointer,
    size: ptr SockLen): cint {.importc: "getsockopt", header: "<sys/socket.h>".}
# Disable SIGPIPE per socket on BSD so a dead collector cannot terminate the peer.
proc setOption(fd, level, option: cint, value: pointer,
    size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
# Parse numeric IP literals only; no DNS work occurs on the peer dispatcher.
proc parseAddress(family: cint, text: cstring, output: pointer): cint {.importc: "inet_pton",
    header: "<arpa/inet.h>".}
# Ports are converted independently of host byte order.
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}

let
  Writable {.importc: "POLLOUT", header: "<poll.h>".}: cshort
  PollError {.importc: "POLLERR", header: "<poll.h>".}: cshort
  Hangup {.importc: "POLLHUP", header: "<poll.h>".}: cshort
  Invalid {.importc: "POLLNVAL", header: "<poll.h>".}: cshort
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
  SocketError {.importc: "SO_ERROR", header: "<sys/socket.h>".}: cint
when defined(macosx):
  # BSD uses a socket option instead of a per-send flag.
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint
else:
  # Linux suppresses SIGPIPE on each send without changing process-wide signal handlers.
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint

# Native ownership may move but must never copy a live socket descriptor.
proc `=copy`*(destination: var Client, source: Client) {.error: "Telemetry Client owns one descriptor".}
# Destruction releases the sole native resource, including exception and early-return paths.
proc `=destroy`*(client: Client) =
  # Default and explicitly closed clients do not own descriptor zero.
  if client.opened: discard posix.close(client.fd)

# Close is idempotent and disables subsequent retries; pending telemetry is best effort on shutdown.
proc close*(client: var Client) =
  # Do not retry close after EINTR because the descriptor could already have been recycled.
  if client.opened: discard posix.close(client.fd)
  client.opened = false
  client.enabled = false
  client.length = 0
  client.offset = 0

# Configure once before ticking. Unsupported endpoints and metadata fail without opening any socket.
proc configure*(client: var Client, endpoint: string, metadata: Metadata): bool =
  # Reconfiguration could replace native ownership or a partially sent frame.
  if client.enabled or client.opened or metadata.coreCount == 0: return false
  # IPv6 mixed notation needs at most 45 host bytes, brackets, colon and five port digits.
  if endpoint.len == 0 or endpoint.len > 53 or '\0' in endpoint: return false
  let ipv6 = endpoint[0] == '['
  var host = ""
  var portText = ""
  if ipv6:
    # Brackets make the port separator unambiguous; scope IDs are deliberately unsupported.
    let closing = endpoint.find(']')
    if closing < 2 or closing + 2 >= endpoint.len or endpoint[closing + 1] != ':': return false
    host = endpoint[1..<closing]
    portText = endpoint[closing + 2..^1]
  else:
    # Keep the existing IPv4/localhost syntax strict; bare IPv6 is ambiguous.
    let parts = endpoint.split(':')
    if parts.len != 2: return false
    host = if parts[0] == "localhost": "127.0.0.1" else: parts[0]
    portText = parts[1]
  if portText.len == 0 or portText.len > 5: return false # Bound arithmetic before decimal parsing.
  var port = 0
  # Decimal parsing rejects signs, whitespace and overflowing values before narrowing.
  for character in portText:
    if character < '0' or character > '9': return false # Port syntax is strictly decimal.
    port = port * 10 + ord(character) - ord('0')
  if port < 1 or port > 65535: return false # Zero is not a remote collector endpoint.
  var address = default(Sockaddr_in)
  var address6 = default(Sockaddr_in6)
  let hostPointer = host.toCString()
  if ipv6:
    # Native parsing rejects malformed literals, zones and bracketed IPv4 without DNS.
    if host.len > 45 or '%' in host or parseAddress(cint(ord(nativesocket.AF_INET6)), hostPointer,
        addr address6.sin6_addr) != 1: return false
    address6.sin6_family = TSa_Family(ord(nativesocket.AF_INET6))
    address6.sin6_port = networkPort(uint16(port))
    when defined(macosx):
      # BSD requires the native sockaddr byte extent as well as its family.
      address6.sin6_len = uint8(sizeof(Sockaddr_in6))
  else:
    # Preserve numeric IPv4 validation and its smaller native address representation.
    if host.len == 0 or host.len > 15 or parseAddress(cint(ord(nativesocket.AF_INET)),
        hostPointer, addr address.sin_addr) != 1: return false
    address.sin_family = TSa_Family(ord(nativesocket.AF_INET))
    address.sin_port = networkPort(uint16(port))
    when defined(macosx):
      # BSD requires the native sockaddr byte extent as well as its family.
      address.sin_len = uint8(sizeof(Sockaddr_in))
  client.address = address
  client.address6 = address6
  client.ipv6 = ipv6
  client.metadata = metadata
  client.retryAt = 0
  client.statusAt = 0
  client.lost = 0
  client.nextEvent = 0
  client.connecting = false
  client.enabled = true
  true

# Retire a failed stream and retry later with a new registration and event-ID namespace.
proc failed(client: var Client, now: int64) =
  # An established or in-progress descriptor has exactly one close on this path.
  if client.opened: discard posix.close(client.fd)
  client.opened = false
  client.connecting = false
  client.length = 0
  client.offset = 0
  client.lost = 0
  client.retryAt = now + 5000

# Retain one complete bounded frame; caller must have finished the preceding frame.
proc queue(client: var Client, bytes: openArray[byte], now: int64) =
  client.length = bytes.len
  client.offset = 0
  client.deadline = now + 5000
  # Encoders are internally bounded below this fixed buffer's capacity.
  for i in 0..<bytes.len: client.buffer[i] = bytes[i]

# Assign one implicit ID even when a bounded buffer or disconnected collector loses the event.
# Every frame may append behind a partial frame when the fixed buffer has room.
proc event(client: var Client, bytes: openArray[byte], now: int64, timestamp: Timestamp): EventId =
  result = EventId(client.nextEvent)
  if not client.enabled: return # Disabled instrumentation neither allocates IDs nor owns resources.
  if client.nextEvent == high(uint64):
    client.close() # Never wrap correlation IDs into an older attempt's namespace.
    return
  inc client.nextEvent
  if not client.opened: return # The next registration's dropped prefix accounts for this position.
  let markerSize = if client.lost > 0: 29 else: 0
  if bytes.len + markerSize > client.buffer.len - client.length:
    if client.lost == 0: client.firstLost = timestamp # Bound storage for a contiguous missing run.
    client.lastLost = timestamp
    inc client.lost
    return
  if client.length == 0:
    client.offset = 0 # A new batch owns a new write deadline; appending cannot extend a stalled one.
    client.deadline = now + 5000
  if client.lost > 0:
    for item in dropped(client.firstLost, client.lastLost, client.lost):
      client.buffer[client.length] = item # The marker precedes the next actual event on the same stream.
      inc client.length
    client.lost = 0
  for item in bytes:
    client.buffer[client.length] = item # Append only after proving room for the complete frame and marker.
    inc client.length

# Capture an outgoing attempt and return its stream position for the later authentication outcome.
proc dialing*(client: var Client, now: int64, timestamp: Timestamp, identity: array[32, byte],
    address: array[16, byte], port: uint16): EventId =
  if not client.enabled: return EventId(0) # Avoid encoding or allocation when telemetry is disabled.
  client.event(connectingOut(timestamp, identity, address, port), now, timestamp)

# Publish exactly one terminal authentication outcome for a previously captured outgoing attempt.
proc dialOutcome*(client: var Client, now: int64, timestamp: Timestamp, attempt: EventId,
    authenticated: bool) =
  if not client.enabled: return # Disabled clients never encode events.
  if authenticated:
    discard client.event(connectedOut(timestamp, attempt), now, timestamp)
  else:
    discard client.event(connectOutFailed(timestamp, attempt), now, timestamp)

# Enqueue an observed authenticated peer closure using the same bounded event stream as its attempt.
proc peerDisconnected*(client: var Client, now: int64, timestamp: Timestamp,
    identity: array[32, byte]) =
  if not client.enabled: return # Disabled clients do not allocate or consume event IDs.
  discard client.event(disconnected(timestamp, identity), now, timestamp)

# Open a nonblocking close-on-exec descriptor and start one numeric-address connection attempt.
proc begin(client: var Client, now: int64, timestamp: Timestamp) =
  let family = if client.ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET
  client.fd = socket(cint(ord(family)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  # Resource exhaustion must not fail the peer or cause a busy retry loop.
  if client.fd < 0:
    client.failed(now)
    return
  client.opened = true
  let flags = fcntl(client.fd, F_GETFL, 0)
  let descriptorFlags = fcntl(client.fd, GetFd, 0)
  # Reject partial setup before connect, preserving nonblocking and inheritance guarantees.
  if flags < 0 or descriptorFlags < 0 or fcntl(client.fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(client.fd, SetFd, descriptorFlags or CloseExec) < 0:
    client.failed(now)
    return
  when defined(macosx):
    var enabled = 1.cint
    # Failure to suppress SIGPIPE is a telemetry setup failure, not a process-wide policy change.
    if setOption(client.fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) != 0:
      client.failed(now)
      return
  var connected = -1.cint
  if client.ipv6:
    # The configured family and exact sockaddr extent must agree on every reconnect.
    connected = connectSocket(client.fd, addr client.address6, SockLen(sizeof(Sockaddr_in6)))
  else:
    # IPv4 collectors retain the original native connect representation.
    connected = connectSocket(client.fd, addr client.address, SockLen(sizeof(Sockaddr_in)))
  # EINPROGRESS is normal; every other error schedules a bounded retry.
  if connected != 0 and osLastError() != OSErrorCode(EINPROGRESS):
    client.failed(now)
    return
  client.connecting = connected != 0
  client.statusAt = now + 2000
  var frames = registration(client.metadata)
  if client.nextEvent > 0:
    # A fresh collector connection starts at zero; skip all positions from previous connections.
    for item in dropped(timestamp, timestamp, client.nextEvent): frames.add(item)
  client.lost = 0
  client.queue(frames, now)

# Perform at most one poll and send per dispatcher turn. Times are caller-provided for deterministic tests.
proc tick*(client: var Client, now: int64, timestamp: Timestamp, peers: uint32) =
  # Disabled telemetry has no socket, clock, allocation or network work.
  if not client.enabled: return
  if not client.opened:
    # Retry spacing applies to refusals, stalled connects and write failures equally.
    if now < client.retryAt: return
    client.begin(now, timestamp)
    if not client.opened: return # Failed setup is isolated from normal peer work.
  # A collector cannot retain a pending connect or frame forever.
  if (client.connecting or client.length > 0) and now >= client.deadline:
    client.failed(now)
    return
  # Status is sampled every two seconds without catch-up loops after a delayed dispatcher turn.
  if now >= client.statusAt:
    client.statusAt = now + 2000
    discard client.event(status(client.metadata, timestamp, peers), now, timestamp)
  if not client.enabled: return # ID exhaustion may have retired the descriptor while sampling status.
  var entry = PollEntry(fd: client.fd, events: Writable, revents: 0)
  let ready = poll(addr entry, 1, 0)
  # EINTR simply defers work; all other poll errors and terminal flags retire the socket.
  if ready < 0:
    if osLastError() != OSErrorCode(EINTR): client.failed(now)
    return
  if (entry.revents and (PollError or Hangup or Invalid)) != 0:
    client.failed(now)
    return
  if ready == 0 or (entry.revents and Writable) == 0: return # Retry only on later dispatcher turns.
  if client.connecting:
    var error = 0.cint
    var size = SockLen(sizeof(error))
    # Writable alone does not establish connection success.
    if getOption(client.fd, SocketLevel, SocketError, addr error, addr size) != 0 or error != 0:
      client.failed(now)
      return
    client.connecting = false
  if client.length == 0: return # Connected idle clients have nothing to send.
  var flags = 0.cint
  when not defined(macosx):
    flags = NoSignal # Linux suppression is per syscall.
  let sent = sendBytes(client.fd, addr client.buffer[client.offset], csize_t(client.length -
      client.offset), flags)
  if sent > 0:
    # Retain unsent suffixes exactly; no frame can interleave with a partial write.
    client.offset += sent
    if client.offset == client.length:
      client.length = 0
      client.offset = 0
  elif sent == 0:
    client.failed(now) # A zero-byte send cannot make progress.
  else:
    let error = osLastError()
    # Backpressure and signals defer the same suffix; fatal errors start a fresh connection.
    if error != OSErrorCode(EAGAIN) and error != OSErrorCode(EWOULDBLOCK) and error != OSErrorCode(EINTR):
      client.failed(now)

# Account for a native observation that lacked bounded tracking space or usable metadata.
proc omit*(client: var Client, timestamp: Timestamp) =
  if not client.enabled: return # Disabled clients do not consume positions.
  if client.nextEvent == high(uint64):
    client.close() # Correlation IDs never wrap.
    return
  inc client.nextEvent
  if not client.opened: return # The next registration accounts for all missing positions.
  if client.lost == 0: client.firstLost = timestamp # Retain only the contiguous loss interval.
  client.lastLost = timestamp
  inc client.lost

# Record a remote endpoint before authentication; its public identity is not yet trusted.
proc accepting*(client: var Client, now: int64, timestamp: Timestamp,
    address: array[16, byte], port: uint16): EventId =
  if not client.enabled: return EventId(0) # Disabled telemetry avoids encoding.
  client.event(connectingIn(timestamp, address, port), now, timestamp)

# Publish the authenticated identity or an explicitly unknown failure reason for one incoming attempt.
proc acceptOutcome*(client: var Client, now: int64, timestamp: Timestamp, attempt: EventId,
    identity: array[32, byte], authenticated: bool) =
  if not client.enabled: return # Disabled telemetry avoids encoding.
  if authenticated:
    discard client.event(connectedIn(timestamp, attempt, identity), now, timestamp)
  else:
    discard client.event(connectInFailed(timestamp, attempt), now, timestamp)

# Queue a real admission refusal in the same bounded event-ID and loss sequence as other observations.
proc refusing*(client: var Client, now: int64, timestamp: Timestamp,
    address: array[16, byte], port: uint16) =
  if not client.enabled: return # Disabled telemetry performs no encoding work.
  discard client.event(connectionRefused(timestamp, address, port), now, timestamp)
