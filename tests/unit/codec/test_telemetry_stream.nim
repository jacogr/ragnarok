# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real Writer delivery, bounded backpressure, deadlines, idle wakeup and joined cancellation.

import std/[assertions, syncio, strutils, oserrors, monotimes]
import std/posix/posix as posix
include ../../../src/telemetry/stream

proc socketPair(domain, kind, protocol: cint, pair: pointer): cint {.
    importc: "socketpair", header: "<sys/socket.h>".}
  ## Give the production connected-stream task a deterministic local peer.

proc connectedPair(peer: var cint): TelemetryStream =
  ## The fixture bypasses only dialing, adopting the same task used after production connect.
  var pair = default(array[2, cint])
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0,
      addr pair[0]) == 0
  assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
  peer = pair[1]
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  s[] = Exchange(phase: ord(Connecting))
  initLock(s.lock)
  result = TelemetryStream(exchange: s)
  submit(delay(runConnected(pair[0], s)), -1)

proc awaitReady(stream: TelemetryStream) =
  ## Bounded polling drives passive continuations without borrowing stream-owned bytes.
  for attempt in 0..<1000:
    pollTelemetryStreams()
    if stream.ready: return
    assert not stream.finished, "stream reaches Ready without I/O failure"
    discard pause(1000)
  assert false, "stream becomes Ready within the fixture allowance"

proc receiveBytes(peer: cint, expected: int): string =
  ## Read exact wire bytes independently of Writer's buffers and partial-send bookkeeping.
  result = ""
  for attempt in 0..<2000:
    pollTelemetryStreams()
    var bytes = default(array[4096, char])
    let count = native_io.receive(peer, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: result.add(bytes[index])
      if result.len >= expected: return
    else:
      assert count != 0, "peer remains open until the expected bytes arrive"
    discard pause(1000)
  assert false, "complete wire batch arrives within the fixture allowance"

proc delivery() =
  ## Every byte value, caller mutation and a second batch verify detached owned wire delivery.
  var peer = -1.cint
  var stream = connectedPair(peer)
  defer: discard posix.close(peer)
  stream.awaitReady()
  var bytes = newSeq[byte](MaxPendingBytes)
  var expected = ""
  for index in 0..<bytes.len:
    bytes[index] = byte(index mod 256)
    expected.add(char(bytes[index]))
  assert stream.send(bytes, afterMs(5000))
  for index in 0..<bytes.len: bytes[index] = 42
  assert receiveBytes(peer, expected.len) == expected
  stream.awaitReady()
  assert stream.send([1'u8, 0, 255], afterMs(5000))
  assert receiveBytes(peer, 3) == "\x01\x00\xff"
  stream.awaitReady()
  let started = getMonoTime().ticks
  var moved = move(stream)
  stream.close() # The moved source cannot wake or release its destination's task.
  assert moved.ready and not stream.active
  moved.close()
  assert (getMonoTime().ticks - started) div 1_000_000 < 1000
  var octet = '\0'
  assert native_io.receive(peer, addr octet, 1, 0) == 0, "joined close releases the connection"

proc submittedStop() =
  ## A batch admitted just before shutdown is still attempted within its existing deadline.
  var peer = -1.cint
  var stream = connectedPair(peer)
  defer: discard posix.close(peer)
  stream.awaitReady()
  assert stream.send([27'u8, 0, 255], afterMs(5000))
  stream.close() # No new work is admitted while the existing batch finishes and the task joins.
  assert receiveBytes(peer, 3) == "\x1b\x00\xff"
  var octet = '\0'
  assert native_io.receive(peer, addr octet, 1, 0) == 0

type EndCase = enum Drained, Expired, Stopped
  ## Select independent successful delivery, I/O failure and cancellation schedules.

proc backpressure(ending: EndCase) =
  ## A saturated native socket forces Writer to retain its batch across suspended sends.
  var pair = default(array[2, cint])
  assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0,
      addr pair[0]) == 0
  assert native_io.nonblocking(pair[0]) and native_io.nonblocking(pair[1])
  defer: discard posix.close(pair[1])
  var filler = repeat('x', 4096)
  var filled = 0
  var blocked = false
  for attempt in 0..<8192:
    # Stop at would-block; every call is nonblocking and the finite allowance caps fixture work.
    let sent = native_io.sendBytes(pair[0], filler.toCString(), csize_t(filler.len), 0)
    if sent < 0:
      assert osLastError() in [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK)]
      blocked = true
      break
    filled += sent
  assert blocked, "fixture reaches real kernel backpressure"
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  s[] = Exchange(phase: ord(Connecting))
  initLock(s.lock)
  var stream = TelemetryStream(exchange: s)
  submit(delay(runConnected(pair[0], s)), -1)
  stream.awaitReady()
  var bytes = newSeq[byte](MaxPendingBytes)
  for index in 0..<bytes.len: bytes[index] = byte(index mod 251)
  let budget = if ending == Drained: 5000 else: 100
  assert stream.send(bytes, afterMs(budget))
  for attempt in 0..<20:
    # Pump the real blocked write before testing occupied credit and cancellation.
    pollTelemetryStreams()
    discard pause(1000)
  assert not stream.ready
  if ending == Drained: assert not stream.finished
  assert not stream.send([99'u8], afterMs(5000)), "pending output keeps exclusive batch credit"
  if ending != Drained:
    if ending == Expired:
      # A real I/O deadline publishes its error without requiring stop or another submission.
      for attempt in 0..<1000:
        pollTelemetryStreams()
        if stream.finished: break
        discard pause(1000)
      assert stream.finished and stream.failure == TimeoutError
    # Shutdown joins the original short write budget and aborts without a destructor flush.
    let started = getMonoTime().ticks
    stream.close()
    assert (getMonoTime().ticks - started) div 1_000_000 < 1000
    assert receiveBytes(pair[1], filled) == repeat('x', filled)
    var octet = '\0'
    assert native_io.receive(pair[1], addr octet, 1, 0) == 0, "abort does not flush expired telemetry"
  else:
    # Removing backpressure must deliver exactly the original batch once, after fixture filler.
    var expected = repeat('x', filled)
    for octet in bytes: expected.add(char(octet))
    assert receiveBytes(pair[1], expected.len) == expected
    stream.awaitReady()
    stream.close()

block:
  # Refuse an address extent that would make the reactor borrow beyond its native value.
  var stream = default(TelemetryStream)
  assert not stream.start(default(Sockaddr_storage), SockLen(sizeof(Sockaddr_storage) + 1),
    nativesocket.AF_INET)
  assert not stream.active
delivery()
submittedStop()
for ending in [Drained, Expired, Stopped]:
  # Fresh resources isolate successful resumption from the independent deadline-abort case.
  backpressure(ending)
ioring.shutdown()
echo "telemetry Writer delivery, backpressure and joined shutdown passed"
