# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise public WebSocket split ownership with eight independent loopback peers.

import std/[assertions, syncio, strutils, atomics]
import std/websocket as ws
import std/httpserver as http
import std/socket as tcp
import std/ioring as io
import std/threadpool as pool
import std/posix/posix

const Peers = 8

type Observation = object
  ## Only atomic scalar observations cross task boundaries; canonical/query owners never do.
  readerStarted, readerWorker, readerDone, writerStarted, writerWorker, writerDone,
    writerFailed: bool

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let pool workers run without the foreground joining their continuation executor.

proc setOption(fd, level, option: cint, value: pointer, size: SockLen): cint {.
    importc: "setsockopt", header: "<sys/socket.h>".}
  ## Clamp only the independent test peer's receive window to arrange backpressure.
let ReceiveBuffer {.importc: "SO_RCVBUF", header: "<sys/socket.h>".}: cint
let SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
when defined(macosx):
  # Accepted Darwin sockets inherit this ordinary listener option.
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint

proc readTask(input: sink ws.WebSocketReader; observed: ptr Observation) {.passive.} =
  ## The reader has its own owner and reports only scalar progress to the foreground.
  var reader = input
  atomicStore(observed.readerWorker, pool.isPoolWorker(), moRelease)
  atomicStore(observed.readerStarted, true, moRelease)
  var message = ""
  try:
    discard reader.recv(message)
  except ErrorCode:
    discard # Closing the independent peer wakes this deliberately idle reader.
  reader.close()
  atomicStore(observed.readerDone, true, moRelease)

proc writeTask(output: sink ws.WebSocketWriter; text: sink string; repeats: int;
    observed: ptr Observation) {.passive.} =
  ## One owner writes this connection; unrelated connections have independent owners/tasks.
  var writer = output
  atomicStore(observed.writerWorker, pool.isPoolWorker(), moRelease)
  atomicStore(observed.writerStarted, true, moRelease)
  try:
    for frame in 0..<repeats:
      # A bounded stream of RPC-sized frames creates pressure without an oversized message.
      writer.send(ws.mkText, text)
  except ErrorCode:
    atomicStore(observed.writerFailed, true, moRelease)
  writer.abort() # Explicit abort prevents destructor flushing after an error or cancellation.
  atomicStore(observed.writerDone, true, moRelease)

proc runWebSocketTrial*[slowPeer: static[bool]]() {.raises.} =
  ## Local owners outlive every task; explicit peer close precedes pool shutdown and retirement.
  var listener = http.listenHttp(0, http.newHttpTags())
  when defined(macosx):
    # Configure the public descriptor before accept; the process signal policy stays untouched.
    var enabled = 1.cint
    assert setOption(listener.fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) == 0
  let port = io.boundPort(listener.fd)
  var clients = default(array[Peers, tcp.Socket])
  for index in 0..<Peers: clients[index].fd = -1 # Default Socket's zero descriptor must not own stdin.
  var writers = default(array[Peers, ws.WebSocketWriter])
  var readers = default(array[Peers, ws.WebSocketReader])
  var observed = default(array[Peers, Observation])
  let upgrade = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
  for index in 0..<Peers:
    # HTTP and WebSocket negotiation both use the stock library; wire assertions are independent.
    clients[index] = tcp.connect("127.0.0.1", port, io.afterMs(5000))
    if index == 0:
      var capacity = 4096.cint
      assert setOption(clients[index].fd, SocketLevel, ReceiveBuffer, addr capacity,
        SockLen(sizeof(capacity))) == 0
    clients[index].write(upgrade)
    var connection = listener.accept()
    assert connection.next()
    var socket = ws.upgradeWebSocket(connection)
    assert socket.reader.deadline == io.never # Observe the stock idle default without overriding it.
    assert clients[index].readLine().startsWith("HTTP/1.1 101 ")
    var ended = false
    for line in 0..<16:
      if clients[index].readLine().len == 0:
        ended = true
        break
    assert ended
    readers[index] = move(socket.reader)
    writers[index] = move(socket.writer)
  for index in 0..<Peers:
    # Queue readers only after foreground handshake I/O stops; otherwise passiveWait may help them.
    pool.submit(delay(readTask(move(readers[index]), addr observed[index])), -1)
  echo "probe: upgrades=8"
  flushFile(stdout)
  var started = false
  for attempt in 0..<2000:
    started = true
    for index in 0..<Peers:
      if not atomicLoad(observed[index].readerStarted, moAcquire): started = false
    if started: break
    discard pauseMicros(1000)
  assert started, "all eight readers enter their tasks"
  for index in 0..<Peers:
    assert atomicLoad(observed[index].readerWorker, moAcquire), "library handlers run on pool workers"
    assert not atomicLoad(observed[index].readerDone, moAcquire), "quiet peers leave reads pending"
    var text = if slowPeer and index == 0: repeat('x', 16384) else: "update"
    let repeats = if slowPeer and index == 0: 512 else: 1
    pool.submit(delay(writeTask(move(writers[index]), move(text), repeats, addr observed[index])), -1)
  let firstDelivered = if slowPeer: 1 else: 0
  var delivered = false
  for attempt in 0..<2000:
    delivered = true
    for index in firstDelivered..<Peers:
      if not atomicLoad(observed[index].writerDone, moAcquire): delivered = false
    if delivered and atomicLoad(observed[0].writerStarted, moAcquire): break
    discard pauseMicros(1000)
  assert delivered, "a slow peer does not block writers on the other seven connections"
  echo "probe: delivered=", Peers - firstDelivered
  flushFile(stdout)
  when slowPeer:
    # The fairness witness is valid only if the slow connection really has unfinished output.
    assert not atomicLoad(observed[0].writerDone, moAcquire), "slow writer really remains parked"
  for index in firstDelivered..<Peers:
    assert not atomicLoad(observed[index].writerFailed, moAcquire)
    assert atomicLoad(observed[index].writerWorker, moAcquire)
    var wire = ""
    while wire.len < 8:
      var bytes = default(array[8, char])
      let count = try:
        clients[index].read(bytes)
      except ErrorCode:
        # Terminate with the observations still alive rather than unwinding across live tasks.
        assert false, "independent client receives the expected notification"
        0
      assert count > 0
      for at in 0..<count: wire.add(bytes[at])
    assert wire == "\x81\x06update", "notification arrives without another client request"
  echo "probe: unsolicited frames verified"
  flushFile(stdout)
  discard pauseMicros(20000)
  for index in 0..<Peers:
    assert not atomicLoad(observed[index].readerDone, moAcquire),
      "ending the writer does not cancel an idle reader"
  echo "probe: writer abort leaves readers pending=8"
  flushFile(stdout)
  echo "probe: closing peers"
  flushFile(stdout)
  for index in 0..<Peers: clients[index].close()
  var retired = false
  for attempt in 0..<2000:
    retired = true
    for index in 0..<Peers:
      if not atomicLoad(observed[index].readerDone, moAcquire) or
          not atomicLoad(observed[index].writerDone, moAcquire): retired = false
    if retired: break
    discard pauseMicros(1000)
  assert retired, "peer close releases pending reader/writer tasks before owner retirement"
  when slowPeer:
    assert atomicLoad(observed[0].writerFailed, moAcquire)
  listener.close()
  io.shutdown() # Join the pool only after all task owners have stopped using stack observations.
  echo "probe: task owners retired and pool joined"
