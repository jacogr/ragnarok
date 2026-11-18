# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise the production RPC listener with independently encoded WebSocket clients.

import std/[assertions, syncio, strutils, base64, ioring, monotimes, atomics]
import std/socket as tcp
import std/posix/posix as posix
import ../../../src/lib/socket_io as native_io
import ../../../src/lib/[http_head, http_stream, logging]
from ../../../src/lib/stop_signal import ignorePipeSignal
import ../../../src/rpc/[server, protocol, wire, wire_stream]
import ../../../src/chain/[genesis, parameters, provider]
from ../../../src/codec/state/layout import chapterKey, StateChapter
from ../../../src/codec/state/trie import StateEntry

proc inspectBind(fd: cint, address: pointer, size: ptr posix.SockLen): cint {.
    importc: "getsockname", header: "<sys/socket.h>".}
  ## Observe the actual kernel listener address.

proc networkAddress(value: uint32): uint32 {.importc: "htonl", header: "<arpa/inet.h>".}
  ## Compare the bound address in network byte order.

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Only the foreground test driver pauses natively; transport jobs yield through the reactor.

proc clientFrame(request: string, opcode = 1): string =
  ## Independent client masking keeps the wire oracle outside the stock server implementation.
  assert request.len <= 65535
  result = $char(128 or opcode)
  if request.len < 126:
    result.add(char(128 or request.len))
  else:
    # Medium lengths use two network-order bytes.
    result.add("\xfe" & $char(request.len shr 8) & $char(request.len and 255))
  result.add("abcd")
  for index, octet in request:
    result.add(char(ord(octet) xor ord("abcd"[index mod 4])))

proc sendRequest(peer: var tcp.Socket, request: string, opcode: int = 1) =
  ## Send one independently encoded client frame.
  try:
    peer.write(clientFrame(request, opcode))
  except ErrorCode:
    assert false, "test client sends its complete request before retirement"

proc child(parent: BlockSnapshot, settings: Parameters): BlockSnapshotResult =
  ## Synthetic direct-child state exercises publication ownership, not consensus validation.
  var header = newSeq[byte](297)
  let hash = array[32, byte](parent.blockHash)
  let root = array[32, byte](parent.stateRoot)
  for index in 0..<32:
    header[index] = hash[index]
    header[32 + index] = root[index]
  header[96] = 9
  var roster = newSeq[byte](2017)
  roster[0] = 6
  captureBlockSnapshot(header, @[StateEntry(key: chapterKey(StateChapter(8)), value: roster),
    StateEntry(key: chapterKey(StateChapter(11)), value: @[9'u8, 0, 0, 0])], settings)

proc awaitWire(owner: var Server, peer: var tcp.Socket, expected: string,
    untilEof = false): string =
  ## Tick the real listener and observe the wire independently of the server decoder.
  result = ""
  for attempt in 0..<2000:
    owner.tick(0)
    var bytes = default(array[1024, char])
    let count = native_io.receive(peer.fd, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: result.add(bytes[index])
      if not untilEof and expected in result: return
    elif count == 0:
      # Half-close tests require both delivery and subsequent connection retirement.
      if untilEof and expected in result: return
      break
    discard pauseMicros(1000)
  assert false, "expected RPC stream output: " & expected

proc socketPair(domain, kind, protocol: cint, pair: pointer): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}

proc shutdownSocket(fd, how: cint): cint {.importc: "shutdown", header: "<sys/socket.h>".}
  ## Finish the sending half of the client while keeping its receiving half open.
let shutdownWrite {.importc: "SHUT_WR", header: "<sys/socket.h>".}: cint

const UpgradeRequest = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"

proc preambleLimits() =
  ## Both production Reader loops refuse a fragmented blank-line head before its deadline.
  for rpc in [false, true]:
    # Independent socket pairs keep stream ownership and refusal observation local to each case.
    var pair = default(array[2, cint])
    assert socketPair(cint(posix.AF_UNIX), cint(posix.SOCK_STREAM), 0, addr pair[0]) == 0,
      "create the preamble stream fixture"
    defer: discard posix.close(pair[1])
    assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
    var http = default(HttpStream)
    var websocket = default(RpcWireStream)
    if rpc:
      assert websocket.start(pair[0]), "start the RPC Reader"
    else:
      assert http.start(pair[0]), "start the HTTP Reader"
    let limit = int(maxHeadBytes())
    var head = ""
    var input = default(WireInput)
    var sent = 0
    while sent < limit - 2:
      # Small sends fit macOS socket-pair buffers; drive the Reader between fragments.
      var chunk = repeat("\r\n", min(1024, limit - 2 - sent) div 2)
      assert native_io.sendBytes(pair[1], chunk.toCString(), csize_t(chunk.len), 0) == chunk.len,
        "send the next preamble fragment"
      sent += chunk.len
      for attempt in 0..<10:
        # The incomplete preamble remains pending until its retained wire budget is exhausted.
        pollRpcStreams()
        websocket.pump()
        if rpc:
          assert not websocket.takeInput(input), "RPC preamble remains pending below its limit"
        else:
          assert http.receiveHead(head) == HeadPending, "HTTP preamble remains pending below its limit"
        discard pauseMicros(1000)
    var ending = "\r\n"
    assert native_io.sendBytes(pair[1], ending.toCString(), csize_t(ending.len), 0) == ending.len,
      "send the final two bytes of the wire head budget"
    var refused = false
    for attempt in 0..<1000:
      # No request line or EOF follows: only the byte bound can publish this refusal now.
      pollRpcStreams()
      websocket.pump()
      if rpc:
        if websocket.takeInput(input):
          assert input.kind == BadHead, "RPC publishes a head refusal"
          refused = true
      else:
        let extent = http.receiveHead(head)
        if extent != HeadPending:
          assert extent == HeadTooLarge and head == "", "HTTP refuses without publishing a head"
          refused = true
      if refused: break
      discard pauseMicros(1000)
    assert refused, "blank-line head reaches its byte bound before the five-second deadline"

proc replyAfterEof() =
  ## Force EOF to arrive after the inbox transfer and before the dispatcher publishes its reply.
  var pair = default(array[2, cint])
  assert socketPair(cint(posix.AF_UNIX), cint(posix.SOCK_STREAM), 0, addr pair[0]) == 0
  defer: discard posix.close(pair[1])
  assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
  var stream = default(RpcWireStream)
  assert stream.start(pair[0])
  # Arm readiness on a silent peer, then publish output without driving
  # another dispatcher turn. send must wake the stream's parked task.
  for attempt in 0..<30:
    pollRpcStreams()
    stream.pump()
    discard pauseMicros(1000)
  var idleOutput = "\x8a\x00"
  assert stream.send(idleOutput)
  for attempt in 0..<1000:
    pollRpcStreams()
    if not stream.writing: break
    discard pauseMicros(1000)
  assert not stream.writing
  var idleReply = default(array[2, char])
  assert native_io.receive(pair[1], addr idleReply[0], 2, 0) == 2
  assert idleReply == ['\x8a', '\x00']
  var incoming = UpgradeRequest & clientFrame("\x03\xe8", 8)
  assert native_io.sendBytes(pair[1], incoming.toCString(), csize_t(incoming.len), 0) == incoming.len
  assert shutdownSocket(pair[1], shutdownWrite) == 0
  var input = default(WireInput)
  for attempt in 0..<1000:
    pollRpcStreams()
    stream.pump()
    if stream.takeInput(input): break
    discard pauseMicros(1000)
  assert input.kind == UpgradeHead and input.head == UpgradeRequest
  for attempt in 0..<1000:
    pollRpcStreams()
    stream.pump()
    if stream.takeInput(input): break
    discard pauseMicros(1000)
  assert input.kind == ClientFrame and input.frame.status == complete
  assert input.frame.opcode == 8 and input.frame.payload == "\x03\xe8"
  for attempt in 0..<1000:
    pollRpcStreams()
    stream.pump()
    if stream.inputEnded or stream.finished: break
    discard pauseMicros(1000)
  assert stream.inputEnded and not stream.finished, "FIN preserves the writer after the final inbox transfer"
  const reply = "\x88\x02\x03\xe8"
  var output = reply
  assert stream.send(output)
  for attempt in 0..<1000:
    pollRpcStreams()
    stream.pump()
    if not stream.writing: break
    discard pauseMicros(1000)
  assert not stream.writing and not stream.finished
  stream = default(RpcWireStream)
  var actual = ""
  var octet = '\0'
  for index in 0..<reply.len:
    # Output credit was released only after all bytes reached the kernel.
    assert native_io.receive(pair[1], addr octet, 1, 0) == 1
    actual.add(octet)
  assert actual == reply and native_io.receive(pair[1], addr octet, 1, 0) == 0

let sendBuffer {.importc: "SO_SNDBUF", header: "<sys/socket.h>".}: cint

proc blockedWriter(owner: var Server, client: var tcp.Socket) =
  ## A socket with a small send buffer and an unread peer holds the stream's output credit.
  var pair = default(array[2, cint])
  assert socketPair(cint(posix.AF_UNIX), cint(posix.SOCK_STREAM), 0, addr pair[0]) == 0
  defer: discard posix.close(pair[1])
  var capacity = 4096.cint
  assert native_io.setOption(pair[0], native_io.SocketLevel, sendBuffer, addr capacity,
    posix.SockLen(sizeof(capacity))) == 0
  assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
  var stream = default(RpcWireStream)
  assert stream.start(pair[0])
  var output = repeat('x', 65535)
  let started = getMonoTime().ticks
  assert stream.send(output)
  var octet = '\0'
  var count = 0
  for attempt in 0..<1000:
    pollRpcStreams()
    count = native_io.receive(pair[1], addr octet, 1, 0)
    if count == 1: break
    discard pauseMicros(1000)
  assert count == 1 and octet == 'x' and stream.writing
  client.sendRequest("alive", 9)
  assert owner.awaitWire(client, "alive") == "\x8a\x05alive"
  assert stream.writing, "a healthy connection progresses while a writer remains blocked"
  # The writer has made partial progress. Keep the peer open and stop without draining it.
  stream.stop()
  stream = default(RpcWireStream)
  assert (getMonoTime().ticks - started) div 1_000_000 < 6000

proc coalescedFrames(owner: var Server, port: uint16) {.raises.} =
  ## A maximum-size request and the following ping can share one receive chunk.
  var peer = tcp.connect("127.0.0.1", port, afterMs(5000))
  defer: peer.close()
  peer.write(UpgradeRequest)
  assert owner.awaitWire(peer, "\r\n\r\n").startsWith("HTTP/1.1 101 ")
  const request = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_clientInfo\",\"id\":75}"
  let ping = repeat('p', 64)
  let pong = "\x8a\x40" & ping
  peer.write(clientFrame(request & repeat(' ', MaxMessage - request.len)) & clientFrame(ping, 9))
  let output = owner.awaitWire(peer, pong)
  # Read the independently encoded reply length to verify the exact frame boundary and order.
  assert output.len >= 4 and output[0] == '\x81' and output[1] == '\x7e'
  let replyEnd = 4 + ord(output[2]) * 256 + ord(output[3])
  assert replyEnd < output.len and "\"id\":75," in output[4..<replyEnd]
  assert output[replyEnd..^1] == pong

proc halfClosedClient(owner: var Server, port: uint16) {.raises.} =
  ## A no-reply frame ahead of the final batch must not retire the dispatcher before the batch.
  var peer = tcp.connect("127.0.0.1", port, afterMs(5000))
  defer: peer.close()
  peer.write(UpgradeRequest)
  assert owner.awaitWire(peer, "\r\n\r\n").startsWith("HTTP/1.1 101 ")
  var requests: seq[string] = @[]
  for id in 1..16:
    requests.add("{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_clientInfo\",\"id\":" & $id & "}")
  peer.write(clientFrame("ignored", 10) & clientFrame("[" & requests.join(",") & "]"))
  assert shutdownSocket(peer.fd, shutdownWrite) == 0
  let response = owner.awaitWire(peer, "\"id\":16,", untilEof = true)
  assert response.len >= 4 and response[0] == '\x81' and response[1] == '\x7e'
  assert response.len == 4 + ord(response[2]) * 256 + ord(response[3])
  for id in 1..16:
    assert ("\"id\":" & $id & ",") in response

type RpcLogCapture = object
  ## The sink parks outside the queue lock so the test's records can be admitted.
  entered, releaseSink: bool
  messages: string

proc collectRpcLog(context: nil pointer, batch: string) {.raises: [].} =
  ## Capture text on the logger lane until the dispatcher releases and joins it.
  let capture = cast[ptr RpcLogCapture](context)
  atomicStore(capture.entered, true, moRelease)
  while not atomicLoad(capture.releaseSink, moAcquire): discard pauseMicros(1000)
  capture.messages.add(batch)

proc startCapture(logger: var Logger, capture: var RpcLogCapture, level = LogLevel.Info) =
  ## Retry sentinel admission only. Once the sink enters, it cannot contend for the queue.
  assert logger.start(initLogPolicy(level), collectRpcLog, addr capture)
  var primed = false
  for attempt in 0..<1000:
    if submitLog(logger.writer, LogTarget.Rpc, LogLevel.Info, "test sink barrier"):
      primed = true
      break
    discard pauseMicros(1000)
  assert primed, "RPC log fixture sentinel admitted"
  for attempt in 0..<1000:
    if atomicLoad(capture.entered, moAcquire): return
    discard pauseMicros(1000)
  assert false, "RPC log fixture sink entered"

proc closeCapture(logger: var Logger, capture: var RpcLogCapture) =
  ## Release the parked sink before the logger joins and drains accepted records.
  atomicStore(capture.releaseSink, true, moRelease)
  logger.close()

proc disconnectedWriter() =
  ## A real send error survives the worker join and is visible at the Info filter.
  assert ignorePipeSignal()
  var capture = default(RpcLogCapture)
  var logger = default(Logger)
  logger.startCapture(capture)
  defer: logger.closeCapture(capture)
  var pair = default(array[2, cint])
  assert socketPair(cint(posix.AF_UNIX), cint(posix.SOCK_STREAM), 0, addr pair[0]) == 0
  assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
  var stream = default(RpcWireStream)
  assert stream.start(pair[0], logger.writer)
  assert posix.close(pair[1]) == 0
  var reply = "private response bytes"
  assert stream.send(reply)
  for attempt in 0..<1000:
    pollRpcStreams()
    if stream.finished: break
    discard pauseMicros(1000)
  assert stream.finished
  stream = default(RpcWireStream)
  logger.closeCapture(capture)
  assert "[warn][rpc] RPC stream write ended: IOError" in capture.messages
  assert "connection retired" notin capture.messages and "private response bytes" notin
      capture.messages

proc refuseAtCapacity(owner: var Server, client: var tcp.Socket, port: uint16) {.raises.} =
  ## An existing upgraded client occupies one slot. Fill the others and observe the new peer close.
  var peers = default(array[MaxConnections - 1, tcp.Socket])
  for peer in mitems(peers):
    peer.fd = -1 # A default stdlib Socket contains descriptor zero until explicitly initialized.
  for peer in mitems(peers):
    # One real connection per dispatcher turn fills exactly the remaining slot budget.
    peer = tcp.connect("127.0.0.1", port, afterMs(1000))
    owner.tick(0)
  var excess = tcp.connect("127.0.0.1", port, afterMs(1000))
  owner.tick(0)
  var octet = '\0'
  for attempt in 0..<1000:
    # Read independently of the RPC stream to distinguish a real refusal from silence.
    if native_io.receive(excess.fd, addr octet, 1, 0) == 0:
      client.sendRequest("at capacity", 9)
      assert owner.awaitWire(client, "at capacity") == "\x8a\x0bat capacity"
      return # The fill clients still hold their slots while the established client gets Pong.
    discard pauseMicros(1000)
  assert false, "RPC listener closes an over-capacity peer"

proc main() {.raises.} =
  # Discover an available loopback port before exercising normal listener startup.
  let probe = native_io.listenLoopback(0, 1)
  assert probe >= 0
  var address = default(posix.Sockaddr_in)
  var length = posix.SockLen(sizeof(address))
  assert inspectBind(probe, addr address, addr length) == 0
  assert address.sin_addr.s_addr == networkAddress(0x7f000001'u32)
  let port = boundPort(probe)
  discard posix.close(probe)
  var settings = default(array[ParameterBytes, byte])
  settings[24] = 2
  settings[30] = 10
  settings[80] = 6
  settings[84] = 1
  let parameters = decodeParameters(settings)
  assert parameters.ok
  let header = repeat("00", 32) & repeat("11", 32) & repeat("00", 32) & "07000000" & repeat("00", 197)
  let roster = "08" & repeat("00", 30)
  let clock = "0b" & repeat("00", 30)
  let source = "{\"genesis_header\":\"" & header & "\",\"genesis_state\":{\"" & roster & "\":\"06" &
    repeat("00", 2016) & "\",\"" & clock & "\":\"07000000\"}}"
  let initial = configuredGenesis(source, parameters.value)
  assert initial.error == GenesisError.None
  let next = child(initial.value, parameters.value)
  assert next.error == GenesisError.None
  var capture = default(RpcLogCapture)
  var logger = default(Logger)
  logger.startCapture(capture, LogLevel.Debug)
  defer: logger.closeCapture(capture)
  var owner = default(Server)
  let prefix = "{\"jsonrpc\":\"2.0\",\"method\":\"subscribeBestBlock\",\"params\":{\"subscription\":1,\"result\":{\"header_hash\":\""
  assert owner.start(port, "stream", parameters, initial, logger = logger.writer)
  var duplicate = default(Server)
  assert not duplicate.start(port, "duplicate", parameters, initial)
  var client = tcp.connect("127.0.0.1", port, afterMs(5000))
  client.write(UpgradeRequest)
  assert owner.awaitWire(client, "\r\n\r\n").startsWith("HTTP/1.1 101 ")
  let lease = owner.pauseChain()
  assert lease != nil
  client.sendRequest("{\"jsonrpc\":\"2.0\",\"method\":\"subscribeBestBlock\",\"params\":[],\"id\":7}")
  var octet = '\0'
  for attempt in 0..<20:
    pollRpcStreams()
    owner.tick(0)
    assert native_io.receive(client.fd, addr octet, 1, 0) < 0
    discard pauseMicros(1000)
  assert owner.resumeChain(lease)
  let initialEvent = prefix & base64.encode(array[32, byte](initial.value.blockHash)) & "\",\"slot\":7}}}"
  let subscribed = owner.awaitWire(client, initialEvent)
  assert "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":1}" in subscribed
  let splitPing = clientFrame("split", 9)
  client.write(splitPing.substr(0, 2))
  for attempt in 0..<20:
    owner.tick(0) # Park with a partial frame and no further bytes from the client.
    discard pauseMicros(1000)
  assert owner.publishBlock(next) == ViewAdvanceError.None
  let event = prefix & base64.encode(array[32, byte](next.value.blockHash)) & "\",\"slot\":9}}}"
  discard owner.awaitWire(client, event)
  client.write(splitPing.substr(3))
  assert owner.awaitWire(client, "split") == "\x8a\x05split"
  client.sendRequest("{\"jsonrpc\":\"2.0\",\"method\":\"unsubscribeBestBlock\",\"params\":[1],\"id\":8}")
  discard owner.awaitWire(client, "{\"jsonrpc\":\"2.0\",\"id\":8,\"result\":true}")
  coalescedFrames(owner, port)
  halfClosedClient(owner, port)
  replyAfterEof()
  preambleLimits()
  blockedWriter(owner, client)
  owner.refuseAtCapacity(client, port)
  # Give the dispatcher time to arm readiness before testing joined idle shutdown.
  for attempt in 0..<30:
    owner.tick(0)
    discard pauseMicros(1000)
  let started = getMonoTime().ticks
  owner.close() # The idle client remains open until the dispatcher has joined its task.
  assert (getMonoTime().ticks - started) div 1_000_000 < 1000
  assert native_io.receive(client.fd, addr octet, 1, 0) == 0
  client.close()
  logger.closeCapture(capture)
  assert "[info][rpc] RPC WebSocket upgrade accepted" in capture.messages
  assert "[debug][rpc] RPC connection refused at capacity" in capture.messages
  assert "RPC accept failed" notin capture.messages # An idle nonblocking listener is routine.
  disconnectedWriter()
  ioring.shutdown()

try:
  main()
except ErrorCode:
  assert false, "stock WebSocket setup succeeds"
echo "Stock WebSocket RPC dispatch checks passed"
