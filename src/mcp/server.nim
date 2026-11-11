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

import std/[nativesocket, oserrors, strutils]
import std/posix/posix
import ../lib/[socket_io, http_stream, logging]
import std/http/httpmsg as http_msg
import std/http/httpparse as http_parse
import ./protocol

const
  MaxConnections = 4

type
  Connection = object ## One bounded request/response and an absolute five-second deadline.
    opened: bool
    stream: HttpStream
    input, output: string
  McpServer* = object               ## Native socket owner retains no canonical state or query contexts.
    logger: LogWriter
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
    # Clear moved-from slot flags without retiring resources transferred to the destination.
    slot.opened = false

proc `=destroy`*(server: McpServer) =
  ## Retire partial startup and accepted sockets before releasing serialized storage.
  if server.opened: discard posix.close(server.fd)
  `=destroy`(server.httpTags)
  `=destroy`(server.connections)

proc close(slot: var Connection) =
  ## A reused slot never inherits request bytes or an output offset.
  slot = default(Connection)

proc close*(server: var McpServer) =
  ## Idempotent explicit shutdown retires consumers before the listener.
  for slot in mitems(server.connections):
    slot.stream.close(server.logger, "MCP")
    slot.close()
  if server.opened: discard posix.close(server.fd)
  server.httpTags = nil # Release the vocabulary after closing request slots.
  server.opened = false
  server.logger = default(LogWriter)
  server.port = 0

func enabled*(server: McpServer): bool =
  ## Scalar observation is safe even while canonical graph workers run.
  server.opened

proc start*(server: var McpServer, port: uint16, logger = default(LogWriter)): bool =
  ## Port zero opens nothing; every enabled listener binds only IPv4 loopback.
  if server.opened: return false
  if port == 0: return true
  server.fd = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if server.fd < 0:
    return false
  server.logger = logger
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

proc processHead(slot: var Connection, tags: http_msg.HttpTags, headBytes: int, port: uint16): int =
  ## Validate the complete head while its parser tokens and tags remain local.
  ## A nonnegative result authorizes exactly that many body bytes.
  result = -1
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
  slot.output = ""
  length

proc processBody(slot: var Connection, body: string, hasSuffix: bool, context: QueryContext) =
  ## Dispatch only a complete authorized body against this turn's context.
  if hasSuffix:
    slot.output = response("400 Bad Request")
    return
  let reply = respond(body, context)
  slot.output = response(if reply.len == 0: "202 Accepted" else: "200 OK", reply)

proc tick*(server: var McpServer, context: QueryContext) =
  ## Accept once, then dispatch bounded byte handoffs under each connection’s fixed deadline.
  if not server.opened: return
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
      log(server.logger, LogTarget.Rpc, LogLevel.Debug, "MCP connection refused at capacity")
    elif not nonblocking(accepted):
      let error = osLastError()
      discard posix.close(accepted)
      log(server.logger, LogTarget.Rpc, LogLevel.Warn, "MCP connection setup failed: " & $int32(error))
    else:
      server.connections[free].opened = true
      server.connections[free].stream.start(accepted, maxBodyBytes = MaxMcpBody)
      log(server.logger, LogTarget.Rpc, LogLevel.Info, "MCP connection accepted")
  else:
    let error = osLastError()
    if not retryableSocketError(error):
      log(server.logger, LogTarget.Rpc, LogLevel.Warn, "MCP accept failed: " & $int32(error))
  for slot in mitems(server.connections):
    # Retire finished workers before inspecting application state or reusing the slot.
    if not slot.opened: continue
    if slot.stream.finished:
      slot.stream.close(server.logger, "MCP")
      slot.close()
      continue
    if slot.stream.expired:
      slot.stream.stop() # The I/O task retires its halves before slot reuse.
      continue
    if not slot.stream.canSend: continue
    if slot.output.len == 0:
      let headBytes = slot.stream.receiveHead(slot.input)
      if headBytes != http_parse.ParseIncomplete:
        let length = slot.processHead(tags, headBytes, server.port)
        slot.input = ""
        if length >= 0:
          slot.stream.requestBody(length)
          continue
      else:
        var body = ""
        var hasSuffix = false
        if not slot.stream.receiveBody(body, hasSuffix): continue
        slot.processBody(body, hasSuffix, context)
      logHttpResponse(server.logger, "MCP", slot.output)
    if slot.opened and slot.output.len > 0:
      slot.stream.sendChunk(slot.output, true)
