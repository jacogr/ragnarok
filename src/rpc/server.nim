# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional loopback WebSocket server driven by the peer dispatcher. No threads or blocking IO.
##
## Exposes the Server owner, publishBlock/publishFinalized handoffs and start/tick/close lifecycle.
## The caller services bounded connection slots and per-connection chain subscription queues.

import std/[nativesocket, oserrors, strutils, monotimes]
import std/posix/posix
import ./[wire, protocol]
import ../chain/[parameters, genesis, provider]

const MaxConnections* = 8

# Each slot's strings own their data; no transport/native callback retains a pointer into them.
type
  Connection = object
    opened, upgraded, closing, fragmented: bool
    fd: cint
    input, output, message: string
    offset: int
    session: RpcSession # Per-connection IDs and bounded notifications, released on disconnect.
    deadline, messageDeadline: int64
  Server* = object
    opened: bool
    fd: cint
    connections: array[MaxConnections, Connection]
    started: int64
    port: uint16
    role: string
    chain: ChainView            # Retained immutable provider view shared by one dispatcher tick.
    parameters: ParameterResult # Fixed-size owned configuration shared by all connections.

# POSIX APIs borrow bounded stack values only for their synchronous nonblocking syscall.
proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
proc bindSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
proc listenSocket(fd, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
proc acceptSocket(fd: cint, address, size: nil pointer): cint {.importc: "accept",
    header: "<sys/socket.h>".}
proc receive(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
proc sendBytes(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
proc setOption(fd, level, option: cint, value: pointer,
    size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
proc parseAddress(family: cint, text: cstring, output: pointer): cint {.importc: "inet_pton",
    header: "<arpa/inet.h>".}
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
let
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
when defined(macosx):
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint # Per-descriptor SIGPIPE suppression.
else:
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint # Per-send Linux suppression.

# Composite owner is explicitly non-copyable: copying slots would duplicate native descriptor ownership.
proc `=copy`*(destination: var Server, source: Server) {.error: "RPC Server owns socket descriptors".}
# ARC destruction closes every live descriptor, including partial startup and exception paths.
proc `=destroy`*(server: Server) =
  if server.opened:
    # Default instances never close stdin.
    discard posix.close(server.fd)
  for slot in server.connections: # Slots are owned solely by this server, without reference cycles.
    if slot.opened:
      discard posix.close(slot.fd)

  # Custom destruction must release dynamic ARC fields as well as native descriptors.
  `=destroy`(server.connections)
  `=destroy`(server.role)
  `=destroy`(server.chain) # The retained state map is an ARC owner too.

# Retire one slot exactly once and release queued data; close is not retried after EINTR.
proc close(slot: var Connection) =
  if slot.opened:
    discard posix.close(slot.fd)
  slot.opened = false
  slot.session = default(RpcSession) # Reused connection slots cannot inherit subscriptions or pending updates.
  slot.input = ""; slot.output = ""; slot.message = ""
  slot.messageDeadline = 0
  slot.offset = 0; slot.upgraded = false; slot.closing = false; slot.fragmented = false

# Explicit shutdown is idempotent and leaves ARC with no live native handles.
proc close*(server: var Server) =
  for slot in mitems(server.connections):
    # Release accepted sockets before listener.
    slot.close()
  if server.opened:
    discard posix.close(server.fd)
  server.opened = false

# Configure descriptor flags before any network operation; failed configuration leaves ownership with caller.
proc nonblocking(fd: cint): bool =
  let flags = fcntl(fd, F_GETFL, 0)
  let descriptorFlags = fcntl(fd, GetFd, 0)
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFd, descriptorFlags or CloseExec) < 0: return false
  when defined(macosx): # BSD requires an explicit socket option to avoid process termination on send.
    var enabled = 1.cint
    if setOption(fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) != 0:
      return false
  true

# Bind loopback only; port zero disables RPC. Startup failure is reported to the peer CLI.
proc start*(server: var Server, port: uint16, role: string,
    parameters = unavailableParameters(), genesis = unavailableGenesis()): bool =
  if server.opened:
    # A second start cannot leak or replace a live listener.
    return false
  if port == 0:
    # Disabled by default, with no allocation or clock work.
    return true
  server.fd = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if server.fd < 0:
    return false
  server.opened = true
  var address = default(Sockaddr_in)
  address.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  address.sin_port = networkPort(port)
  when defined(macosx):
    # Darwin includes the sockaddr extent.
    address.sin_len = uint8(sizeof(Sockaddr_in))
  var loopback = "127.0.0.1"
  let host = loopback.toCString()
  let family = cint(ord(nativesocket.AF_INET))
  if not nonblocking(server.fd) or parseAddress(family, host, addr address.sin_addr) != 1:
    server.close() # Atomic flag/address failure retires the listener before binding.
    return false
  if bindSocket(server.fd, addr address, SockLen(sizeof(address))) != 0:
    server.close() # A requested occupied port cannot silently disable RPC.
    return false
  if listenSocket(server.fd, cint(MaxConnections)) != 0:
    server.close() # Failed admission setup cannot leave an unusable bound socket.
    return false
  server.started = getMonoTime().ticks div 1_000_000
  server.port = port
  server.role = role
  server.parameters = parameters
  server.chain = genesisView(genesis)
  true

## Publish a caller-validated direct child between ticks on the same dispatcher thread.
## Closed/disabled listeners and missing seeds return Uninitialized; other failures preserve the
## current view and forward advanceView's reason. Success replaces the chain and queues subscription updates,
## preserving sockets, queued replies and startup parameters unless a subscriber FIFO overflows.
## This is not a thread-safe import/validation API.
proc publishBlock*(server: var Server, child: BlockSnapshotResult): ViewAdvanceError =
  if not server.opened:
    return ViewAdvanceError.Uninitialized # Shutdown cannot be bypassed by publishing another snapshot.
  let update = server.chain.advanceView(child)
  if update.error != ViewAdvanceError.None:
    return update.error # Never install a partial or rejected history.
  server.chain = update.value
  for slot in mitems(server.connections):
    if slot.opened and slot.upgraded and not slot.closing: # Only usable WS connections receive events.
      if not slot.session.queueChainUpdates(child):
        slot.close() # Disconnect only the overflowing consumer; never drop updates or reject the chain head.
  ViewAdvanceError.None

## Record caller-certified finality between ticks on the same dispatcher thread, without inferring it.
## Requires a known retained chain block; failures leave the view intact. No finality proof is verified.
## A new finalized head emits only finalized subscription events; repeats are silent and best is unchanged.
proc publishFinalized*(server: var Server, hash: BlockHash): ViewFinalizeError =
  if not server.opened:
    return ViewFinalizeError.Uninitialized # Closed listeners cannot receive state publications.
  let update = server.chain.finalizeView(hash)
  if update.error != ViewFinalizeError.None:
    return update.error # Preserve the entire view on a rejected selection.
  let previous = server.chain.finalizedBlock
  if previous.error == GenesisError.None:
    if array[32, byte](previous.value.blockHash) == array[32, byte](hash):
      return ViewFinalizeError.None # Idempotent publication must not duplicate notifications.
  server.chain = update.value
  for slot in mitems(server.connections):
    if slot.opened and slot.upgraded and not slot.closing:
      if not slot.session.queueChainUpdates(server.chain.finalizedBlock, finalized = true):
        slot.close() # Finality still advances; only the slow consumer is disconnected.
  ViewFinalizeError.None

# Queue a bounded close frame, then allow only its partial writes until the absolute deadline.
proc reject(slot: var Connection, code: int, now: int64) =
  let payload = $char(code shr 8) & $char(code and 255)
  slot.output = frame(payload, 8)
  slot.offset = 0
  slot.closing = true
  slot.deadline = now + 5000

# Process at most one frame per slot/turn, including control frames interleaved with fragmented text.
proc process(slot: var Connection, info: ClientInfo, now: int64) =
  if not slot.upgraded: # The only HTTP operation is an explicit WebSocket upgrade, never RPC over POST.
    let ending = slot.input.find("\r\n\r\n")
    if ending < 0:
      if slot.input.len >= MaxHeader:
        # Incomplete headers cannot grow without bound.
        slot.close()
      return
    let response = upgrade(slot.input[0..<ending + 4])
    if response.len == 0:
      # Invalid upgrades close without dispatching their body.
      slot.close()
      return
    slot.input = slot.input[ending + 4..^1]
    slot.output = response
    slot.upgraded = true
    slot.deadline = now + 5000
    return
  let parsed = decodeFrame(slot.input)
  if parsed.status == incomplete:
    # Retain bytes until the fixed deadline.
    return
  if parsed.status == invalid:
    # Fail the connection on framing violations.
    slot.reject(1002, now)
    return
  slot.input = slot.input[parsed.consumed..^1]
  case parsed.opcode
  of 8: # A close body is either empty or a legal status code followed by UTF-8 text.
    let payload = parsed.payload
    if payload.len == 1:
      slot.reject(1002, now)
      return
    if payload.len >= 2:
      let code = ord(payload[0]) * 256 + ord(payload[1])
      if not (code in [1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014] or
          code in 3000..4999): slot.reject(1002, now); return
      if not validUtf8(payload[2..^1]):
        slot.reject(1007, now)
        return
    slot.output = frame(payload, 8); slot.closing = true # Echo valid close and retire after delivery.
  of 9:
    # Ping payload is echoed exactly in an unmasked pong.
    slot.output = frame(parsed.payload, 10)
  of 10:
    # Unsolicited pongs are allowed and carry no application data.
    discard
  of 2:
    # JSON-RPC messages use text frames only.
    slot.reject(1003, now)
    return
  of 0, 1:
    if (parsed.opcode == 0 and not slot.fragmented) or (parsed.opcode == 1 and slot.fragmented):
      slot.reject(1002, now); return # Continuations cannot start messages or overlap existing ones.
    if parsed.payload.len > MaxMessage - slot.message.len:
      slot.reject(1009, now)
      return
    if not slot.fragmented:
      # Ping/pong cannot extend fragmented-message lifetime.
      slot.messageDeadline = now + 5000
    slot.message.add(parsed.payload)
    slot.fragmented = not parsed.final
    if parsed.final: # UTF-8 is checked across the assembled message, allowing splits inside code points.
      if not validUtf8(slot.message):
        slot.reject(1007, now)
        return
      let response = respond(slot.message, info, slot.session)
      slot.message = ""
      slot.messageDeadline = 0
      if response.len > 0:
        # Notifications have no response frame.
        slot.output = frame(response)
  else:
    # Decoder already excludes reserved opcodes.
    slot.reject(1002, now)
    return
  slot.offset = 0
  if slot.output.len > 0:
    # A slow consumer gets one absolute write budget.
    slot.deadline = now + 5000
  elif slot.input.len == 0 and not slot.fragmented:
    # Idle keepalive window.
    slot.deadline = now + 30000

# One accept, one bounded read, one frame and one write per slot per turn; called by the existing peer loop.
proc tick*(server: var Server, peers: uint32) =
  if not server.opened:
    # Default peer operation does no additional syscall or clock work.
    return
  let now = getMonoTime().ticks div 1_000_000
  let accepted = acceptSocket(server.fd, nil, nil)
  if accepted >= 0: # Capacity pressure closes only the newly accepted socket.
    var free = -1
    for i in 0..<MaxConnections:
      if not server.connections[i].opened:
        # At most one admission per dispatcher turn.
        free = i
        break
    if free < 0 or not nonblocking(accepted):
      discard posix.close(accepted)
    else:
      server.connections[free].fd = accepted
      server.connections[free].opened = true
      server.connections[free].deadline = now + 5000
  let info = ClientInfo(uptimeMs: now - server.started, peers: peers, role: server.role,
      port: server.port, parameters: server.parameters, chain: server.chain,
      occupiedBytes: getOccupiedMem(), reservedBytes: getTotalMem())
  for slot in mitems(server.connections): # Fixed capacity bounds per-turn work and memory.
    if not slot.opened:
      continue
    if now >= slot.deadline or (slot.fragmented and now >= slot.messageDeadline):
      # Partial headers/messages and blocked writes expire.
      slot.close()
      continue
    if slot.output.len == 0 and not slot.closing:
      var bytes = default(array[4096, char])
      let count = receive(slot.fd, addr bytes[0], csize_t(bytes.len), 0)
      if count == 0:
        # Orderly EOF retires queued input.
        slot.close()
        continue
      if count < 0:
        let error = osLastError()
        if error notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(EINTR)]:
          slot.close()
          continue
      else:
        if count > MaxMessage + 14 - slot.input.len:
          slot.reject(1009, now) # Reject before appending beyond the fixed receive allowance.
        else:
          if slot.input.len == 0 and not slot.fragmented and slot.upgraded:
            slot.deadline = now + 5000 # Begin one fixed partial-message deadline.
          for i in 0..<count:
            # Copy only the initialized native prefix.
            slot.input.add(bytes[i])
      if slot.opened and slot.output.len == 0:
        slot.process(info, now)
    if slot.opened and not slot.closing and slot.output.len == 0:
      let update = slot.session.nextUpdate()
      if update.len > 0:
        slot.output = frame(update) # Request replies precede queued notifications on this connection.
        slot.offset = 0
        slot.deadline = min(slot.deadline, now + 5000) # Notifications cannot extend a partial input deadline.
    if not slot.opened or slot.output.len == 0:
      continue
    var flags = 0.cint
    when not defined(macosx):
      # Linux protects each send independently.
      flags = NoSignal
    let data = slot.output.toCString()
    let sent = sendBytes(slot.fd, cast[pointer](cast[uint](data) + uint(slot.offset)),
        csize_t(slot.output.len - slot.offset), flags)
    if sent > 0:
      slot.offset += sent
      if slot.offset == slot.output.len: # All response bytes were handed to the kernel.
        slot.output = ""; slot.offset = 0
        if slot.closing:
          slot.close()
        elif slot.input.len == 0 and not slot.fragmented:
          slot.deadline = now + 30000
    elif sent == 0:
      # A zero-progress send cannot spin indefinitely.
      slot.close()
    else:
      let error = osLastError()
      if error notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(EINTR)]:
        slot.close()
