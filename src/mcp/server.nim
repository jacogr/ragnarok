# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded loopback Streamable HTTP endpoint. One request per connection; no SSE or HTTP sessions.
## Only serialized bytes survive a tick. Query contexts are borrowed synchronously and never retained.

import std/[nativesocket, oserrors, strutils, monotimes]
import std/posix/posix
import ../lib/socket_io
import ./protocol

const
  MaxConnections = 4
  MaxHeader = 4096
  MaxInput = MaxHeader + MaxMcpBody

type
  Connection = object ## One bounded request/response and an absolute five-second deadline.
    opened: bool
    fd: cint
    input, output: string
    offset: int
    deadline: int64
  McpServer* = object ## Native socket owner retains no canonical state or query contexts.
    opened: bool
    fd: cint
    port: uint16
    connections: array[MaxConnections, Connection]

proc `=copy`*(destination: var McpServer, source: McpServer) {.error: "MCP server owns sockets".}
  ## Descriptor ownership cannot be copied.

proc `=dup`*(source: McpServer): McpServer {.error.}
  ## Implicit duplication cannot duplicate descriptor retirement.

proc `=wasMoved`*(server: var McpServer) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  server.opened = false
  server.fd = -1
  server.port = 0
  # Generated object/array hooks clear managed bytes but leave scalar descriptor flags intact.
  `=wasMoved`(server.connections)
  for slot in mitems(server.connections):
    # Every accepted descriptor belongs to the destination, including streaming files.
    slot.opened = false
    slot.fd = -1

proc `=destroy`*(server: McpServer) =
  ## Retire partial startup and accepted sockets before releasing serialized storage.
  for slot in server.connections:
    if slot.opened: discard posix.close(slot.fd)
  if server.opened: discard posix.close(server.fd)
  `=destroy`(server.connections)

proc close(slot: var Connection) =
  ## A reused slot never inherits request bytes or an output offset.
  if slot.opened: discard posix.close(slot.fd)
  slot = default(Connection)

proc close*(server: var McpServer) =
  ## Idempotent explicit shutdown retires consumers before the listener.
  for slot in mitems(server.connections): slot.close()
  if server.opened: discard posix.close(server.fd)
  server.opened = false
  server.port = 0

func enabled*(server: McpServer): bool =
  ## Scalar observation is safe even while canonical graph workers run.
  server.opened

proc start*(server: var McpServer, port: uint16): bool =
  ## Port zero opens nothing; every enabled listener binds only IPv4 loopback.
  if server.opened: return false
  if port == 0: return true
  server.fd = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if server.fd < 0:
    return false
  server.opened = true
  var reuse = 1.cint
  if setOption(server.fd, SocketLevel, ReuseAddress, addr reuse, SockLen(sizeof(reuse))) != 0:
    server.close()
    return false # HTTP response TIME_WAIT must not prevent an immediate listener restart.
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
  server.port = port
  true

proc response(status: string, body = "", extra = ""): string =
  ## No caching, ambient browser authorization or persistent connection state.
  "HTTP/1.1 " & status & "\r\nContent-Type: application/json\r\nContent-Length: " & $body.len &
    "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" &
        extra & "\r\n" & body

proc process(slot: var Connection, port: uint16, context: QueryContext) =
  ## Strict single-message HTTP framing rejects ambiguous lengths, browser origins and upgrades.
  let ending = slot.input.find("\r\n\r\n")
  if ending < 0:
    if slot.input.len >= MaxHeader: slot.output = response("431 Request Header Fields Too Large")
    return
  slot.output = response("400 Bad Request")
  if ending + 4 > MaxHeader: return
  let lines = slot.input.substr(0, ending - 1).split("\r\n")
  if lines.len == 0: return
  var names: seq[string] = @[]
  var host, contentType, acceptsJson, acceptsEvents = false
  var length = -1
  for index in 1..<lines.len:
    let line = lines[index]
    let colon = line.find(':')
    if colon < 1: return
    let name = line.substr(0, colon - 1).toLowerAscii()
    for c in name:
      if c notin {'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_',
          '`', '|', '~'}: return # Whitespace/folding cannot conceal a framing header.
    if name in names: return
    names.add(name)
    let raw = line.substr(colon + 1)
    for c in raw:
      if (ord(c) < 32 and c != '\t') or ord(c) == 127: return
    let value = raw.strip()
    case name
    of "host":
      host = value in ["127.0.0.1:" & $port, "localhost:" & $port]
      if not host:
        slot.output = response("403 Forbidden")
        return # An attacker-controlled DNS alias never acquires local query access.
    of "origin":
      slot.output = response("403 Forbidden")
      return # Initial local-agent policy refuses all browser origins, including opaque/null origins.
    of "content-type": contentType = value.toLowerAscii() in ["application/json", "application/json; charset=utf-8"]
    of "accept":
      for media in value.toLowerAscii().split(','):
        let kind = media.strip()
        if kind == "application/json": acceptsJson = true
        if kind == "text/event-stream": acceptsEvents = true
    of "mcp-protocol-version":
      if value != ProtocolVersion: return # Explicit unsupported revisions are HTTP errors before dispatch.
    of "mcp-session-id", "transfer-encoding", "upgrade", "expect", "content-encoding": return
    of "content-length":
      if value.len == 0 or value.len > 5: return
      length = 0
      for c in value:
        if c notin {'0'..'9'}: return
        length = length * 10 + ord(c) - ord('0') # At most five digits, bounded before body arithmetic.
    else: discard # Ordinary extra headers grant no additional capabilities.
  if not host: return
  if lines[0] != "POST /mcp HTTP/1.1":
    slot.output = response("405 Method Not Allowed", extra = "Allow: POST\r\n")
    return # GET deliberately declines the optional standalone SSE stream; DELETE has no session to close.
  if not contentType or length < 0: return
  if not acceptsJson or not acceptsEvents:
    slot.output = response("406 Not Acceptable")
    return
  if length > MaxMcpBody:
    slot.output = response("413 Content Too Large")
    return
  let total = ending + 4 + length
  if slot.input.len > total: return # Pipelined data is never interpreted as a second request.
  if slot.input.len < total:
    slot.output = ""
    return # Partial bodies retain the original absolute deadline.
  let body = if length == 0: "" else: slot.input.substr(ending + 4, total - 1)
  let reply = respond(body, context)
  slot.output = response(if reply.len == 0: "202 Accepted" else: "200 OK", reply)
  slot.input = "" # No request token/context alias survives the synchronous dispatch.

proc tick*(server: var McpServer, context: QueryContext) =
  ## One accept/read/write per slot and a five-second absolute deadline bound each turn.
  if not server.opened: return
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
        slot.process(server.port, context)
      elif count == 0: slot.close()
      elif not retryableSocketError(osLastError()): slot.close()
    if slot.opened and slot.output.len > 0:
      let written = writePending(slot.fd, slot.output, slot.offset)
      if written == WriteComplete:
        slot.close() # One complete reply retires the connection.
      elif written == WriteFailed:
        slot.close() # Permanent errors retire only this service's connection.
