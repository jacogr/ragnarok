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
let dialing = connectingOut(Timestamp(17), remoteIdentity, remoteAddress, 9000)
assert dialing.len == 63 and number(dialing, 0, 4) == 59
assert number(dialing, 4, 8) == 17 and dialing[12] == 24
assert dialing[13] == 123 and dialing[60] == 1 and number(dialing, 61, 2) == 9000
let established = connectedOut(Timestamp(19), EventId(0x0102030405060708'u64))
assert established.len == 21 and number(established, 0, 4) == 17 and established[12] == 26
assert number(established, 13, 8) == 0x0102030405060708'u64
let refused = connectOutFailed(Timestamp(20), EventId(7))
assert refused.len == 22 and number(refused, 0, 4) == 18 and refused[12] == 25
assert number(refused, 13, 8) == 7 and refused[21] == 0 # Empty reason is canonical.

# Strict numeric endpoint parsing fails atomically and never creates descriptors.
for endpoint in ["", "localhost", "localhost:0", "localhost:65536", "127.0.0.1:-1",
    "127.0.0.1: 1", "127.0.0.1:1:2", "127.0.0.999:9000", "127.0.0.1\0x:9000"]:
  var invalid = default(Client)
  assert not invalid.configure(endpoint, parsed.value)
  assert not invalid.enabled and not invalid.opened
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
assert queued.length == 47 and queued.offset == 0 and queued.deadline == 5010
# Every copied byte is retained independently of the producer sequence.
for i in 0..<sample.len: assert queued.buffer[i] == sample[i]
queued.offset = 5
queued.lost = 8
queued.failed(20)
assert queued.length == 0 and queued.offset == 0 and queued.lost == 0
assert queued.retryAt == 5020
# A Unix stream pair gives deterministic backpressure without a collector process or network race.
proc socketPair(domain, kind, protocol: cint, descriptors: ptr cint): cint {.importc: "socketpair",
    header: "<sys/socket.h>".}
# Receive consumes only a caller-owned bounded buffer and never retains it.
proc receive(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
var descriptors = [-1.cint, -1.cint]
assert socketPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0,
    addr descriptors[0]) == 0
var blocked = default(Client)
assert blocked.configure("localhost:9000", parsed.value)
blocked.fd = descriptors[0]
blocked.opened = true
assert fcntl(descriptors[0], F_SETFL, O_NONBLOCK) == 0
assert fcntl(descriptors[1], F_SETFL, O_NONBLOCK) == 0
var scratch = default(array[4096, byte])
var filled = false
# Saturate at most 32 MiB of kernel writes; no syscall can block after O_NONBLOCK.
for iteration in 0..<8192:
  let sent = sendBytes(descriptors[0], addr scratch[0], csize_t(scratch.len), 0)
  if sent < 0:
    assert osLastError() == OSErrorCode(EAGAIN) or osLastError() == OSErrorCode(EWOULDBLOCK)
    filled = true
    break
assert filled
blocked.queue(sample, 0)
blocked.offset = 7 # Model a previously accepted prefix before collector backpressure.
blocked.tick(0, Timestamp(10), 7)
blocked.tick(2000, Timestamp(20), 7)
assert blocked.offset == 7 and blocked.length == sample.len and blocked.lost == 2
# Drain kernel filler completely without blocking or spinning indefinitely.
for iteration in 0..<8192:
  if receive(descriptors[1], addr scratch[0], csize_t(scratch.len), 0) < 0: break
blocked.tick(2500, Timestamp(25), 7)
assert blocked.length == 0
let suffix = receive(descriptors[1], addr scratch[0], csize_t(scratch.len), 0)
assert suffix == sample.len - 7
# A partial write resumes at its exact suffix, without duplicating frame bytes.
for i in 0..<suffix: assert scratch[i] == sample[i + 7]
blocked.tick(4000, Timestamp(40), 7)
let resumed = receive(descriptors[1], addr scratch[0], csize_t(scratch.len), 0)
assert resumed == 29 + sample.len
assert number(scratch, 4, 8) == 10 and number(scratch, 13, 8) == 20
assert number(scratch, 21, 8) == 2 and scratch[29 + 12] == 10
blocked.close()
discard posix.close(descriptors[1])
echo "telemetry ok"
