# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent registry, strict HTTP boundaries and real private local-socket lifecycle checks.
import std/[assertions, syncio]
import ../../../src/rpc/protocol as public_protocol
include ../../../src/management/server

proc connectSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## The test connects a real AF_UNIX consumer rather than bypassing listener admission.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bound native scheduling waits without an unbounded blocking receive.

proc packet(body: string): string =
  ## Construct independent HTTP framing with the exact encoded body length.
  "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: " &
    $body.len & "\r\n\r\n" & body

let admin = ManagementInfo(role: "validator", chainPath: "/private/chain.json",
  databasePath: "/private/db", stateEnabled: true)
let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ragnarok_unsafe_clientInfo\"}"
let good = respond(request, admin)
assert "\"chainPath\":\"/private/chain.json\"" in good
assert "\"databasePath\":\"/private/db\"" in good
assert "\"result\"" in good and "\"id\":1" in good
for name in ["ragnarok_clientInfo", "bestBlock", "subscribeBestBlock",
    "ragnarok_requestStateProof"]:
  let reply = respond("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"" & name & "\"}", admin)
  assert "-32601" in reply # The management registry cannot reach any public method.
let publicInfo = ClientInfo(role: "server")
assert "-32601" in public_protocol.respond(request, publicInfo) # WS cannot reach management.
for suffix in ["[]", "{}"]:
  assert "\"result\"" in respond(request.substr(0, request.len - 2) & ",\"params\":" & suffix & "}", admin)
assert "-32602" in respond(request.substr(0, request.len - 2) & ",\"params\":[1]}", admin)
for bad in ["", "{", request & "{}", "{\"jsonrpc\":\"2.0\",}", "\xff", "[1,]", "/*x*/{}"]:
  assert "-32700" in respond(bad, admin) # Strict shared lexical policy rejects permissive parser extensions.
for bad in ["[]", "true", "{\"jsonrpc\":\"2.0\",\"method\":\"x\",\"method\":\"y\"}"]:
  assert "-32600" in respond(bad, admin) # Empty batches and ambiguous envelopes do not dispatch.
assert respond("{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_unsafe_clientInfo\"}", admin) == ""
assert "\"result\"" in respond("[" & request & ",true]", admin)
assert "-32600" in respond("[" & request & ",true]", admin)
assert "-32700" in respond(repeat(' ', MaxManagementBody + 1), admin)
assert "Response budget exceeded" in respond(request, ManagementInfo(chainPath: repeat('x', 10000)))

# Parser-level negative witnesses do not depend on socket packet coalescing.
for head in ["GET / HTTP/1.1\r\nHost: x\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: x\r\nOrigin: http://localhost\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n\r\n",
    "POST / HTTP/1.1\r\nHost: x\r\n Content-Length: 0\r\n\r\n",
    packet(request) & packet(request)]:
  var slot = Connection(input: head)
  slot.process(admin)
  assert "200 OK" notin slot.output and "\"result\"" notin slot.output
var partial = Connection(input: packet(request).substr(0, packet(request).len - 2))
partial.process(admin)
assert partial.output.len == 0 # Partial bodies cannot dispatch.
partial.input.add('}')
partial.process(admin)
assert "200 OK" in partial.output
var capped = Connection(input: "POST / HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 8193\r\n\r\n")
capped.process(admin)
assert "413" in capped.output

var directory = "/tmp/ragnarok-management-" & $processId()
var path = directory & "/admin.sock"
assert mkdir(directory.toCString(), Mode(0o700)) == 0
block lifecycle:
  var listener = default(ManagementServer)
  assert listener.start("", admin) and not listener.opened # Default activation opens nothing.
  assert not listener.start("relative.sock", admin)
  assert not listener.start("/tmp/unsafe-management.sock", admin) # Shared parent directories are refused.
  assert listener.start(path, admin)
  var mode = default(Stat)
  assert lstat(path.toCString(), mode) == 0 and (uint32(mode.st_mode) and 0o777'u32) == 0o600
  var second = default(ManagementServer)
  assert not second.start(path, admin) # A competing bind never removes the live pathname.
  assert lstat(path.toCString(), mode) == 0
  let peer = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert peer >= 0
  var destination = default(LocalAddress)
  destination.sun_family = typeof(destination.sun_family)(ord(nativesocket.AF_UNIX))
  when defined(macosx): destination.sun_len = uint8(sizeof(destination)) # Native test endpoint follows host ABI.
  for index, c in path: destination.sun_path[index] = c
  assert connectSocket(peer, addr destination, SockLen(sizeof(destination))) == 0
  assert nonblocking(peer)
  var wire = packet(request)
  assert sendBytes(peer, wire.toCString(), csize_t(wire.len), 0) == wire.len
  var output = ""
  for attempt in 0..<200:
    listener.tick()
    var bytes = default(array[16384, char])
    let count = receive(peer, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: output.add(bytes[index]) # Read only the initialized native extent.
    elif count == 0: break # A fully drained one-shot response closes its consumer.
    discard pauseMicros(1000)
  assert "HTTP/1.1 200 OK" in output and "Cache-Control: no-store" in output
  assert "\"pid\":" & $processId() in output and "\"result\"" in output
  discard posix.close(peer)
  listener.close()
  listener.close() # Explicit close is idempotent and permits a new lifetime.
  assert lstat(path.toCString(), mode) != 0
  assert listener.start(path, admin)
# Destructor cleanup also removes the owned socket without explicit close.
var gone = default(Stat)
assert lstat(path.toCString(), gone) != 0
assert rmdir(directory.toCString()) == 0

echo "Management HTTP tests passed"
