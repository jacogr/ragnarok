# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS regression for UP0 greatest-ID replacement, delayed lower-ID arrival, pending-route
## replacement and connection isolation. Include the production responder to inspect private
## route ownership without exporting test-only accessors.

import std/[envvars, monotimes, times, syncio]
include "../../../src/jamnp-s/devnet"
import ../../../src/codec/bounded

type
  RawStream = object ## One test stream keeps its original number after final close for independent assertions.
    handle: NativeStream
    number: NativeStreamId
    output, input: seq[byte]
    offset: int
    closed, reset: bool
  RawClient = object ## Stable test callback owner; both engines retire before this stack storage leaves scope.
    transport: Transport
    streams: array[3, RawStream]
    opened: int
    active: bool
    expected: array[32, byte]

# Composite fixtures cannot relocate their retained native callback addresses.
proc `=copy`(destination: var RawClient, source: RawClient) {.error.}
# Duplication has the same stable-address constraint.
proc `=dup`(source: RawClient): RawClient {.error.}

proc rawVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Pin the real server's JAMNP-S identity independently on each outgoing connection.
  let client = cast[ptr RawClient](user)
  cint(validPeer(cast[ptr byte](der), length, client.expected))

proc rawEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Send independently assembled bytes and retain native closure/reset observations per original stream.
  let client = cast[ptr RawClient](user)
  var found = -1
  for i in 0..<client.opened:
    if client.streams[i].handle == stream: found = i
  if event == 0:
    assert client.opened < client.streams.len
    found = client.opened
    inc client.opened
    client.streams[found] = RawStream(handle: stream, number: stream.streamId)
    wantRead(stream, 1)
    return # The host selects write order after all original IDs are known.
  if found < 0: return # Already retired handles cannot borrow a new stream slot.
  let slot = addr client.streams[found]
  case event
  of 1:
    var buffer = default(array[128, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    if count <= 0:
      slot.reset = true
      wantRead(stream, 0)
      return # No fixture sends FIN; early end is the responder's rejection.
    assert count <= int64(buffer.len) and slot.input.len+int(count) <= 128
    for i in 0..<int(count): slot.input.add(buffer[i])
  of 2:
    if slot.offset < slot.output.len:
      let count = streamWrite(stream, addr slot.output[slot.offset], csize_t(
          slot.output.len-slot.offset))
      if count == -2: return
      assert count > 0 and count <= int64(slot.output.len-slot.offset)
      slot.offset += int(count)
    if slot.offset == slot.output.len:
      wantWrite(stream, 0)
      discard streamFlush(stream) # UP0 remains open; the test never half-closes its request direction.
  of 3:
    slot.closed = true
    slot.handle = NativeStream(nil)
  of 4:
    slot.reset = true
    wantRead(stream, 0)
    wantWrite(stream, 0)
  else: discard # Unrelated events cannot acknowledge a handshake or replace a peer.

proc key(path: string): array[32, byte] {.raises.} =
  ## The generated fixture contract supplies exact raw Ed25519 public-key files.
  let bytes = readFile(path)
  assert bytes.len == 32
  result = default(array[32, byte])
  for i in 0..<32: result[i] = byte(bytes[i])

proc drive(server: var DevnetNetwork, first, second: var RawClient) =
  ## Progress each endpoint independently so one delayed stream cannot stall other connections.
  assert server.poll()
  if first.active: assert first.transport.pollTransport(0)
  if second.active: assert second.transport.pollTransport(0)

proc openClient(client: var RawClient, port: uint16, serverKey: array[32, byte], cert,
    key: string): bool =
  ## Install callback storage before connecting; caller retains it through explicit teardown.
  client.expected = serverKey
  client.active = openTransport(client.transport, false, false, 0, cert, key,
      "jamnp-s/1/00000000", addr client, rawVerify, rawEvent)
  client.active and client.transport.connectTransport(port)

proc awaitOpened(server: var DevnetNetwork, first, second: var RawClient, count: int,
    useSecond: bool) =
  ## A fixed two-second deadline includes actual handshake/native stream creation progress.
  let deadline = getMonoTime()+initDuration(seconds = 2)
  while getMonoTime() < deadline:
    drive(server, first, second)
    let opened = if useSecond: second.opened else: first.opened
    if opened == count: return
  assert false, "native stream-open deadline"

proc connect(server: var DevnetNetwork, first, second: var RawClient, useSecond: bool) =
  ## Wait for authenticated transport before asking LSQUIC to create any application stream.
  let deadline = getMonoTime()+initDuration(seconds = 2)
  while getMonoTime() < deadline:
    drive(server, first, second)
    let status = if useSecond: second.transport.transportStatus else: first.transport.transportStatus
    if status == 1: return
  assert false, "TLS connection deadline"

proc send(client: var RawClient, index: int, complete: bool) =
  ## Independently encode selector0 and E4(37), finalized block zero and compact leaf count zero.
  var wire = @[0'u8]
  if complete:
    wire.add(37)
    for i in 0..<3: wire.add(0)
    for i in 0..<37: wire.add(0)
  client.streams[index].output = wire
  client.streams[index].offset = 0
  wantWrite(client.streams[index].handle, 1)

proc settled(server: var DevnetNetwork, first, second: var RawClient, known: int,
    sum: uint64, firstMask, secondMask: int) =
  ## Require exact live claims and real rejection/close observations before accepting a routing transition.
  let deadline = getMonoTime()+initDuration(seconds = 2)
  while getMonoTime() < deadline:
    drive(server, first, second)
    var count = 0
    var observed = 0'u64
    var retired = true
    for response in server.responses:
      if response.announcement.active:
        inc count
        observed += uint64(response.announcement.handle.streamId)
    for i in 0..<3:
      if (firstMask and (1 shl i)) != 0 and not (first.streams[i].closed or first.streams[i].reset):
        retired = false
      if (secondMask and (1 shl i)) != 0 and not (second.streams[i].closed or second.streams[i].reset):
        retired = false
    if count == known and observed == sum and retired: return
  assert false, "persistent selection/retirement deadline"

proc main() {.raises.} =
  ## Keep both peers authenticated while exercising out-of-order kind discovery on one connection.
  for number in 0'u64..255'u64:
    assert persistentInitiator(NativeStreamId(number)) == ((number and 3) == 0)
  assert not persistentInitiator(NativeStreamId(1'u64 shl 62))
  assert preferPersistent(NativeStreamId(8), NativeStreamId(4))
  assert not preferPersistent(NativeStreamId(4), NativeStreamId(8))
  assert not preferPersistent(NativeStreamId(4), NativeStreamId(4))
  var server = default(DevnetNetwork)
  var first = default(RawClient)
  var second = default(RawClient)
  var peers = default(array[6, array[32, byte]])
  peers[0] = key(getEnv("RAGNAROK_TEST_PEER_A"))
  peers[1] = key(getEnv("RAGNAROK_TEST_PEER_B"))
  let limits = AnnouncementLimits(leaves: ElementLimit(4), bytes: ByteLimit(8192),
      header: fullHeaderConfig(ByteLimit(4096)))
  assert server.enableAnnouncements(default(AnnouncementHandshake), limits) ==
      AnnouncementError.None
  try:
    assert server.open(0, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
        "jamnp-s/1/00000000", peers)
    assert openClient(first, server.localPort, peers[0], getEnv("RAGNAROK_TEST_CERT_B"),
        getEnv("RAGNAROK_TEST_KEY_B"))
    connect(server, first, second, false)
    for i in 0..<3: first.transport.openStream()
    awaitOpened(server, first, second, 3, false)
    assert uint64(first.streams[0].number) == 0
    assert uint64(first.streams[1].number) == 4
    assert uint64(first.streams[2].number) == 8
    send(first, 0, true)
    settled(server, first, second, 1, 0, 0, 0)
    send(first, 2, true)
    settled(server, first, second, 1, 8, 1, 0)
    send(first, 1, true)
    settled(server, first, second, 1, 8, 3, 0)
    # A second connection owns its own UP0 ID space even though its IDs are lower than the first peer's8.
    assert openClient(second, server.localPort, peers[0], getEnv("RAGNAROK_TEST_CERT"),
        getEnv("RAGNAROK_TEST_KEY"))
    connect(server, first, second, true)
    for i in 0..<2: second.transport.openStream()
    awaitOpened(server, first, second, 2, true)
    send(second, 0, false)
    let deadline = getMonoTime()+initDuration(seconds = 2)
    var pendingSeen = false
    while getMonoTime() < deadline and not pendingSeen:
      drive(server, first, second)
      var bound = 0
      for response in server.responses:
        if response.announcement.handle != NativeStream(nil) and
            not response.announcement.failed: inc bound
      pendingSeen = bound == 2
    assert pendingSeen, "pending UP0 kind was bound independently of handshake completion"
    send(second, 1, true)
    settled(server, first, second, 2, 12, 3, 1)
    assert not first.streams[2].closed and not first.streams[2].reset
    assert not second.streams[1].closed and not second.streams[1].reset
  finally:
    closeTransport(first.transport)
    closeTransport(second.transport)
    first.active = false
    second.active = false
    server.close() # All foreign callbacks retire before enclosing stack ownership ends.

try:
  main()
except:
  quit 2 # Missing fixture files remain failures, not skipped protocol checks.
echo "JAMNP-S: greatest UP0 ID, late lower ID, pending replacement and peer isolation passed"
