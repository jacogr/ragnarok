# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local HTTP management over a permission-controlled Unix domain socket.
##
## The owned private parent directory and mode-0600 socket form the authorization
## boundary. Existing paths are refused, and cleanup compares device and inode before
## unlinking so a replacement endpoint survives. The operator supplies trusted ancestry.
##
## One request per connection, fixed byte ceilings, and absolute deadlines bound
## dispatcher work. Reject ambiguous framing before entering the private registry.
## Only copied startup and resource observations cross into management dispatch.

import std/[nativesocket, oserrors, strutils]
import std/posix/posix
import ../lib/[socket_io, http_stream, logging]
import std/http/httpmsg as http_msg
import std/http/httpparse as http_parse
import ./[protocol, file_status, resources]
import ../lib/utf8

const
  MaxConnections = 4
  MaxHeader = http_parse.MaxHeadLen
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
  Connection = object                   ## Each slot owns bounded bytes and one nonblocking descriptor.
    opened: bool
    stream: HttpStream
    input, output: string
    headScanner: http_parse.HeadScanner # Resumes the stock scan across partial reads.
  ManagementServer* = object        ## Non-copyable local listener; an empty configuration opens nothing.
    logger: LogWriter
    httpTags: nil http_msg.HttpTags # One vocabulary for this listener’s synchronous parses.
    opened, bound: bool
    fd: cint
    path: string
    identity: FileStatus
    info: ManagementInfo
    resources: ResourceSampler
    connections: array[MaxConnections, Connection]

proc effectiveUid(): uint32 {.importc: "geteuid", header: "<unistd.h>".}
  ## The parent directory must belong to this effective OS user.

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Process identity is available only through the management schema.

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

proc `=wasMoved`*(server: var ManagementServer) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  server.opened = false
  server.bound = false
  server.fd = -1
  `=wasMoved`(server.path)
  `=wasMoved`(server.info)
  `=wasMoved`(server.resources)
  # Generated object/array hooks clear managed bytes but leave scalar descriptor flags intact.
  `=wasMoved`(server.httpTags)
  `=wasMoved`(server.connections)
  for slot in mitems(server.connections):
    # Clear moved-from slot flags without retiring resources transferred to the destination.
    slot.opened = false

proc `=destroy`*(server: ManagementServer) =
  ## Partial startup and normal ARC retirement close every native and dynamic owner.
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  `=destroy`(server.httpTags)
  `=destroy`(server.connections)
  `=destroy`(server.resources)
  `=destroy`(server.info)
  `=destroy`(server.path)

proc close(slot: var Connection) =
  ## Slot reuse retires both the native handle and every retained request byte.
  slot = default(Connection)

proc close*(server: var ManagementServer) =
  ## Repeated shutdown is harmless; only an owned pathname may be removed.
  for slot in mitems(server.connections):
    slot.stream.close(server.logger, "Management RPC")
    slot.close() # Consumers retire before the listener.
  if server.opened: discard posix.close(server.fd)
  server.removeSocket()
  server.httpTags = nil # Release the vocabulary after closing request slots.
  server.opened = false
  server.logger = default(LogWriter)
  server.bound = false
  server.path = ""
  server.resources.close()
  server.info = default(ManagementInfo)

proc start*(server: var ManagementServer, path: string, info: ManagementInfo, logger = default(
    LogWriter)): bool =
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
  server.logger = logger
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

proc process(slot: var Connection, tags: http_msg.HttpTags, info: ManagementInfo) =
  ## Parse stock HTTP POST / with one explicit length; no upgrade, chunking or pipelining.
  ## The stock parser validates head syntax. This routine owns endpoint, unique
  ## application selectors, body limits and dispatch into the private registry.
  let headBytes = slot.headScanner.findHeadEnd(toOpenArray(slot.input, 0, slot.input.len - 1))
  if headBytes == http_parse.ParseIncomplete: return
  if headBytes < 0:
    slot.output = response("431 Request Header Fields Too Large")
    return # Upstream scanning owns incomplete and oversized head handling.
  slot.output = response("400 Bad Request")
  # The request message retires on return. The listener keeps the vocabulary for later requests.
  var head = http_msg.initHttpMsg(tags)
  if http_parse.parseRequestHead(toOpenArray(slot.input, 0, headBytes - 1), head) !=
      headBytes: return
  for field in ["host", "content-type"]:
    if head.countHeaderByName(field) > 1: return # Application selectors must be unambiguous.
  if head.methodOf != http_msg.tag(http_msg.mPost) or head.target != "/":
    slot.output = response("405 Method Not Allowed")
    return # Public WS methods and other HTTP routes acquire no management authority.
  if head.getStr(http_msg.hHost).len == 0: return
  for forbidden in ["origin", "transfer-encoding", "upgrade", "expect", "content-encoding"]:
    if head.countHeaderByName(forbidden) > 0: return # Browser and alternate body transports are refused.
  let contentType = head.getStr(http_msg.hContentType).toLowerAscii()
  let length = head.contentLength
  if contentType notin ["application/json", "application/json; charset=utf-8"] or length < 0: return
  if length > MaxManagementBody:
    slot.output = response("413 Content Too Large")
    return
  let total = headBytes + length # Both operands have already been bounded independently.
  if slot.input.len > total: return # No pipelined suffix is interpreted as another request.
  if slot.input.len < total:
    slot.output = ""
    return # A bounded partial body waits only until its original connection deadline.
  let body = if length == 0: "" else: slot.input.substr(headBytes, total - 1)
  let reply = respond(body, info)
  slot.output = response(if reply.len == 0: "204 No Content" else: "200 OK", reply)
  slot.input = "" # No parser token or input borrow survives this synchronous call.

proc tick*(server: var ManagementServer) =
  ## Accept once, then dispatch bounded byte handoffs under each connection’s fixed deadline.
  if not server.opened: return
  server.resources.tick() # Scalar/path observations remain independent of every canonical lease.
  server.info.resources = server.resources.snapshot()
  let existingTags = server.httpTags
  let tags: http_msg.HttpTags =
    if existingTags != nil:
      existingTags # A running listener reuses its vocabulary.
    else:
      let vocabulary = http_msg.newHttpTags()
      server.httpTags = vocabulary # Seed the vocabulary once before serving requests.
      vocabulary
  pollHttpStreams()
  let accepted = acceptSocket(server.fd, nil, nil)
  if accepted >= 0:
    var free = -1
    for index in 0..<MaxConnections:
      if not server.connections[index].opened:
        free = index
        break # Capacity is fixed independently of public WS/UI connections.
    if free < 0:
      discard posix.close(accepted)
      log(server.logger, LogTarget.Rpc, LogLevel.Debug, "Management RPC connection refused at capacity")
    elif not nonblocking(accepted):
      let error = osLastError()
      discard posix.close(accepted)
      log(server.logger, LogTarget.Rpc, LogLevel.Warn, "Management RPC connection setup failed: " &
          $int32(error))
    else:
      server.connections[free].opened = true
      server.connections[free].stream.start(accepted, MaxInput)
      log(server.logger, LogTarget.Rpc, LogLevel.Info, "Management RPC connection accepted")
  else:
    let error = osLastError()
    if not retryableSocketError(error):
      log(server.logger, LogTarget.Rpc, LogLevel.Warn, "Management RPC accept failed: " & $int32(error))
  for slot in mitems(server.connections):
    # Retire finished workers before inspecting application state or reusing the slot.
    if not slot.opened: continue
    if slot.stream.finished:
      slot.stream.close(server.logger, "Management RPC")
      slot.close()
      continue
    if slot.stream.expired:
      slot.stream.stop() # The I/O task retires its halves before slot reuse.
      continue
    if not slot.stream.canSend: continue
    if slot.output.len == 0 and slot.stream.receiveChunk(slot.input):
      slot.process(tags, server.info)
      if not slot.opened: continue
      if slot.output.len == 0:
        let available = MaxInput - slot.input.len
        if available > 0: slot.stream.requestChunk(available)
        else: slot.close()
        continue
      logHttpResponse(server.logger, "Management RPC", slot.output)
    if slot.opened and slot.output.len > 0:
      slot.stream.sendChunk(slot.output, true)
