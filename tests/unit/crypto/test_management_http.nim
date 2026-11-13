# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent registry, strict HTTP boundaries and real private local-socket lifecycle checks.

import std/[assertions, syncio]
import ../../../src/rpc/protocol as public_protocol
from ../../../src/lib/stop_signal import ignorePipeSignal
include ../../../src/management/server

proc process(slot: var Connection, tags: http_msg.HttpTags, info: ManagementInfo) =
  ## Run the same header and body policy against an in-memory wire fixture.
  var scanner = default(http_parse.HeadScanner)
  let headBytes = scanner.findHeadEnd(toOpenArray(slot.input, 0, slot.input.len - 1))
  if headBytes == http_parse.ParseIncomplete: return
  let length = slot.processHead(tags, headBytes)
  if length >= 0 and slot.input.len >= headBytes + length:
    let total = headBytes + length
    let body = if length == 0: "" else: slot.input.substr(headBytes, total - 1)
    slot.processBody(body, slot.input.len > total, info)
    slot.input = ""

let requestTags = http_msg.newHttpTags() # Share the listener vocabulary across fixture requests.

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
  slot.process(requestTags, admin)
  assert "200 OK" notin slot.output and "\"result\"" notin slot.output
var partial = Connection(input: packet(request).substr(0, packet(request).len - 2))
partial.process(requestTags, admin)
assert partial.output.len == 0 # Partial bodies cannot dispatch.
partial.input.add('}')
partial.process(requestTags, admin)
assert "200 OK" in partial.output
var capped = Connection(input: "POST / HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 8193\r\n\r\n")
capped.process(requestTags, admin)
assert "413" in capped.output
# The stock parser rejects unsupported whitespace before application dispatch.
for extra in ["X-Client: a\tb\r\n"]:
  var refused = Connection(input: packet(request).replace("Content-Length:", extra &
      "Content-Length:"))
  refused.process(requestTags, admin)
  assert "400 Bad Request" in refused.output
var normalized = Connection(input: packet(request).replace("Content-Length: " & $request.len,
  "Content-Length: 000000" & $request.len))
normalized.process(requestTags, admin)
assert "200 OK" in normalized.output
for wire in [packet(request).replace("\r\n", "\n"),
    packet(request).replace("HTTP/1.1", "HTTP/1.0"),
    packet(request).replace("Content-Length:", "X-Client: a\r\nx-client: b\r\nContent-Length:")]:
  # Stock grammar owns framing and ordinary repeated fields; management authorization stays separate.
  var accepted = Connection(input: wire)
  accepted.process(requestTags, admin)
  assert "200 OK" in accepted.output

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
  let wire = packet(request)
  var first = wire.substr(0, wire.len - 3)
  assert sendBytes(peer, first.toCString(), csize_t(first.len), 0) == first.len
  var octet = '\0'
  for attempt in 0..<20:
    # The head and partial body arrive together, but dispatch must wait for the authorized extent.
    listener.tick()
    assert receive(peer, addr octet, 1, 0) < 0
    discard pauseMicros(1000)
  var tail = wire.substr(first.len)
  assert sendBytes(peer, tail.toCString(), csize_t(tail.len), 0) == tail.len
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
  # The client can see EOF before the dispatcher observes the worker's completion.
  for attempt in 0..<1000:
    listener.tick()
    if not listener.connections[0].opened: break
    discard pauseMicros(1000)
  assert not listener.connections[0].opened, "response worker retires before filling idle slots"
  # Expect is refused from the head even when the client has withheld the body.
  let rejected = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert rejected >= 0 and connectSocket(rejected, addr destination, SockLen(sizeof(
      destination))) == 0
  assert nonblocking(rejected)
  var expectHead = "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 64\r\nExpect: 100-continue\r\n\r\n"
  assert sendBytes(rejected, expectHead.toCString(), csize_t(expectHead.len), 0) == expectHead.len
  output = ""
  for attempt in 0..<200:
    listener.tick()
    var bytes = default(array[512, char])
    let count = receive(rejected, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: output.add(bytes[index])
    elif count == 0: break
    discard pauseMicros(1000)
  assert output.startsWith("HTTP/1.1 400 Bad Request")
  discard posix.close(rejected)
  for attempt in 0..<1000:
    listener.tick()
    if not listener.connections[0].opened: break
    discard pauseMicros(1000)
  assert not listener.connections[0].opened

  # Capacity and absolute timeout retirement use real idle consumers, independently of JSON parsing.
  var idle = default(array[5, cint])
  for index in 0..<idle.len:
    idle[index] = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
    assert idle[index] >= 0
    assert connectSocket(idle[index], addr destination, SockLen(sizeof(destination))) == 0
    listener.tick() # The fifth admission is closed while four existing idle slots remain owned.
  var active = 0
  for slot in mitems(listener.connections):
    if slot.opened:
      inc active
  assert active == 4, "four idle management clients occupy the slots"
  for attempt in 0..<6000:
    listener.tick()
    var remaining = false
    for slot in listener.connections:
      if slot.opened: remaining = true
    if not remaining: break
    discard pauseMicros(1000)
  for slot in listener.connections: assert not slot.opened, "idle management stream expires"
  for peer in idle: discard posix.close(peer)
  assert unlink(path.toCString()) == 0
  let replacement = posix.open(path.toCString(), O_CREAT or O_EXCL or O_WRONLY, Mode(0o600))
  assert replacement >= 0 and posix.close(replacement) == 0
  listener.close()
  assert lstat(path.toCString(), mode) == 0 and S_ISREG(mode.st_mode) # Replacement inodes are never removed.
  assert unlink(path.toCString()) == 0
  listener.close() # Explicit close is idempotent and permits a new lifetime.
  assert lstat(path.toCString(), mode) != 0
  assert listener.start(path, admin)
  # Moving a bound Unix listener transfers pathname cleanup as well as its descriptor.
  var relocated = move(listener)
  assert not listener.opened and not listener.bound
  listener.close()
  assert lstat(path.toCString(), mode) == 0 and S_ISSOCK(mode.st_mode)
  relocated.close()
  assert lstat(path.toCString(), mode) != 0
  assert listener.start(path, admin)
# Destructor cleanup also removes the owned socket without explicit close.
var gone = default(Stat)
assert lstat(path.toCString(), gone) != 0
assert rmdir(directory.toCString()) == 0

echo "Management HTTP tests passed"

# Moving the listener transfers descriptor cleanup to its destination.
block moved_owner:
  var destination = default(ManagementServer)
  block:
    var source = default(ManagementServer)
    source.fd = posix.open("/dev/null", O_RDONLY)
    assert source.fd >= 0
    source.opened = true
    source.connections[0].input = "owned request bytes"
    destination = move(source)
    assert not source.opened and not source.connections[0].opened
    source.close()
    # Reusing the source must neither retire the destination nor inherit its request storage.
    assert source.connections[0].input.len == 0
    source.fd = posix.open("/dev/null", O_RDONLY)
    assert source.fd >= 0
    source.opened = true
    source.close()
  # Source destruction has run; both transferred descriptor identities still belong to destination.
  assert fcntl(destination.fd, F_GETFL) >= 0
  assert destination.connections[0].input == "owned request bytes"
  destination.close()

proc disconnectedPair(domain, kind, protocol: cint, fds: pointer): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Give the stock writer a local peer whose lifetime the test controls.

proc collectStreamLog(context: nil pointer, batch: string) {.raises: [].} =
  ## The logger is the only writer until close joins its sink thread.
  cast[ptr string](context)[].add(batch)

block disconnectedWriter:
  assert ignorePipeSignal() # Match the executable’s Linux writer policy.
  # Close the peer after the reader has handed off its request, before the writer runs.
  var pair = default(array[2, cint])
  assert disconnectedPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
      0, addr pair[0]) == 0
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  var stream = default(HttpStream)
  assert stream.start(pair[0])
  var request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  assert sendBytes(pair[1], request.toCString(), csize_t(request.len), 0) == request.len
  var input = ""
  for attempt in 0..<1000:
    pollHttpStreams()
    if stream.receiveHead(input) == request.len: break
    discard pauseMicros(1000)
  assert input == request
  assert posix.close(pair[1]) == 0
  var reply = "response"
  stream.sendChunk(reply, true)
  for attempt in 0..<1000:
    pollHttpStreams()
    if stream.finished: break
    discard pauseMicros(1000)
  assert stream.finished, "disconnected stock writer retires without terminating the process"
  var messages = ""
  var logger = default(Logger)
  assert logger.start(initLogPolicy(LogLevel.Info), collectStreamLog, addr messages)
  stream.close(logger.writer, "Management RPC")
  logger.close()
  assert "Management RPC stream write ended:" in messages
  assert "connection retired" notin messages # Trace output follows the configured filter.

block refusedBody:
  var pair = default(array[2, cint])
  assert disconnectedPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
      0, addr pair[0]) == 0
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  var stream = default(HttpStream)
  assert not stream.start(pair[0], maxBodyBytes = -1)
  assert stream.start(pair[0], maxBodyBytes = 1)
  var wire = "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n"
  assert sendBytes(pair[1], wire.toCString(), csize_t(wire.len), 0) == wire.len
  var head = ""
  for attempt in 0..<1000:
    pollHttpStreams()
    if stream.receiveHead(head) == wire.len: break
    discard pauseMicros(1000)
  assert head == wire
  stream.requestBody(2)
  for attempt in 0..<1000:
    pollHttpStreams()
    if stream.finished: break
    discard pauseMicros(1000)
  assert stream.finished, "over-limit body retires only this connection"
  assert posix.close(pair[1]) == 0

block expiredRequest:
  # Park a complete request in a real management slot until its deadline passes.
  var pair = default(array[2, cint])
  assert disconnectedPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)),
      0, addr pair[0]) == 0
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  var wire = packet(request)
  assert sendBytes(pair[1], wire.toCString(), csize_t(wire.len), 0) == wire.len
  var listener = default(ManagementServer)
  # A pipe-like fixture keeps accept separate from the already admitted socket.
  listener.fd = socket(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert listener.fd >= 0 and nonblocking(listener.fd)
  listener.opened = true
  listener.info = admin
  listener.connections[0].opened = true
  assert listener.connections[0].stream.start(pair[0], timeoutMs = 200)
  for attempt in 0..<150:
    pollHttpStreams()
    if listener.connections[0].stream.canSend: break
    discard pauseMicros(1000)
  assert listener.connections[0].stream.canSend, "request reaches the dispatcher mailbox"
  for attempt in 0..<1000:
    if listener.connections[0].stream.expired: break
    discard pauseMicros(1000)
  assert listener.connections[0].stream.expired
  listener.tick()
  assert listener.connections[0].input.len == 0 and listener.connections[0].output.len == 0
  listener.close()
  var octet = '\0'
  assert receive(pair[1], addr octet, 1, 0) == 0, "expired request closes without a response"
  discard posix.close(pair[1])
