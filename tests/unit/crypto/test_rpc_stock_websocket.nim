# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real stock WebSocket tasks feed detached bytes to the canonical RPC dispatcher and its subscription FIFO.

import std/[assertions, syncio, strutils, base64, threadpool, ioring]
import std/websocket as ws
import std/httpserver as http
import std/socket as tcp
import std/posix/posix as posix
import ../../../src/rpc/[server, protocol, websocket_transport]
import ../../../src/rpc/transport_bridge as transport
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
    assert false, "test client sends its complete request before bridge retirement"

proc exact(peer: var tcp.Socket, size: int): string =
  ## Finite client deadlines and a byte ceiling bound every independent frame read.
  assert size >= 0 and size <= 65535
  result = ""
  while result.len < size:
    var bytes = default(array[256, char])
    let capacity = min(bytes.len, size - result.len)
    let count = try:
      peer.read(toOpenArray(bytes, 0, capacity - 1))
    except ErrorCode:
      assert false, "expected stock WebSocket output arrives before the client deadline"
      0
    assert count > 0
    for index in 0..<count: result.add(bytes[index])

proc frame(peer: var tcp.Socket, opcode: int): string =
  ## Assert final, unmasked framing without consulting the server encoder.
  let head = peer.exact(2)
  assert ord(head[0]) == (128 or opcode) and (ord(head[1]) and 128) == 0
  var size = ord(head[1])
  assert size != 127
  if size == 126:
    let medium = peer.exact(2)
    size = ord(medium[0]) * 256 + ord(medium[1])
  peer.exact(size)

proc textFrame(peer: var tcp.Socket): string =
  ## RPC replies and unsolicited notifications use only text frames.
  peer.frame(1)

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

proc drive(owner: var Server, bridge: var transport.RpcTransportBridge,
    writer: var WebSocketTaskState, count: uint64) =
  ## Bounded foreground turns execute all canonical queries; tasks see only the bridge.
  for attempt in 0..<2000:
    pollWebSocketTransport()
    discard owner.dispatchTransport(bridge, 0)
    if writer.transferred >= count: return
    discard pauseMicros(1000)
  assert false, "stock writer frames: wanted=" & $count & " sent=" & $writer.transferred &
    " stopped=" & $writer.completed

proc rejectUpgrade(listener: var http.HttpServer, port: uint16, target, extra: string) {.raises.} =
  ## Endpoint admission remains application policy before the stock handshake takes the streams.
  var peer = tcp.connect("127.0.0.1", port, afterMs(5000))
  peer.write("GET " & target & " HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" &
      extra & "\r\n")
  var request = listener.accept()
  assert request.next()
  var refused = false
  try:
    var socket = upgradeRpcWebSocket(request)
    socket.abort() # Unexpected admission still retires its halves before failing the test.
  except ErrorCode:
    refused = true
  assert refused and request.isClosed
  peer.close()

proc main() {.raises.} =
  ## Finish handshake setup before lending stable bridge/state addresses to task callbacks.
  var listener = listenRpcWebSocket(0)
  assert listener.fd >= 0
  var address = default(posix.Sockaddr_in)
  var length = posix.SockLen(sizeof(address))
  assert inspectBind(listener.fd, addr address, addr length) == 0
  assert address.sin_addr.s_addr == networkAddress(0x7f000001'u32), "listener binds only IPv4 loopback"
  let port = boundPort(listener.fd)
  var duplicate = listenRpcWebSocket(port)
  assert duplicate.fd < 0, "an occupied port fails without a live listener"
  duplicate.close()
  rejectUpgrade(listener, port, "/wrong", "")
  rejectUpgrade(listener, port, "/", "Origin: http://untrusted\r\n")
  rejectUpgrade(listener, port, "/", "Origin:\r\n")
  rejectUpgrade(listener, port, "/", "Host: duplicate\r\n")
  rejectUpgrade(listener, port, "/", "Connection: close\r\n")
  rejectUpgrade(listener, port, "/", "Upgrade: h2c\r\n")
  rejectUpgrade(listener, port, "/", "Content-Length: 0\r\n")
  var peer = tcp.connect("127.0.0.1", port, afterMs(5000))
  peer.write("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
  var connection = listener.accept()
  assert connection.next()
  var socket = upgradeRpcWebSocket(connection)
  assert peer.readLine().startsWith("HTTP/1.1 101 ")
  while peer.readLine().len != 0: discard
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
  assert owner.startTransport(port, "bridge", parameters, initial)
  var bridge = default(transport.RpcTransportBridge)
  var selected = default(transport.BridgeTicket)
  assert bridge.open(0, selected) == transport.Ready
  var readerState, writerState = default(WebSocketTaskState)
  submit(delay(readWebSocket(move(socket.reader), addr bridge, selected, addr readerState)), -1)
  submit(delay(writeWebSocket(move(socket.writer), addr bridge, selected, addr writerState)), -1)
  peer.sendRequest("{\"jsonrpc\":\"2.0\",\"method\":\"subscribeBestBlock\",\"params\":[],\"id\":7}")
  owner.drive(bridge, writerState, 2)
  assert peer.textFrame() == "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":1}"
  let prefix = "{\"jsonrpc\":\"2.0\",\"method\":\"subscribeBestBlock\",\"params\":{\"subscription\":1,\"result\":{\"header_hash\":\""
  assert peer.textFrame() == prefix & base64.encode(array[32, byte](initial.value.blockHash)) & "\",\"slot\":7}}}"
  assert owner.publishBlock(next) == ViewAdvanceError.None
  owner.drive(bridge, writerState, 3)
  assert peer.textFrame() == prefix & base64.encode(array[32, byte](next.value.blockHash)) & "\",\"slot\":9}}}"
  peer.sendRequest("{\"jsonrpc\":\"2.0\",\"method\":\"unsubscribeBestBlock\",\"params\":[1],\"id\":8}")
  owner.drive(bridge, writerState, 4)
  assert peer.textFrame() == "{\"jsonrpc\":\"2.0\",\"id\":8,\"result\":true}"
  peer.sendRequest("alive", 9)
  owner.drive(bridge, writerState, 5)
  assert peer.frame(10) == "alive"
  peer.sendRequest("\x03\xe8finished", 8)
  owner.drive(bridge, writerState, 6)
  assert peer.frame(8) == "\x03\xe8finished", "close code and complete reason survive the split bridge"
  assert owner.closeTransport(bridge)
  peer.close() # Release idle recv cooperatively; local cancellation remains a documented adoption gate.
  var retired = false
  for attempt in 0..<2000:
    pollWebSocketTransport()
    retired = readerState.completed and writerState.completed
    if retired: break
    discard pauseMicros(1000)
  assert retired, "both task owners retire before bridge and state storage leave scope"
  listener.close()
  shutdown()

try:
  main()
except ErrorCode:
  assert false, "stock WebSocket setup succeeds"
echo "Stock WebSocket RPC dispatch checks passed"
