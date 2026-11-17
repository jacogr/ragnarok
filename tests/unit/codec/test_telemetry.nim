# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise telemetry client internals, event encoding, bounded queues and connection-state
## handling.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
include ../../../src/telemetry/client

# Read a known bounded little-endian field independently of production encoding helpers.
proc number(bytes: openArray[byte], start, width: int): uint64 =
  result = 0
  # Each asserted field is bounded by the independently expected message size.
  for i in 0..<width: result = result or (uint64(bytes[start + i]) shl (8 * i))

# Default results and all wrong metadata lengths must remain failed.
let empty = default(MetadataResult)
assert not empty.ok
var raw = default(array[MetadataSize, byte])
raw[24] = 2
let parsed = metadata(raw)
assert parsed.ok and parsed.value.coreCount == 2
# Every truncated record is rejected without extracting a partial snapshot.
for size in 0..<MetadataSize:
  let failed = metadata(raw.toOpenArray(0, size - 1))
  assert not failed.ok and failed.error == wrongSize
var oversized = newSeq[byte](MetadataSize + 1)
assert not metadata(oversized).ok
raw[24] = 0
assert not metadata(raw).ok
raw[25] = 4
let maximum = metadata(raw)
assert maximum.ok # The supported maximum is exactly 1024 cores.
assert status(maximum.value, Timestamp(0), 0).len == 1069
raw[24] = 1
assert not metadata(raw).ok

# Metadata snapshots own input bytes; later mutations above cannot alter this registration.
let hello = registration(parsed.value)
assert number(hello, 0, 4) == uint64(hello.len - 4)
assert hello[4] == 1 and hello[29] == 2
assert number(hello, 209, 4) == 0
assert hello[213] == 8 # Compact name length, followed by ASCII Ragnarok.
assert hello[214] == byte('R') and hello[221] == byte('k')
let sample = status(parsed.value, Timestamp(0x0102030405060708'u64), 7)
assert sample.len == 47
assert number(sample, 0, 4) == 43
assert number(sample, 4, 8) == 0x0102030405060708'u64
assert sample[12] == 10 and number(sample, 13, 4) == 7
# Every remaining field is genuinely empty in the proof peer, with two raw core bytes.
for i in 17..<sample.len: assert sample[i] == 0
let loss = dropped(Timestamp(11), Timestamp(19), 3)
assert loss.len == 29 and number(loss, 0, 4) == 25
assert number(loss, 4, 8) == 11 and loss[12] == 0
assert number(loss, 13, 8) == 19 and number(loss, 21, 8) == 3

# Outgoing event layouts use fixed identity/address fields and little-endian correlation IDs.
var remoteIdentity = default(array[32, byte])
var remoteAddress = default(array[16, byte])
remoteIdentity[0] = 123
remoteAddress[15] = 1
let dialFrame = connectingOut(Timestamp(17), remoteIdentity, remoteAddress, 9000)
assert dialFrame.len == 63 and number(dialFrame, 0, 4) == 59
assert number(dialFrame, 4, 8) == 17 and dialFrame[12] == 24
assert dialFrame[13] == 123 and dialFrame[60] == 1 and number(dialFrame, 61, 2) == 9000
let established = connectedOut(Timestamp(19), EventId(0x0102030405060708'u64))
assert established.len == 21 and number(established, 0, 4) == 17 and established[12] == 26
assert number(established, 13, 8) == 0x0102030405060708'u64
let refused = connectOutFailed(Timestamp(20), EventId(7))
assert refused.len == 22 and number(refused, 0, 4) == 18 and refused[12] == 25
assert number(refused, 13, 8) == 7 and refused[21] == 0 # Empty reason is canonical.

# Disconnection carries the authenticated peer identity, an absent terminator and an empty reason.
let closed = disconnected(Timestamp(23), remoteIdentity)
assert closed.len == 47 and number(closed, 0, 4) == 43
assert number(closed, 4, 8) == 23 and closed[12] == 27
assert closed[13] == 123 and closed[45] == 0 and closed[46] == 0
for i in 14..<45: assert closed[i] == 0 # Identity bytes are fixed-width, without a sequence prefix.

# Refusal has an endpoint only: no invented identity, reason or correlation field.
let capacityRefusal = connectionRefused(Timestamp(30), remoteAddress, 65535)
assert capacityRefusal.len == 31 and number(capacityRefusal, 0, 4) == 27
assert capacityRefusal[12] == 20 and number(capacityRefusal, 4, 8) == 30
assert capacityRefusal[28] == 1 and number(capacityRefusal, 29, 2) == 65535
for i in 13..<28: assert capacityRefusal[i] == 0 # Preserve every IPv6 address byte.

# Incoming wire layouts preserve the pre-handshake event ID and add identity only on success.
let incoming = connectingIn(Timestamp(31), remoteAddress, 9001)
assert incoming.len == 31 and number(incoming, 0, 4) == 27 and incoming[12] == 21
assert incoming[28] == 1 and number(incoming, 29, 2) == 9001
let accepted = connectedIn(Timestamp(32), EventId(0x0102030405060708'u64), remoteIdentity)
assert accepted.len == 53 and number(accepted, 0, 4) == 49 and accepted[12] == 23
assert number(accepted, 13, 8) == 0x0102030405060708'u64 and accepted[21] == 123
let failedIncoming = connectInFailed(Timestamp(33), EventId(9))
assert failedIncoming.len == 22 and failedIncoming[12] == 22
assert number(failedIncoming, 13, 8) == 9 and failedIncoming[21] == 0

# Strict numeric endpoint parsing fails atomically and never creates descriptors.
for endpoint in ["", "localhost", "localhost:0", "localhost:65536", "127.0.0.1:-1",
    "127.0.0.1: 1", "127.0.0.1:1:2", "::1:9000", "[::1]", "[::1]:", "[]:1", "[::1]x:1",
    "[::1]:0", "[::1]:65536", "[::1]:-1", "[::1]: 1", "[::1]:1:2",
    "[127.0.0.1]:1", "[localhost]:1", "[fe80::1%lo0]:1", "[:::1]:1",
    "[::1]extra:1", "[::1\0x]:1", "[12345::1]:1", "127.0.0.999:9000", "127.0.0.1\0x:9000"]:
  var invalid = default(Client)
  assert not invalid.configure(endpoint, parsed.value), endpoint
  assert not invalid.enabled and not invalid.opened
# Accepted literal forms select IPv6 and preserve the port without opening a descriptor.
for endpoint in ["[::1]:1", "[2001:db8::abcd]:65535", "[::ffff:192.0.2.1]:9000",
    "[ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255]:65535"]:
  var literal = default(Client)
  assert literal.configure(endpoint, parsed.value), endpoint
  assert literal.ipv6 and not literal.opened
  assert literal.address6.sin6_family == TSa_Family(ord(nativesocket.AF_INET6))
  literal.close()
var valid = default(Client)
assert valid.configure("localhost:9000", parsed.value)
assert not valid.configure("127.0.0.1:9001", parsed.value)
valid.close()
valid.close()
valid.tick(0, Timestamp(0), 0)
assert not valid.opened

# Private queue witnesses verify bounded storage and retirement without relying on wall time.
var queued = default(Client)
queued.queue(sample, 10)
assert queued.length == 47 and queued.inFlight == 0 and queued.deadline == 5010
# Every copied byte is retained independently of the producer sequence.
for i in 0..<sample.len: assert queued.buffer[i] == sample[i]
queued.inFlight = 5
queued.lost = 8
queued.failed(20)
assert queued.length == 0 and queued.inFlight == 0 and queued.lost == 0
assert queued.retryAt == 5020

# Queue credit stays occupied until the Writer has acknowledged the entire in-flight batch.
var blocked = default(Client)
assert blocked.configure("localhost:9000", parsed.value)
blocked.opened = true # Exercise dispatcher queue policy independently of actual I/O timing below.
blocked.statusAt = 2000
blocked.peerDisconnected(1999, Timestamp(19), remoteIdentity)
blocked.tick(2000, Timestamp(20), 0)
assert blocked.lost == 0 and blocked.nextEvent == 2
assert blocked.length == closed.len + sample.len
assert blocked.buffer[12] == 27 and blocked.buffer[closed.len + 12] == 10
# Maximum-size statuses exhaust credit while an equally large detached batch is still in flight.
blocked.statusAt = 0
blocked.nextEvent = 0
let largeSample = status(maximum.value, Timestamp(30), 7)
blocked.metadata = maximum.value
blocked.queue(largeSample, 0)
blocked.inFlight = blocked.length
blocked.length = 0
blocked.tick(0, Timestamp(10), 7)
blocked.tick(2000, Timestamp(20), 7)
assert blocked.inFlight == largeSample.len and blocked.length == 0 and blocked.lost == 2
# Model only completed credit here; the stream suite proves actual Writer completion on sockets.
blocked.inFlight = 0
blocked.metadata = parsed.value
blocked.tick(4000, Timestamp(40), 7)
assert blocked.length == 29 + sample.len
assert number(blocked.buffer, 4, 8) == 10 and number(blocked.buffer, 13, 8) == 20
assert number(blocked.buffer, 21, 8) == 2 and blocked.buffer[29 + 12] == 10
blocked.length = 0 # The previous completed batch no longer occupies dispatcher staging.
# Correlation includes status and lost observations; append never overwrites a partial frame or deadline.
assert blocked.nextEvent == 3
let attempt = blocked.dialing(4100, Timestamp(41), remoteIdentity, remoteAddress, 9000)
assert uint64(attempt) == 3 and blocked.length == dialFrame.len
let originalDeadline = blocked.deadline
blocked.inFlight = 5
blocked.omit(Timestamp(42)) # Missing native metadata still consumes one correlated position.
assert blocked.nextEvent == 5 and blocked.lost == 1
blocked.dialOutcome(4300, Timestamp(43), attempt, true)
assert blocked.nextEvent == 6 and blocked.lost == 0 and blocked.inFlight == 5
assert blocked.deadline == originalDeadline
assert blocked.buffer[dialFrame.len + 12] == 0
assert number(blocked.buffer, dialFrame.len + 21, 8) == 1
assert blocked.buffer[dialFrame.len + 29 + 12] == 26
assert number(blocked.buffer, dialFrame.len + 29 + 13, 8) == 3
let beforeClose = blocked.length
blocked.peerDisconnected(4350, Timestamp(44), remoteIdentity)
assert blocked.nextEvent == 7 and blocked.length == beforeClose + closed.len
assert blocked.buffer[beforeClose + 12] == 27 and blocked.buffer[beforeClose + 13] == 123
assert blocked.deadline == originalDeadline and blocked.inFlight == 5
# Native tracking losses consume IDs and precede the next incoming frame without touching a partial prefix.
let beforeIncoming = blocked.length
blocked.omit(Timestamp(45))
blocked.omit(Timestamp(46))
let incomingId = blocked.accepting(4370, Timestamp(47), remoteAddress, 9000)
assert uint64(incomingId) == 9 and blocked.buffer[beforeIncoming + 12] == 0
assert number(blocked.buffer, beforeIncoming + 21, 8) == 2
assert blocked.buffer[beforeIncoming + 29 + 12] == 21
let beforeOutcome = blocked.length
blocked.acceptOutcome(4380, Timestamp(48), incomingId, remoteIdentity, true)
assert blocked.buffer[beforeOutcome + 12] == 23
assert number(blocked.buffer, beforeOutcome + 13, 8) == 9
assert blocked.nextEvent == 11 and blocked.deadline == originalDeadline and blocked.inFlight == 5
# Admission refusal appends after TLS success without allocating another correlation slot.
let beforeRefusal = blocked.length
blocked.refusing(4390, Timestamp(49), remoteAddress, 9000)
assert blocked.nextEvent == 12 and blocked.buffer[beforeRefusal + 12] == 20
assert blocked.length == beforeRefusal + capacityRefusal.len and blocked.deadline == originalDeadline
blocked.failed(4400)
assert blocked.nextEvent == 12 # Failure retires bytes, never the process-wide correlation namespace.
let offline = blocked.dialing(4500, Timestamp(45), remoteIdentity, remoteAddress, 9000)
assert uint64(offline) == 12 and blocked.nextEvent == 13 and blocked.length == 0
blocked.nextEvent = high(uint64)
blocked.dialOutcome(4600, Timestamp(46), offline, false)
assert not blocked.enabled and blocked.nextEvent == high(uint64) # Exhaustion disables rather than wraps.
blocked.close()
echo "telemetry ok"

# Moving a client transfers its live task; closing the moved source cannot retire the destination.
block moved_client:
  var destination = default(Client)
  block:
    var source = default(Client)
    assert source.configure("localhost:1", parsed.value)
    source.begin(0, Timestamp(0))
    assert source.stream.active and source.opened
    destination = move(source)
    assert not source.enabled and not source.opened and not source.stream.active
    source.close()
  assert destination.stream.active and destination.enabled
  destination.close()

proc inspectBinding(fd: cint, address: pointer, size: ptr SockLen): cint {.
    importc: "getsockname", header: "<sys/socket.h>".}
  ## Observe the kernel-selected collector port using its initialized native address type.

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Give passive I/O continuations a bounded turn while the test collector drains bytes.

proc collectorDelivery(ipv6: bool, identity: array[32, byte]) =
  ## Exercise the public task connect path and independently capture exact JIP-3 wire bytes.
  let host = if ipv6: "[::1]" else: "127.0.0.1"
  var binding = default(Client)
  assert binding.configure(host & ":1", parsed.value)
  let family = if ipv6: nativesocket.AF_INET6 else: nativesocket.AF_INET
  let listener = socket(cint(ord(family)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert listener >= 0 and nonblocking(listener), "create the numeric loopback collector"
  defer: discard posix.close(listener)
  var port = 0'u16
  if ipv6:
    binding.address6.sin6_port = 0
    assert bindSocket(listener, addr binding.address6, SockLen(sizeof(Sockaddr_in6))) == 0
    var size = SockLen(sizeof(Sockaddr_in6))
    assert inspectBinding(listener, addr binding.address6, addr size) == 0
    port = networkPort(binding.address6.sin6_port)
  else:
    binding.address.sin_port = 0
    assert bindSocket(listener, addr binding.address, SockLen(sizeof(Sockaddr_in))) == 0
    var size = SockLen(sizeof(Sockaddr_in))
    assert inspectBinding(listener, addr binding.address, addr size) == 0
    port = networkPort(binding.address.sin_port)
  assert port > 0 and listenSocket(listener, 1) == 0
  var client = default(Client)
  assert client.configure(host & ":" & $port, parsed.value)
  var collector = -1.cint
  defer:
    if collector >= 0: discard posix.close(collector)
  var received = newSeq[byte]()
  for attempt in 0..<2000:
    # Registration is delivered before any application observations are queued.
    client.tick(0, Timestamp(0), 0)
    if collector < 0:
      collector = acceptSocket(listener, nil, nil)
      if collector >= 0: assert nonblocking(collector)
    if collector >= 0:
      var bytes = default(array[2048, byte])
      let count = receive(collector, addr bytes[0], csize_t(bytes.len), 0)
      if count > 0:
        for index in 0..<count: received.add(bytes[index])
    if received.len >= hello.len: break
    discard pauseMicros(1000)
  assert received == hello, "numeric collector receives exact registration"
  assert client.nextEvent == 0 and not client.connecting
  client.peerDisconnected(1, Timestamp(23), identity)
  received = @[]
  for attempt in 0..<2000:
    # The same Writer delivers the following lifecycle frame without HTTP or text conversion.
    client.tick(1, Timestamp(1), 0)
    var bytes = default(array[2048, byte])
    let count = receive(collector, addr bytes[0], csize_t(bytes.len), 0)
    if count > 0:
      for index in 0..<count: received.add(bytes[index])
    if received.len >= closed.len: break
    discard pauseMicros(1000)
  assert received == closed and client.nextEvent == 1
  client.close()

for ipv6 in [false, true]:
  # Both address families are required; missing IPv6 support is a failure, not a skip.
  collectorDelivery(ipv6, remoteIdentity)
ioring.shutdown()
