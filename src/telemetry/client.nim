# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dispatcher-owned JIP-3 delivery with one task-owned Socket/Writer connection.
## Event IDs, registration, dropped ranges and status timing stay with this owner;
## the task receives detached bytes only. Staging and in-flight batches share a single
## 2 KiB credit budget, held until Writer.flush completes. Appending never extends a
## batch deadline. The stream module owns partial sends and joined I/O cleanup.
##
## Reconnect registers again and advances the collector over every earlier observation
## position, including omitted events. ID exhaustion disables delivery rather than wrapping.
## Collector failures discard queued bytes and request task retirement without blocking a
## dispatcher tick. Shutdown aborts output and joins the bounded operation before the shared
## reactor stops. Wire layout belongs to wire.nim; native observations enter through observer.nim.

import std/[strutils, nativesocket, ioring]
import std/posix/posix
import ../lib/socket_io
import ./wire
import ./stream
import ../lib/logging

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
  Client* = object ## One dispatcher and one exclusive stream keep the exporter bounded.
    enabled, opened, connecting: bool
    stream: TelemetryStream
    address: Sockaddr_in
    address6: Sockaddr_in6
    ipv6: bool
    collectorName: string
    collectorPort: uint16
    metadata: Metadata
    logWriter: LogWriter
    buffer: array[MaxPendingBytes, byte]
    length, inFlight: int
    retryAt, deadline, statusAt: int64
    nextEvent, lost: uint64
    firstLost, lastLost: Timestamp

proc `=copy`*(destination: var Client, source: Client) {.error: "Telemetry Client owns its stream task".}
  ## Task ownership may move but must never duplicate a live mailbox or join obligation.

proc `=dup`*(source: Client): Client {.error.}
  ## Implicit duplication cannot duplicate task retirement authority.

proc `=wasMoved`*(client: var Client) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  client.enabled = false
  client.opened = false
  client.connecting = false
  `=wasMoved`(client.stream)
  `=wasMoved`(client.collectorName)
  `=wasMoved`(client.metadata)

proc `=destroy`*(client: Client) =
  ## Join the stream before its stable mailbox and borrowed runtime can retire.
  `=destroy`(client.stream)
  `=destroy`(client.collectorName)
  `=destroy`(client.metadata)

proc disable(client: var Client) =
  ## Revoke retries without waiting in event callbacks or dispatcher error paths.
  client.stream.stop()
  client.opened = false
  client.enabled = false
  client.length = 0
  client.inFlight = 0

proc close*(client: var Client) =
  ## Disable retries and abort best-effort delivery; the original I/O deadline bounds joining.
  client.disable()
  client.stream.close()

proc enabled*(client: Client): bool =
  ## Observation adapters query this owner, not process-global command-line configuration.
  client.enabled

func isCollectorName(host: string): bool =
  ## Accept ASCII DNS labels and an optional root dot. Malformed IPv4 remains invalid.
  if host.len == 0 or host.len > MaxCollectorName: return false
  var label = 0
  var previous = '.'
  var named = false
  for character in host:
    case character
    of '.':
      if label == 0 or previous == '-': return false
      label = 0
    of 'a'..'z', 'A'..'Z', '0'..'9', '-':
      if label == 63 or (label == 0 and character == '-'): return false
      inc label
      if character in {'a'..'z', 'A'..'Z'}: named = true
    else: return false # An endpoint is a host, never a URL, scope or percent escape.
    previous = character
  named and previous != '-' and (host.len < MaxCollectorName or previous == '.')

proc configure*(client: var Client, endpoint: string, metadata: Metadata,
    writer: LogWriter = default(LogWriter)): bool =
  ## Configure once before ticking. Unsupported endpoints and metadata fail without opening any socket.
  ## An optional writer is borrowed; its logger must outlive this client.
  # Reconfiguration could replace native ownership or a partially sent frame.
  if client.enabled or client.stream.active or metadata.coreCount == 0: return false
  # The longest DNS name may have a root dot, colon and five port digits.
  if endpoint.len == 0 or endpoint.len > MaxCollectorName + 6 or '\0' in endpoint: return false
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
  var name = ""
  if ipv6:
    let hostPointer = host.toCString()
    # Native parsing rejects malformed literals, zones and bracketed IPv4 without DNS.
    if host.len > 45 or '%' in host or parseAddress(cint(ord(nativesocket.AF_INET6)), hostPointer,
        addr address6.sin6_addr) != 1: return false
    address6.sin6_family = TSa_Family(ord(nativesocket.AF_INET6))
    address6.sin6_port = networkPort(uint16(port))
    when defined(macosx):
      # BSD requires the native sockaddr byte extent as well as its family.
      address6.sin6_len = uint8(sizeof(Sockaddr_in6))
  elif host.len > 15 or not collectorIpv4Address(host, uint16(port), address):
    # Only a syntactically valid name may turn a literal parse failure into a lookup.
    if not isCollectorName(host): return false
    name = move(host)
  client.address = address
  client.address6 = address6
  client.ipv6 = ipv6
  client.collectorName = move(name)
  client.collectorPort = uint16(port)
  client.metadata = metadata
  client.retryAt = 0
  client.statusAt = 0
  client.lost = 0
  client.nextEvent = 0
  client.connecting = false
  client.logWriter = writer
  client.enabled = true
  true

proc failed(client: var Client, now: int64, reason = default(ErrorCode)) =
  ## Retire a failed stream and schedule a retry.
  ## A new stream needs fresh registration, but pending handshakes retain their attempt IDs.
  ## Keep the exporter position so reconnect can account for discarded frames.
  ## Retirement is nonblocking here; a later tick collects Done before starting another attempt.
  client.stream.stop()
  client.opened = false
  client.connecting = false
  client.length = 0
  client.inFlight = 0
  client.lost = 0
  client.retryAt = now + 5000
  let detail = if reason == default(ErrorCode): "" else: " (" & $reason & ")"
  log(client.logWriter, LogTarget.Telemetry, LogLevel.Warn,
    "Telemetry collector connection unavailable; retrying in 5s" & detail)

proc queue(client: var Client, bytes: openArray[byte], now: int64) =
  ## Retain one complete bounded frame; caller must have finished the preceding frame.
  client.length = bytes.len
  client.inFlight = 0
  client.deadline = now + 5000
  # Encoders are internally bounded below this fixed buffer's capacity.
  for i in 0..<bytes.len: client.buffer[i] = bytes[i]

proc event(client: var Client, bytes: openArray[byte], now: int64, timestamp: Timestamp): EventId =
  ## Assign one implicit ID even when a bounded buffer or disconnected collector loses the event.
  ## Every frame may append behind a partial frame when the fixed buffer has room.
  result = EventId(client.nextEvent)
  if not client.enabled: return # Disabled instrumentation neither allocates IDs nor owns resources.
  if client.nextEvent == high(uint64):
    client.disable() # Never wrap correlation IDs into an older attempt's namespace.
    return
  inc client.nextEvent
  if not client.opened: return # The next registration's dropped prefix accounts for this position.
  let markerSize = if client.lost > 0: 29 else: 0
  if bytes.len + markerSize > client.buffer.len - client.length - client.inFlight:
    if client.lost == 0: client.firstLost = timestamp # Bound storage for a contiguous missing run.
    client.lastLost = timestamp
    inc client.lost
    return
  if client.length == 0 and client.inFlight == 0:
    # Credit remains occupied during a write; appending behind it keeps its original deadline.
    client.deadline = now + 5000
  if client.lost > 0:
    for item in dropped(client.firstLost, client.lastLost, client.lost):
      client.buffer[client.length] = item # The marker precedes the next actual event on the same stream.
      inc client.length
    client.lost = 0
  for item in bytes:
    client.buffer[client.length] = item # Append only after proving room for the complete frame and marker.
    inc client.length

proc dialing*(client: var Client, now: int64, timestamp: Timestamp, identity: array[32, byte],
    address: array[16, byte], port: uint16): EventId =
  ## Capture an outgoing attempt and return its stream position for the later authentication outcome.
  if not client.enabled: return EventId(0) # Avoid encoding or allocation when telemetry is disabled.
  client.event(connectingOut(timestamp, identity, address, port), now, timestamp)

proc dialOutcome*(client: var Client, now: int64, timestamp: Timestamp, attempt: EventId,
    authenticated: bool) =
  ## Publish exactly one terminal authentication outcome for a previously captured outgoing attempt.
  if not client.enabled: return # Disabled clients never encode events.
  if authenticated:
    discard client.event(connectedOut(timestamp, attempt), now, timestamp)
  else:
    discard client.event(connectOutFailed(timestamp, attempt), now, timestamp)

proc peerDisconnected*(client: var Client, now: int64, timestamp: Timestamp,
    identity: array[32, byte]) =
  ## Enqueue an observed authenticated peer closure using the same bounded event stream as its attempt.
  if not client.enabled: return # Disabled clients do not allocate or consume event IDs.
  discard client.event(disconnected(timestamp, identity), now, timestamp)

proc begin(client: var Client, now: int64, timestamp: Timestamp) =
  ## Launch the admitted endpoint and queue registration before publishing events.
  log(client.logWriter, LogTarget.Telemetry, LogLevel.Info, "Connecting to telemetry collector")
  let started =
    if client.collectorName.len != 0:
      # Each retry asks the resolver again instead of keeping the previous choice.
      client.stream.start(client.collectorName, client.collectorPort)
    else:
      var address = default(Sockaddr_storage)
      let size = if client.ipv6: sizeof(Sockaddr_in6) else: sizeof(Sockaddr_in)
      if size > sizeof(Sockaddr_storage):
        client.failed(now, IOError) # Refuse an unsupported platform layout before copying native address bytes.
        return
      if client.ipv6:
        copyMem(addr address, addr client.address6, size)
      else:
        copyMem(addr address, addr client.address, size)
      let family = if client.ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET
      client.stream.start(address, SockLen(size), family)
  if not started:
    client.failed(now)
    return
  client.opened = true
  client.connecting = true
  client.statusAt = now + 2000
  var frames = registration(client.metadata)
  if client.nextEvent > 0:
    # A fresh collector connection starts at zero; skip all positions from previous connections.
    for item in dropped(timestamp, timestamp, client.nextEvent): frames.add(item)
  client.lost = 0
  client.queue(frames, now)

proc tick*(client: var Client, now: int64, timestamp: Timestamp, peers: uint32) =
  ## Drive completions and transfer at most one bounded batch per dispatcher turn.
  ## Only the Writer task waits for connection/send progress. Completed credit retires before
  ## status sampling, so a simultaneous lifecycle event and status cannot manufacture loss.
  ## Caller monotonic time controls retry, status and the fixed deadline for queued bytes.
  if not client.enabled: return
  if client.stream.active:
    pollTelemetryStreams()
    if client.stream.finished:
      let error = client.stream.failure
      client.stream.close() # Done guarantees this collection cannot wait on I/O.
      if client.opened:
        client.failed(now, error)
    elif client.stream.ready:
      client.inFlight = 0 # Writer.flush has finished borrowing the previous batch.
      if client.connecting:
        client.connecting = false
        log(client.logWriter, LogTarget.Telemetry, LogLevel.Info, "Connected to telemetry collector")
  if not client.opened:
    # A retiring task keeps its mailbox until Done; retry cannot overwrite that borrow.
    if client.stream.active or now < client.retryAt: return
    client.begin(now, timestamp)
    if not client.opened: return
  if (client.connecting or client.length > 0 or client.inFlight > 0) and now >= client.deadline:
    client.failed(now, TimeoutError)
    return
  if now >= client.statusAt:
    # No catch-up loop after a delayed dispatcher turn; appends retain the batch deadline.
    client.statusAt = now + 2000
    discard client.event(status(client.metadata, timestamp, peers), now, timestamp)
  if not client.enabled: return # Event-ID exhaustion may have retired the stream.
  if client.length > 0 and client.stream.ready:
    let remaining = client.deadline - now
    if client.stream.send(toOpenArray(client.buffer, 0, client.length-1), afterMs(int(remaining))):
      client.inFlight = client.length
      client.length = 0 # The detached mailbox now holds these bytes against the same credit budget.

proc omit*(client: var Client, timestamp: Timestamp) =
  ## Account for a native observation that lacked bounded tracking space or usable metadata.
  if not client.enabled: return # Disabled clients do not consume positions.
  if client.nextEvent == high(uint64):
    client.disable() # Correlation IDs never wrap.
    return
  inc client.nextEvent
  if not client.opened: return # The next registration accounts for all missing positions.
  if client.lost == 0: client.firstLost = timestamp # Retain only the contiguous loss interval.
  client.lastLost = timestamp
  inc client.lost

proc accepting*(client: var Client, now: int64, timestamp: Timestamp,
    address: array[16, byte], port: uint16): EventId =
  ## Record a remote endpoint before authentication; its public identity is not yet trusted.
  if not client.enabled: return EventId(0) # Disabled telemetry avoids encoding.
  client.event(connectingIn(timestamp, address, port), now, timestamp)

proc acceptOutcome*(client: var Client, now: int64, timestamp: Timestamp, attempt: EventId,
    identity: array[32, byte], authenticated: bool) =
  ## Publish the authenticated identity or an explicitly unknown failure reason for one incoming attempt.
  if not client.enabled: return # Disabled telemetry avoids encoding.
  if authenticated:
    discard client.event(connectedIn(timestamp, attempt, identity), now, timestamp)
  else:
    discard client.event(connectInFailed(timestamp, attempt), now, timestamp)

proc refusing*(client: var Client, now: int64, timestamp: Timestamp,
    address: array[16, byte], port: uint16) =
  ## Queue a real admission refusal in the same bounded event-ID and loss sequence as other observations.
  if not client.enabled: return # Disabled telemetry performs no encoding work.
  discard client.event(connectionRefused(timestamp, address, port), now, timestamp)
