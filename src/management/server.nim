# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional HTTP management listener over a permission-controlled Unix domain socket.
## Four nonblocking slots, fixed request budgets and deadlines bound dispatcher work.
## This listener never imports the public WS method registry or canonical state.

import std/[nativesocket, oserrors, strutils, monotimes]
import std/posix/posix
import ./[protocol, file_status, resources]
import ../lib/utf8

const
  MaxConnections = 4
  MaxHeader = 4096
  MaxInput = MaxHeader + MaxManagementBody

type
  LocalAddress = object
    ## POSIX local address prefix; Linux accepts this shorter bounded pathname extent.
    when defined(macosx):
      sun_len: uint8
      sun_family: uint8
    else:
      sun_family: cushort
    sun_path: array[104, char]
  Connection = object ## Each slot owns bounded bytes and one nonblocking descriptor.
    opened: bool
    fd: cint
    input, output: string
    offset: int
    deadline: int64
  ManagementServer* = object ## Non-copyable local listener; an empty configuration opens nothing.
    opened, bound: bool
    fd: cint
    path: string
    identity: FileStatus
    info: ManagementInfo
    resources: ResourceSampler
    connections: array[MaxConnections, Connection]

proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Open only a local-domain stream descriptor.
proc bindSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
  ## Native bind borrows the initialized pathname only during this syscall.
proc listenSocket(fd, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
  ## Listen only after the private socket permissions have been installed.
proc acceptSocket(fd: cint, address, size: nil pointer): cint {.importc: "accept",
    header: "<sys/socket.h>".}
  ## Admit at most one connection per dispatcher turn.
proc receive(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Read at most the remaining bounded request capacity.
proc sendBytes(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Preserve partial write offsets until the one response drains.
proc effectiveUid(): uint32 {.importc: "geteuid", header: "<unistd.h>".}
  ## The parent directory must belong to this effective OS user.
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Process identity is available only through the management schema.
let
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
when defined(macosx):
  proc setOption(fd, level, option: cint, value: pointer,
      size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
    ## Darwin suppresses SIGPIPE per descriptor.
  let SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint
else:
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint

proc removeSocket(server: ManagementServer) =
  ## Never delete an existing or replacement pathname that this lifetime did not bind.
  if server.bound:
    var current = default(FileStatus)
    var path = server.path # A mutable string owns the terminated native borrow.
    if readStatus(path.toCString(), current) == 0 and S_ISSOCK(Mode(current.st_mode)) and
        current.st_dev == server.identity.st_dev and current.st_ino == server.identity.st_ino:
      discard unlink(path.toCString()) # Device/inode equality confines cleanup to the owned socket.

proc `=copy`*(destination: var ManagementServer, source: ManagementServer) {.error: "ManagementServer owns sockets".}
  ## Copying an aggregate must not duplicate native ownership.
proc `=dup`*(source: ManagementServer): ManagementServer {.error.}
  ## Implicit duplication is forbidden as well as assignment copies.
proc `=destroy`*(server: ManagementServer) =
  ## Partial startup and normal ARC retirement close every native and dynamic owner.
  for slot in server.connections:
    if slot.opened: discard posix.close(slot.fd) # A default slot never closes stdin.
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  `=destroy`(server.connections)
  `=destroy`(server.resources)
  `=destroy`(server.info)
  `=destroy`(server.path)

proc close(slot: var Connection) =
  ## Slot reuse retires both the native handle and every retained request byte.
  if slot.opened: discard posix.close(slot.fd)
  slot = default(Connection)

proc close*(server: var ManagementServer) =
  ## Repeated shutdown is harmless; only an owned pathname may be removed.
  for slot in mitems(server.connections): slot.close() # Consumers retire before the listener.
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  server.opened = false
  server.bound = false
  server.path = ""
  server.resources.close()
  server.info = default(ManagementInfo)

proc nonblocking(fd: cint): bool =
  ## Install nonblocking and close-on-exec before any IO can become visible.
  let flags = fcntl(fd, F_GETFL, 0)
  let descriptorFlags = fcntl(fd, GetFd, 0)
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFd, descriptorFlags or CloseExec) < 0: return false
  when defined(macosx):
    var enabled = 1.cint
    if setOption(fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) != 0:
      return false # Signal suppression is part of successful socket configuration.
  true

proc start*(server: var ManagementServer, path: string, info: ManagementInfo): bool =
  ## Empty disables management. Otherwise require an absolute path in a private existing directory.
  if server.opened or server.bound: return false
  if path.len == 0: return true
  if path.len > 103 or path[0] != '/' or path.endsWith('/') or not validUtf8(path): return false
  for c in path:
    if ord(c) < 32 or ord(c) == 127: return false # No native truncation or control-bearing path is accepted.
  let slash = path.rfind('/')
  var directory = if slash == 0: "/" else: path.substr(0, slash - 1)
  var parent = default(FileStatus)
  if readStatus(directory.toCString(), parent) != 0 or not S_ISDIR(Mode(parent.st_mode)) or
      uint32(parent.st_uid) != effectiveUid() or (uint32(parent.st_mode) and 0o077'u32) != 0:
    return false # Directory protection also covers bind-to-chmod before the socket becomes 0600.
  for text in [info.role, info.chainPath, info.databasePath]:
    if text.len > 1024 or not validUtf8(text): return false # Bound admin metadata before serializing any reply.
  var address = default(LocalAddress)
  address.sun_family = typeof(address.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): address.sun_len = uint8(sizeof(address)) # Darwin carries the native address extent.
  for index, c in path: address.sun_path[index] = c # The initialized final NUL is within the fixed array.
  let fd = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if fd < 0: return false
  server.fd = fd
  server.opened = true
  if not nonblocking(fd) or bindSocket(fd, addr address, SockLen(sizeof(address))) != 0:
    server.close()
    return false # An existing socket/file is refused without unlinking it.
  server.path = path
  var nativePath = path # Nimony terminates a mutable owned string before native calls.
  if readStatus(nativePath.toCString(), server.identity) != 0:
    server.close()
    return false # Without an observed identity cleanup cannot claim pathname ownership.
  server.bound = true
  if chmod(nativePath.toCString(), Mode(0o600)) != 0 or listenSocket(fd, MaxConnections.cint) != 0:
    server.close()
    return false # Partial successful binds retire only their own native socket and inode.
  server.info = info
  server.info.socketPath = path
  server.info.processId = uint32(processId())
  server.info.effectiveUser = effectiveUid()
  server.resources.configure(info.databasePath, directory)
  true

proc response(status, body = ""): string =
  ## Every response closes; admin output must never enter browser caches.
  "HTTP/1.1 " & status & "\r\nContent-Type: application/json\r\nContent-Length: " & $body.len &
    "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n" & body

proc process(slot: var Connection, info: ManagementInfo) =
  ## Parse strict HTTP/1.1 POST / with one explicit length; no upgrade, chunking or pipelining.
  let ending = slot.input.find("\r\n\r\n")
  if ending < 0:
    if slot.input.len >= MaxHeader: slot.output = response("431 Request Header Fields Too Large")
    return
  slot.output = response("400 Bad Request")
  if ending + 4 > MaxHeader: return
  let lines = slot.input.substr(0, ending - 1).split("\r\n")
  if lines[0] != "POST / HTTP/1.1":
    slot.output = response("405 Method Not Allowed")
    return # GET/OPTIONS/WS upgrades never acquire management dispatch authority.
  var names: seq[string] = @[]
  var host, contentType = false
  var length = -1
  for index in 1..<lines.len:
    let line = lines[index]
    let colon = line.find(':')
    if colon < 1: return
    let name = line.substr(0, colon - 1).toLowerAscii()
    for c in name:
      if c notin {'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_',
          '`', '|', '~'}:
        return # Invalid names and folded headers cannot hide framing fields.
    if name in names: return
    names.add(name)
    let raw = line.substr(colon + 1)
    for c in raw:
      if (ord(c) < 32 and c != '\t') or ord(c) == 127: return # Validate before trimming optional whitespace.
    let value = raw.strip()
    case name
    of "host": host = value.len > 0
    of "content-type": contentType = value.toLowerAscii() in ["application/json", "application/json; charset=utf-8"]
    of "origin", "transfer-encoding", "upgrade", "expect",
        "content-encoding": return # Browser and ambiguous body transports are refused.
    of "content-length":
      if value.len == 0 or value.len > 4: return
      length = 0
      for c in value:
        if c notin {'0'..'9'}: return
        length = length * 10 + ord(c) - ord('0') # Four digits cannot overflow; body budget is checked below.
    else: discard # Unknown ordinary headers grant no additional capabilities.
  if not host or not contentType or length < 0: return
  if length > MaxManagementBody:
    slot.output = response("413 Content Too Large")
    return
  let total = ending + 4 + length # Both operands have already been bounded independently.
  if slot.input.len > total: return # No pipelined suffix is interpreted as another request.
  if slot.input.len < total:
    slot.output = ""
    return # A bounded partial body waits only until its original connection deadline.
  let body = if length == 0: "" else: slot.input.substr(ending + 4, total - 1)
  let reply = respond(body, info)
  slot.output = response(if reply.len == 0: "204 No Content" else: "200 OK", reply)
  slot.input = "" # No parser token or input borrow survives this synchronous call.

proc tick*(server: var ManagementServer) =
  ## One accept/read/write per slot and a five-second absolute deadline bound each turn.
  if not server.opened: return
  server.resources.tick() # Scalar/path observations remain independent of every canonical lease.
  server.info.resources = server.resources.snapshot()
  let now = getMonoTime().ticks div 1_000_000
  let accepted = acceptSocket(server.fd, nil, nil)
  if accepted >= 0:
    var free = -1
    for index in 0..<MaxConnections:
      if not server.connections[index].opened:
        free = index
        break # Capacity is fixed independently of public WS/UI connections.
    if free < 0 or not nonblocking(accepted): discard posix.close(accepted)
    else: server.connections[free] = Connection(opened: true, fd: accepted, deadline: now + 5000)
  for slot in mitems(server.connections):
    if slot.opened and now >= slot.deadline: slot.close() # A partial header/body cannot extend its deadline.
    if slot.opened and slot.output.len == 0:
      var bytes = default(array[MaxInput, char])
      let count = receive(slot.fd, addr bytes[0], csize_t(MaxInput - slot.input.len), 0)
      if count > 0:
        for index in 0..<count: slot.input.add(bytes[index]) # Only initialized receive bytes enter owned storage.
        slot.process(server.info)
      elif count == 0: slot.close()
      elif osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(
          EINTR)]: slot.close()
    if slot.opened and slot.output.len > 0:
      var flags = 0.cint
      when not defined(macosx): flags = NoSignal # Linux suppression applies per send.
      let bytes = slot.output.toCString()
      let sent = sendBytes(slot.fd, cast[pointer](cast[uint](bytes) + uint(slot.offset)),
        csize_t(slot.output.len - slot.offset), flags)
      if sent > 0:
        slot.offset += sent
        if slot.offset == slot.output.len: slot.close() # One complete reply retires the connection.
      elif sent == 0 or osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK),
          OSErrorCode(EINTR)]: slot.close()
