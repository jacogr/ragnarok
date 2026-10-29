# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Move-only local fuzzer listener bounds each tick and hands execution tickets to the host outside IO.
import std/[nativesocket, oserrors, strutils, monotimes, assertions]
import std/posix/posix
import ../../state/fuzz/[protocol as fuzz_protocol, session as fuzz_session]
import ../../codec/bounded
import ../../management/file_status
import ../../lib/utf8

const IoBytes = 4096 ## Each dispatcher turn performs at most one read and one write of this extent.
type
  LocalAddress = object
    ## POSIX local-address prefix uses a common 104-byte pathname extent; Linux accepts this shorter bounded address.
    when defined(macosx):
      sun_len: uint8
      sun_family: uint8
    else:
      sun_family: cushort
    sun_path: array[104, char]
  FuzzSocketConfig* = object ## Trusted host policy supplies the target declaration, wire bounds and absolute exchange deadline.
    path*: string
    timeoutMs*: int
    peer*: FuzzPeer
    limits*: FuzzLimits
  FuzzSocket* = object ## One listener and one connection own all descriptors, frames and pending request identity.
    opened, bound, connected, waiting: bool
    fd, connection: cint
    identity: FileStatus
    config: FuzzSocketConfig
    generation: uint64
    deadline: int64
    reader: FuzzFrameReader
    session: FuzzSession
    ticket: FuzzRequest
    output: seq[byte]
    offset: int
proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Acquire a local stream descriptor without granting ownership on failure.
proc bindSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
  ## Borrow one fully initialized native pathname during bind.
proc listenSocket(fd, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
  ## A single pending connection bounds the listener queue request.
proc acceptSocket(fd: cint, address, size: nil pointer): cint {.importc: "accept",
    header: "<sys/socket.h>".}
  ## Admit a new connection only when the previous session has retired.
proc receive(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Read only into an initialized bounded stack buffer.
proc sendBytes(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Preserve partial write offsets in the owned output frame.
proc effectiveUid(): uint32 {.importc: "geteuid", header: "<unistd.h>".}
  ## Socket parent ownership is checked against the actual effective user.
let
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
when defined(macosx):
  proc setOption(fd, level, option: cint, value: pointer,
      size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
    ## Darwin suppresses SIGPIPE on each admitted descriptor.
  let SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint
else:
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint
proc removeSocket(server: FuzzSocket) =
  ## Replacement paths and files never inherit cleanup authority from this lifetime.
  if server.bound:
    var current = default(FileStatus)
    var path = server.config.path
    if readStatus(path.toCString(), current) == 0 and S_ISSOCK(Mode(current.st_mode)) and
        current.st_dev == server.identity.st_dev and current.st_ino == server.identity.st_ino:
      discard unlink(path.toCString()) # Exact inode ownership confines removal to the bound socket.
proc `=copy`*(destination: var FuzzSocket, source: FuzzSocket) {.error.}
  ## Descriptor ownership cannot be copied between hosts.
proc `=dup`*(source: FuzzSocket): FuzzSocket {.error.}
  ## Implicit duplication is also forbidden.
proc `=wasMoved`*(server: var FuzzSocket) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  server.opened = false
  server.bound = false
  server.connected = false
  server.waiting = false
  server.fd = -1
  server.connection = -1
  `=wasMoved`(server.config)
  `=wasMoved`(server.reader)
  `=wasMoved`(server.session)
  `=wasMoved`(server.ticket)
  `=wasMoved`(server.output)

proc `=destroy`*(server: FuzzSocket) =
  ## Default/moved owners never close descriptor zero; partial startup releases every acquired resource.
  if server.connected: discard posix.close(server.connection)
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  `=destroy`(server.config)
  `=destroy`(server.reader)
  `=destroy`(server.session)
  `=destroy`(server.ticket)
  `=destroy`(server.output)
proc disconnect*(server: var FuzzSocket) =
  ## Retire a connection and all its tickets while leaving the listener ready for a new session.
  if server.connected: discard posix.close(server.connection)
  server.connected = false
  server.waiting = false
  server.session.close()
  server.reader = default(FuzzFrameReader)
  server.ticket = default(FuzzRequest)
  server.output = @[]
  server.offset = 0
proc close*(server: var FuzzSocket) =
  ## Explicit shutdown is idempotent and uses the same inode-limited cleanup as ARC retirement.
  server.disconnect()
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  server.opened = false
  server.bound = false
  server.config = default(FuzzSocketConfig)
func connected*(server: FuzzSocket): bool =
  ## Backend state belongs to an active connection only.
  server.connected
func generation*(server: FuzzSocket): uint64 =
  ## Each accepted connection gets a distinct generation; exhaustion stops further admission.
  server.generation
func hasRequest*(server: FuzzSocket): bool =
  ## A pending execution ticket is distinct from partial input or an automatic handshake reply.
  server.connected and server.waiting
func request*(server: FuzzSocket): FuzzRequest {.inline, requires: server.hasRequest.} =
  ## Borrow immutable request authority for execution outside the transport tick.
  server.ticket
func negotiatedFeatures*(server: FuzzSocket): uint32 =
  ## The host activates optional backend behavior only after the actual handshake intersection.
  if server.connected: server.session.negotiatedFeatures else: 0'u32
proc nonblocking(fd: cint): bool =
  ## Install nonblocking IO, close-on-exec and signal safety before exposing a descriptor.
  let flags = fcntl(fd, F_GETFL, 0)
  let descriptorFlags = fcntl(fd, GetFd, 0)
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFd, descriptorFlags or CloseExec) < 0: return false
  when defined(macosx):
    var enabled = 1.cint
    if setOption(fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) != 0:
      return false # No socket can become usable without SIGPIPE suppression.
  true
proc start*(server: var FuzzSocket, config: FuzzSocketConfig): bool =
  ## Reject bad policy and existing paths before opening a bounded private listener.
  if server.opened or server.bound or config.timeoutMs <= 0 or config.timeoutMs > 3600000:
    return false
  if initFuzzSession(config.peer, config.limits).error != FuzzSessionError.None or
      uint64(config.limits.bytes) > uint64(high(int)-4): return false
  let path = config.path
  if path.len == 0 or path.len > 103 or path[0] != '/' or path.endsWith('/') or not validUtf8(path):
    return false
  for c in path:
    if ord(c) < 32 or ord(c) == 127: return false # No native truncation or ambiguous control-bearing path.
  let slash = path.rfind('/')
  var directory = if slash == 0: "/" else: path.substr(0, slash-1)
  var parent = default(FileStatus)
  if readStatus(directory.toCString(), parent) != 0 or not S_ISDIR(Mode(parent.st_mode)) or
      uint32(parent.st_uid) != effectiveUid() or (uint32(parent.st_mode) and 0o077'u32) != 0:
    return false # The bind-to-chmod interval remains inside a private directory.
  var address = default(LocalAddress)
  address.sun_family = typeof(address.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): address.sun_len = uint8(sizeof(address)) # Native Darwin requires its address extent.
  for index, c in path: address.sun_path[index] = c # The zero-initialized terminator remains within the common bound.
  let fd = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if fd < 0: return false
  server.fd = fd
  server.opened = true
  if not nonblocking(fd) or bindSocket(fd, addr address, SockLen(sizeof(address))) != 0:
    server.close()
    return false # An existing path remains untouched, including another live socket.
  server.config = config
  var nativePath = path
  if readStatus(nativePath.toCString(), server.identity) != 0:
    server.close()
    return false # Never assume ownership without an observed native inode.
  server.bound = true
  if chmod(nativePath.toCString(), Mode(0o600)) != 0 or listenSocket(fd, 1) != 0:
    server.close()
    return false # Partial successful startup retires its own path and descriptor.
  true
proc queue(server: var FuzzSocket, message: FuzzMessage): bool =
  ## A complete output frame is retained until every byte drains; no second reply can overwrite it.
  if server.output.len != 0: return false
  let encoded = message.encodeFuzzFrame(ByteLimit(uint64(server.config.limits.bytes)+4))
  if encoded.error != FuzzError.None: return false
  server.output = encoded.value
  server.offset = 0
  true
proc respond*(server: var FuzzSocket, ticket: FuzzRequest, message: FuzzMessage): bool =
  ## Submit only a genuine host outcome matching the still-live ticket; internal failure uses disconnect instead.
  if not server.hasRequest: return false
  let response = server.session.respond(ticket, message)
  if response.error != FuzzSessionError.None or not server.queue(response.value):
    server.disconnect()
    return false # Invalid host responses cannot reach the socket as consensus errors.
  server.waiting = false
  server.ticket = default(FuzzRequest)
  true
proc tick*(server: var FuzzSocket) =
  ## One bounded read/write per turn; neither partial input nor output can extend the absolute deadline.
  if not server.opened: return
  let now = getMonoTime().ticks div 1000000
  if not server.connected:
    if server.generation == high(uint64): return # Retiring the process is required before identity can wrap.
    let fd = acceptSocket(server.fd, nil, nil)
    if fd >= 0:
      if not nonblocking(fd): discard posix.close(fd) # Failed setup never becomes an active connection.
      else:
        server.connection = fd
        server.connected = true
        inc server.generation
        server.deadline = now+int64(server.config.timeoutMs)
        server.reader = initFuzzFrameReader(server.config.limits)
        server.session = initFuzzSession(server.config.peer, server.config.limits).value
  if not server.connected: return
  if now >= server.deadline:
    server.disconnect()
    return # Timeout retires partial input, output and pending execution authority together.
  if not server.waiting and server.output.len == 0:
    var bytes = default(array[IoBytes, byte])
    let count = receive(server.connection, addr bytes[0], csize_t(IoBytes), 0)
    if count > 0:
      let decoded = server.reader.feed(bytes.toOpenArray(0, count-1))
      if decoded.error != FuzzSessionError.None or decoded.value.consumed != count:
        server.disconnect()
        return # Pipelining violates sequential request/response and never creates hidden queued work.
      if decoded.value.complete:
        let dispatch = server.session.receive(decoded.value.message)
        if dispatch.error != FuzzSessionError.None:
          server.disconnect()
          return # Malformed ordering/profile failures close without an Error reply.
        case dispatch.value.kind
        of FuzzDispatchKind.Reply:
          if not server.queue(dispatch.value.reply):
            server.disconnect()
            return # Output resource failure is an internal fault, not consensus import rejection.
        of FuzzDispatchKind.Execute:
          server.ticket = dispatch.value.request
          server.waiting = true # Host execution is intentionally outside this bounded IO callback.
    elif count == 0:
      server.disconnect()
      return # EOF leaves the listener alive for a fresh session.
    elif osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(EINTR)]:
      server.disconnect()
      return # Retryable OS conditions retain exactly the current assembly.
  if server.output.len != 0:
    var flags = 0.cint
    when not defined(macosx): flags = NoSignal # Linux suppresses SIGPIPE per send.
    let count = min(IoBytes, server.output.len-server.offset)
    let sent = sendBytes(server.connection, addr server.output[server.offset], csize_t(count), flags)
    if sent > 0:
      server.offset += sent
      if server.offset == server.output.len:
        server.output = @[]
        server.offset = 0
        server.deadline = now+int64(server.config.timeoutMs) # Only a complete exchange starts a fresh deadline.
    elif sent == 0 or osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK),
        OSErrorCode(EINTR)]:
      server.disconnect() # Broken pipes close locally without process-wide signals.
