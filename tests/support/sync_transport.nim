# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent literal UP0/CE128 TLS server for continuous synchronization witnesses.
import std/[assertions, envvars]
import ../../src/quic/transport
import "../../src/jamnp-s/protocol"
import "../../src/jamnp-s/announcements"
import ../../src/codec/header

type
  SyncWireBlock* = object ## Independently prepared wire bytes indexed by exact canonical parent.
    parent*: array[32, byte]
    bytes*: seq[byte]
  Response = object ## Sixteen fixed stream slots keep native work and retention bounded.
    stream: NativeStream
    input, output: seq[byte]
    offset: int
    up0, writing, handshake: bool
  SyncResponder* = object ## Explicit close retires every callback before fixture storage can move.
    transport: Transport
    responses: array[16, Response]
    catalog*: seq[SyncWireBlock]
    initial: seq[byte]
    empty*, corrupt*: bool
    requests*: int
    expectedHeader*: seq[byte]
    targetObserved*: bool
    handshakes*: int
    receivedFinal*: AnnouncedBlock

proc `=copy`(destination: var SyncResponder, source: SyncResponder) {.error.}
  ## The native callback points to this exact stable fixture address.
proc `=dup`(source: SyncResponder): SyncResponder {.error.}
  ## No implicit sequence retention may duplicate the native server owner.
proc frame(body: seq[byte]): seq[byte] =
  ## Test-only framing uses literal little-endian E4, independently of production encoders.
  result = @[]
  for index in 0..<4: result.add(byte((uint64(body.len) shr (8 * index)) and 255))
  for octet in body: result.add(octet)
proc append(body: var seq[byte], claim: AnnouncedBlock) =
  ## Fixed hash/slot fields have independent literal byte expectations.
  for octet in array[32, byte](claim.hash): body.add(octet)
  for index in 0..<4: body.add(byte((uint32(claim.slot) shr (8 * index)) and 255))
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Real certificate/SAN verification remains enabled for test-generated TLS identities.
  cint(validPeer(cast[ptr byte](der), length, []))
proc event(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## One bounded read/write per callback; this responder never decodes or executes a block.
  let server = cast[ptr SyncResponder](user)
  var found = -1
  for index in 0..<16:
    if server.responses[index].stream == stream: found = index
  if event == 0:
    for index in 0..<16:
      if found < 0 and server.responses[index].stream == NativeStream(nil): found = index
    assert found >= 0, "bounded fixture stream slots"
    server.responses[found] = Response(stream: stream)
    wantRead(stream, 1)
    return
  if found < 0: return # Reset/late native events cannot target an unrelated slot.
  let response = addr server.responses[found]
  case event
  of 1:
    var buffer = default(array[4096, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    assert count >= 0 and count <= int64(buffer.len), "fixture native read"
    assert response.input.len + int(count) <= 8192, "bounded fixture request"
    for index in 0..<int(count): response.input.add(buffer[index])
    if response.up0 or (response.input.len > 0 and response.input[0] == 0):
      if not response.up0:
        var tail = newSeq[byte](response.input.len - 1)
        for index in 0..<tail.len: tail[index] = response.input[index + 1]
        response.input = tail # Strip exactly one initiating kind byte, independent of subsequent frames.
      response.up0 = true
      if response.output.len == 0:
        response.output = server.initial
        response.writing = true
        wantWrite(stream, 1) # UP0 responds without waiting for FIN on the persistent stream.
      var cursor = 0
      while response.input.len - cursor >= 4:
        var size = 0'u64
        for index in 0..<4: size = size or (uint64(response.input[cursor + index]) shl (8 * index))
        assert size > 0 and size <= 4096, "bounded incoming fixture UP0 frame"
        if size > uint64(response.input.len - cursor - 4): break
        if response.handshake:
          var matches = server.expectedHeader.len > 0 and int(size) == server.expectedHeader.len + 36
          if matches:
            for index in 0..<server.expectedHeader.len:
              if response.input[cursor + 4 + index] != server.expectedHeader[index]: matches = false
          if matches: server.targetObserved = true # A whole exact header message witnesses canonical client publication.
        else:
          assert size >= 37, "independent UP0 handshake Final extent"
          var digest = default(array[32, byte])
          for index in 0..<32: digest[index] = response.input[cursor + 4 + index]
          var slot = 0'u32
          for index in 0..<4:
            slot = slot or (uint32(response.input[cursor + 36 + index]) shl (8 * index))
          server.receivedFinal = AnnouncedBlock(hash: AnnouncedHeaderHash(digest), slot: HeaderSlot(slot))
          inc server.handshakes
          response.handshake = true # Read the actual outgoing Final bytes independently, before any child announcement.
        cursor += 4 + int(size)
      var pending = newSeq[byte](response.input.len - cursor)
      for index in 0..<pending.len: pending[index] = response.input[cursor + index]
      response.input = pending # Retain only one incomplete bounded frame across arbitrary fragmentation.
      if count == 0:
        readDone(stream)
        wantRead(stream, 0)
    elif count == 0:
      assert response.input.len == 42, "literal CE128 request extent"
      var expected = default(array[42, byte])
      expected[0] = 128
      expected[1] = 37
      expected[38] = 1
      for index in 5..<37: expected[index] = response.input[index]
      for index in 0..<42: assert expected[index] == response.input[index], "literal CE128 request bytes"
      readDone(stream)
      wantRead(stream, 0)
      var parent = default(array[32, byte])
      for index in 0..<32: parent[index] = response.input[index + 5]
      var body: seq[byte] = @[]
      if not server.empty:
        for child in server.catalog:
          if child.parent == parent: body = child.bytes
      if server.corrupt and body.len > 0:
        var damaged = newSeq[byte](body.len)
        for index, octet in body: damaged[index] = octet
        damaged[damaged.len - 1] = damaged[damaged.len - 1] xor 1
        body = damaged # Invalid seals preserve exact block framing and leave the healthy catalog unchanged.
      response.output = frame(body)
      response.writing = true
      inc server.requests
      wantWrite(stream, 1)
  of 2:
    if not response.writing: return
    if response.offset < response.output.len:
      let remaining = min(71, response.output.len - response.offset)
      let count = streamWrite(stream, addr response.output[response.offset], csize_t(remaining))
      if count == -2: return
      assert count > 0 and count <= int64(remaining), "fixture native write"
      response.offset += int(count)
    if response.offset == response.output.len:
      response.writing = false
      wantWrite(stream, 0)
      discard streamFlush(stream)
      if not response.up0: streamFin(stream) # CE128 retires while UP0 remains available for later targets.
  of 3:
    response[] = Response()
  of 4:
    wantRead(stream, 0)
    wantWrite(stream, 0)
  else: discard # Unknown native events carry no fixture authority.

proc open*(server: var SyncResponder, anchor: AnnouncedBlock,
    leaves: seq[AnnouncedBlock]): uint16 =
  ## Literal handshake construction intentionally does not call production UP0 encoders.
  assert leaves.len <= 63
  var body: seq[byte] = @[]
  body.append(anchor)
  body.add(byte(leaves.len))
  for leaf in leaves: body.append(leaf)
  server.initial = frame(body)
  assert server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr server, verify, event, multi = true)
  server.transport.localPort
proc poll*(server: var SyncResponder) =
  ## The test explicitly interleaves native server work with ordinary host ticks.
  assert server.transport.pollTransport(0)
proc announce*(server: var SyncResponder, header: OwnedHeader, anchor: AnnouncedBlock) =
  ## Append an independently framed complete header update after all earlier output was sent.
  var body = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(body).error == HeaderError.None
  body.append(anchor)
  let message = frame(body)
  for index in 0..<16:
    let response = addr server.responses[index]
    if response.up0 and response.stream != NativeStream(nil):
      assert not response.writing
      response.output = message
      response.offset = 0
      response.writing = true
      wantWrite(response.stream, 1)
proc disconnect*(server: var SyncResponder) =
  ## Reset only actual persistent sources; readiness must revoke on the next client poll.
  for index in 0..<16:
    if server.responses[index].up0:
      streamAbort(server.responses[index].stream)
proc close*(server: var SyncResponder) =
  ## Synchronous engine retirement precedes release of response storage.
  server.transport.closeTransport()
