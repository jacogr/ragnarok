# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise the production RPC listener with independently encoded WebSocket clients.

import std/[assertions, syncio, strutils, base64, ioring, monotimes]
import std/socket as tcp
import std/posix/posix as posix
import ../../../src/lib/socket_io as native_io
import ../../../src/rpc/[server, protocol, wire_stream]
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

proc sendRequest(peer: var tcp.Socket, request: string, opcode: int = 1) =
  ## Independent client masking keeps the wire oracle outside the stock server implementation.
  assert request.len < 126
  var frame = $char(128 or opcode) & $char(128 or request.len) & "abcd"
  for index, octet in request:
    frame.add(char(ord(octet) xor ord("abcd"[index mod 4])))
  try:
    peer.write(frame)
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

proc awaitWire(owner: var Server, peer: var tcp.Socket, expected: string): string =
  ## Tick the real listener and observe the wire independently of the server decoder.
  result = ""
  for attempt in 0..<2000:
    owner.tick(0)
    var bytes = default(array[1024, char])
    let count = native_io.receive(peer.fd, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: result.add(bytes[index])
      if expected in result: return
    elif count == 0:
      break
    discard pauseMicros(1000)
  assert false, "expected RPC stream output: " & expected

proc socketPair(domain, kind, protocol: cint, pair: pointer): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
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
  stream.start(pair[0])
  var output = repeat('x', 65535)
  let started = getMonoTime().ticks
  stream.send(output)
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
  var owner = default(Server)
  let prefix = "{\"jsonrpc\":\"2.0\",\"method\":\"subscribeBestBlock\",\"params\":{\"subscription\":1,\"result\":{\"header_hash\":\""
  assert owner.start(port, "stream", parameters, initial)
  var duplicate = default(Server)
  assert not duplicate.start(port, "duplicate", parameters, initial)
  var client = tcp.connect("127.0.0.1", port, afterMs(5000))
  client.write("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
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
  assert owner.publishBlock(next) == ViewAdvanceError.None
  let event = prefix & base64.encode(array[32, byte](next.value.blockHash)) & "\",\"slot\":9}}}"
  discard owner.awaitWire(client, event)
  client.sendRequest("{\"jsonrpc\":\"2.0\",\"method\":\"unsubscribeBestBlock\",\"params\":[1],\"id\":8}")
  discard owner.awaitWire(client, "{\"jsonrpc\":\"2.0\",\"id\":8,\"result\":true}")
  blockedWriter(owner, client)
  let started = getMonoTime().ticks
  owner.close() # The idle client remains open until the dispatcher has joined its task.
  assert (getMonoTime().ticks - started) div 1_000_000 < 1000
  assert native_io.receive(client.fd, addr octet, 1, 0) == 0
  client.close()
  ioring.shutdown()

try:
  main()
except ErrorCode:
  assert false, "stock WebSocket setup succeeds"
echo "Stock WebSocket RPC dispatch checks passed"
