# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local Streamable HTTP transport for MCP chain queries.
##
## The listener trusts local processes and binds IPv4 loopback. The accepted Host names
## are the configured loopback address and localhost with the selected port. Rejecting
## Origin-bearing requests keeps browser traffic outside that trust boundary.
##
## POST carries one request per connection. Replies use JSON, with HTTP 202 for valid
## notifications. Clients advertise both JSON and event-stream support for MCP negotiation.
## Connections close after the response and clients can reconnect within the same logical
## lifecycle. Explicit protocol-version headers must match the supported revision.
##
## Fixed slots, byte ceilings and absolute deadlines bound work by each dispatcher turn.
## Only serialized bytes survive a turn, so slow clients cannot extend a query borrow.
## See spec/mcp.md for protocol references and verification.

import std/[nativesocket, oserrors, strutils, monotimes]
import std/posix/posix
import ../lib/socket_io
import std/http/httpmsg as http_msg
import std/http/httpparse as http_parse
import ./protocol

const
  MaxConnections = 4
  MaxHeader = http_parse.MaxHeadLen
  MaxInput = MaxHeader + MaxMcpBody

type
  Connection = object                   ## One bounded request/response and an absolute five-second deadline.
    opened: bool
    fd: cint
    input, output: string
    headScanner: http_parse.HeadScanner # Resumes the stock scan across partial reads.
    offset: int
    deadline: int64
  McpServer* = object               ## Native socket owner retains no canonical state or query contexts.
    httpTags: nil http_msg.HttpTags # One vocabulary for this listener’s synchronous parses.
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
  `=wasMoved`(server.httpTags)
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
  `=destroy`(server.httpTags)
  `=destroy`(server.connections)

proc close(slot: var Connection) =
  ## A reused slot never inherits request bytes or an output offset.
  if slot.opened: discard posix.close(slot.fd)
  slot = default(Connection)

proc close*(server: var McpServer) =
  ## Idempotent explicit shutdown retires consumers before the listener.
  for slot in mitems(server.connections): slot.close()
  if server.opened: discard posix.close(server.fd)
  server.httpTags = nil # Release the vocabulary after closing request slots.
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

proc process(slot: var Connection, tags: http_msg.HttpTags, port: uint16, context: QueryContext) =
  ## Strict single-message HTTP framing rejects ambiguous lengths, browser origins and upgrades.
  ## The stock scanner and parser own syntax and head extent. Keep the parsed
  ## message within this activation, then apply MCP selectors and body policy.
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
  for field in ["host", "content-type", "accept", "mcp-protocol-version"]:
    if head.countHeaderByName(field) > 1: return # Application selectors must be unambiguous.
  let host = head.getStr(http_msg.hHost)
  if host.len == 0: return
  if host notin ["127.0.0.1:" & $port, "localhost:" & $port] or head.contains(http_msg.hOrigin):
    slot.output = response("403 Forbidden")
    return # DNS aliases and browser origins never grant access to the local tool catalog.
  if head.countHeaderByName("mcp-protocol-version") > 0 and
      head.findHeader("mcp-protocol-version") != ProtocolVersion: return
  for forbidden in ["mcp-session-id", "transfer-encoding", "upgrade", "expect", "content-encoding"]:
    if head.countHeaderByName(forbidden) > 0: return # No sessions, alternate body coding or upgrades.
  if head.methodOf != http_msg.tag(http_msg.mPost) or head.target != "/mcp":
    slot.output = response("405 Method Not Allowed", extra = "Allow: POST\r\n")
    return # GET declines the optional SSE stream; DELETE has no retained session to close.
  let contentType = head.getStr(http_msg.hContentType).toLowerAscii()
  let length = head.contentLength
  if contentType notin ["application/json", "application/json; charset=utf-8"] or length < 0: return
  var acceptsJson, acceptsEvents = false
  for media in head.getStr(http_msg.hAccept).toLowerAscii().split(','):
    # Both response media types remain an explicit MCP transport requirement.
    let kind = media.strip()
    if kind == "application/json": acceptsJson = true
    if kind == "text/event-stream": acceptsEvents = true
  if not acceptsJson or not acceptsEvents:
    slot.output = response("406 Not Acceptable")
    return
  if length > MaxMcpBody:
    slot.output = response("413 Content Too Large")
    return
  let total = headBytes + length
  if slot.input.len > total: return # Pipelined data is never interpreted as a second request.
  if slot.input.len < total:
    slot.output = ""
    return # Partial bodies retain the original absolute deadline.
  let body = if length == 0: "" else: slot.input.substr(headBytes, total - 1)
  let reply = respond(body, context)
  slot.output = response(if reply.len == 0: "202 Accepted" else: "200 OK", reply)
  slot.input = "" # No request token/context alias survives the synchronous dispatch.

proc tick*(server: var McpServer, context: QueryContext) =
  ## One accept/read/write per slot and a five-second absolute deadline bound each turn.
  if not server.opened: return
  let existingTags = server.httpTags
  let tags: http_msg.HttpTags =
    if existingTags != nil:
      existingTags # A running listener reuses its vocabulary.
    else:
      let vocabulary = http_msg.newHttpTags()
      server.httpTags = vocabulary # Seed the vocabulary once before serving requests.
      vocabulary
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
        slot.process(tags, server.port, context)
      elif count == 0: slot.close()
      elif not retryableSocketError(osLastError()): slot.close()
    if slot.opened and slot.output.len > 0:
      let written = writePending(slot.fd, slot.output, slot.offset)
      if written == WriteComplete:
        slot.close() # One complete reply retires the connection.
      elif written == WriteFailed:
        slot.close() # Permanent errors retire only this service's connection.
