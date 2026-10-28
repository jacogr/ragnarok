# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed MCP registry, stateless lifecycle, bounded HTTP framing and actual loopback request exchange.
import std/[assertions, syncio, base64]
import ../../../src/mcp/protocol
import ../../../src/rpc/protocol as rpc
import ../../../src/chain/[parameters, genesis, provider]
import ../../../src/lib/json_writer
import ../../support/rpc_socket as sockets
import ../../support/mcp_context
include ../../../src/mcp/server

proc request(methodName: string, params = "{}", id = "1"): string =
  ## Independent wire authoring keeps malformed-envelope tests outside the production encoder.
  "{\"jsonrpc\":\"2.0\",\"id\":" & id & ",\"method\":\"" & methodName & "\",\"params\":" & params & "}"
proc call(name: string, arguments = "{}"): string =
  ## Author a fixed MCP tool call with explicit named arguments.
  request("tools/call", "{\"name\":\"" & name & "\",\"arguments\":" & arguments & "}")
proc http(body: string, port = 14141'u16, extra = ""): string =
  ## Include both standard MCP response media types and exact byte framing.
  "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:" & $port &
    "\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\n" &
    extra & "Content-Length: " & $body.len & "\r\n\r\n" & body
proc processed(packet: string): string =
  ## Pure HTTP processing never opens a socket and returns the fully serialized response.
  var slot = Connection(input: packet)
  let context = default(QueryContext)
  slot.process(14141, context)
  slot.output

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## A short bounded pause lets the local nonblocking socket drain.

let empty = default(QueryContext)
var busy = default(QueryContext)
busy.busy = true
let init = request("initialize", "{\"protocolVersion\":\"future\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}")
assert "\"protocolVersion\":\"2025-11-25\"" in respond(init, empty)
assert "-32602" in respond(request("initialize"), empty)
assert respond("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}", empty) == ""
assert "\"result\":{}" in respond(request("ping", id = "\"α\""), empty)
assert "get_storage" in respond(request("tools/list"), empty)
assert "readOnlyHint" in respond(request("tools/list"), empty)
assert "-32602" in respond(request("tools/list", "{\"cursor\":\"invalid\"}"), empty)
for wire in ["[]", "null", "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}"]:
  assert "-32600" in respond(wire, empty) # Batches and wrong-version messages cannot enter tool dispatch.
for wire in ["{", "{\"x\":1,\"x\":2}", "\xff", repeat("x", MaxMcpBody+1)]:
  assert "-32700" in respond(wire, empty) # Reject invalid UTF-8, duplicate fields and oversized input.
assert "-32601" in respond(request("arbitrary_rpc"), empty)
assert "-32602" in respond(call("state_set"), empty)
assert "-32602" in respond(call("get_block"), empty)
assert "-32602" in respond(call("get_chain_status", "{\"extra\":1}"), empty)
assert "\"isError\":true" in respond(call("get_parameters"), empty)
assert "retryable" in respond(call("get_parameters"), busy)
assert "\"result\":{}" in respond(request("ping"), busy)

# Independently retained fixture verifies actual chain queries and precision-preserving output.
let text = mcpChainText()
let params = rpc.configuredParameters(text)
assert params.ok
let seed = rpc.configuredGenesis(text, params.value)
assert seed.error == GenesisError.None
let info = rpc.ClientInfo(parameters: params, chain: genesisView(seed), identity: rpc.chainIdentity(
    seed), peers: 3)
let context = QueryContext(info: info)
let hash = base64.encode(array[32, byte](seed.value.blockHash))
let selector = "{\"block_hash\":" & $json(hash) & "}"
let root = base64.encode(array[32, byte](seed.value.stateRoot))
let rootAnswer = respond(call("get_block", selector), context)
assert root in rootAnswer and "\"isError\":false" in rootAnswer
assert "genesisHash" in rootAnswer and hash in rootAnswer
assert "18446744073709551615" in respond(call("get_parameters"), context)
assert "\"connectedPeers\":\"3\"" in respond(call("get_chain_status"), context)
assert "\"finalizedBlock\":null" in respond(call("get_chain_status"), context)
assert "\"transport\"" notin respond(call("get_chain_status"), context)
assert "\"isError\":false" in respond(call("list_services", selector), context)
assert "\"value\":null" in respond(call("get_service", selector.replace("}",
    ",\"service_id\":42}")), context)
for invalid in ["-1", "4294967296", "1.5", "1e1", "\"42\""]:
  let arguments = selector.replace("}", ",\"service_id\":" & invalid & "}")
  let answer = respond(call("get_service", arguments), context)
  assert "\"isError\":true" in answer or "-32602" in answer
assert "\"isError\":true" in respond(call("get_block", "{\"block_hash\":\"bad\"}"), context)

# Strict HTTP boundaries refuse cross-origin access, DNS aliases, ambiguity and protocol mismatches.
let ping = request("ping")
assert "200 OK" in processed(http(ping))
assert "202 Accepted" in processed(http("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"))
assert "403 Forbidden" in processed(http(ping, extra = "Origin: https://evil.example\r\n"))
assert "403 Forbidden" in processed(http(ping).replace("127.0.0.1:14141", "evil.example:14141"))
assert "400 Bad Request" in processed(http(ping, extra = "MCP-Protocol-Version: unknown\r\n"))
assert "200 OK" in processed(http(ping, extra = "MCP-Protocol-Version: 2025-11-25\r\n"))
assert "400 Bad Request" in processed(http(ping, extra = "Transfer-Encoding: chunked\r\n"))
assert "400 Bad Request" in processed(http(ping, extra = "Content-Length: 1\r\n"))
assert "400 Bad Request" in processed(http(ping) & "suffix")
assert "406 Not Acceptable" in processed(http(ping).replace(", text/event-stream", ""))
assert "405 Method Not Allowed" in processed(http(ping).replace("POST", "GET"))
assert processed(http(ping).substr(0, http(ping).len-2)) == ""
assert "431 Request Header Fields Too Large" in processed(repeat("x", MaxHeader))
assert "413 Content Too Large" in processed(http(repeat("x", MaxMcpBody+1)))

block loopback:
  # The OS selects a free port; all network operations and polls remain bounded.
  let reserved = sockets.reservation()
  let port = reserved.port
  discard posix.close(reserved.fd)
  var server = default(McpServer)
  assert server.start(port)
  var collision = default(McpServer)
  assert not collision.start(port)
  let peer = sockets.client(port)
  sockets.sendText(peer, http(init, port), masked = false)
  var answer = ""
  for attempt in 0..<200:
    server.tick(context)
    var buffer = default(array[8192, char])
    let count = receive(peer, addr buffer[0], csize_t(8192), 0)
    if count > 0:
      for index in 0..<count: answer.add(buffer[index])
    elif count == 0: break # A drained response closes its only request connection.
    discard pauseMicros(1000)
  assert "200 OK" in answer and "2025-11-25" in answer
  discard posix.close(peer)
  server.close()
  server.close()
  assert not server.enabled
  assert server.start(0) and not server.enabled

block boundedConnections:
  # Five admitted TCP clients cannot grow the four-slot owner; the extra descriptor is closed.
  let reserved = sockets.reservation()
  discard posix.close(reserved.fd)
  var server = default(McpServer)
  assert server.start(reserved.port)
  var clients = default(array[5, cint])
  for index in 0..<5:
    clients[index] = sockets.client(reserved.port)
    server.tick(context)
  var opened = 0
  for slot in server.connections:
    if slot.opened: inc opened
  assert opened == MaxConnections, "MCP retains exactly four idle clients"
  var byteBuffer = default(array[1, char])
  var refused = false
  for attempt in 0..<200:
    if receive(clients[4], addr byteBuffer[0], 1, 0) == 0:
      refused = true
      break # The local FIN may become observable after the close syscall returns.
    discard pauseMicros(1000)
  assert refused, "Fifth MCP client closes within the bounded polling allowance"
  # Expiring each slot exercises deadline retirement without sleeping for five wall-clock seconds.
  for slot in mitems(server.connections): slot.deadline = 0
  server.tick(context)
  for slot in server.connections: assert not slot.opened, "Expired MCP slot retires"
  for client in clients: discard posix.close(client)
  server.close()

echo "MCP protocol and HTTP passed"
