# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical CE128 selections and independent actual TLS request/FIN/reset transcripts.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../support/jamnp_topology_fixture
import ../../../src/jamnp-s/[block_service, protocol]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, natural]
import ../../../src/quic/transport

type
  Server = object ## Stable callback storage owns fixed routes; canonical work stays in the host loop.
    transport: Transport
    routes: array[4, BlockRequestRoute]
  Client = object ## One original stream retains independent transcript and termination observations.
    transport: Transport
    stream: NativeStream
    output, input: seq[byte]
    offset: int
    finAllowed, sentFin, receivedFin, reset, opened: bool
    expected: array[32, byte]
proc `=copy`(destination: var Server, source: Server) {.error.}
  ## Native contexts must never follow a copied stack address.
proc `=dup`(source: Server): Server {.error.}
  ## Copy prevention applies to initialization lowering as well.
proc `=copy`(destination: var Client, source: Client) {.error.}
  ## Client storage remains fixed until transport retirement.
proc `=dup`(source: Client): Client {.error.}
  ## Duplication cannot acquire a second native callback context.
proc serverVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Maintained certificate validation is independent of these read-only protocol assertions.
  cint(validPeer(cast[ptr byte](der), length, []))
proc clientVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Pin the configured server identity, never its endpoint or a claimed request hash.
  let owner = cast[ptr Client](user)
  cint(validPeer(cast[ptr byte](der), length, owner.expected))
proc serverEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Admit at most four borrowed routes; host enforces a deadline outside native callbacks.
  let owner = cast[ptr Server](user)
  if event == 0:
    for index in 0..<owner.routes.len:
      if owner.routes[index].handle == NativeStream(nil):
        assert owner.routes[index].bindStream(stream) == BlockServiceError.None
        return # Fixed capacity never expands under hostile stream creation.
    streamAbort(stream)
    return
  for index in 0..<owner.routes.len:
    if owner.routes[index].handle == stream:
      owner.routes[index].event(stream, event)
      return # Each event belongs to one exact still-live native handle.
proc clientEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Independently assembled bytes and observed FIN test the production responder, not its encoder.
  let owner = cast[ptr Client](user)
  if event != 0 and owner.stream != stream: return # Late retirement of an older stream cannot revoke its successor.
  case event
  of 0:
    owner.stream = stream
    owner.opened = true
    wantRead(stream, 1)
    wantWrite(stream, 1)
  of 1:
    var buffer = default(array[4096, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    if count <= 0:
      if count == 0:
        owner.receivedFin = true
        readDone(stream)
      else:
        owner.reset = true # Negative read is transport rejection, never a valid empty frame.
      wantRead(stream, 0)
      return
    assert count <= int64(buffer.len) and owner.input.len+int(count) <= MaxBlockReplyBytes
    for index in 0..<int(count): owner.input.add(buffer[index])
  of 2:
    if owner.offset < owner.output.len:
      let written = streamWrite(stream, addr owner.output[owner.offset], csize_t(
          owner.output.len-owner.offset))
      if written == -2: return
      assert written >= 0 and written <= int64(owner.output.len-owner.offset)
      owner.offset += int(written)
    if owner.offset == owner.output.len:
      wantWrite(stream, 0)
      discard streamFlush(stream)
      if owner.finAllowed and not owner.sentFin:
        owner.sentFin = true
        streamFin(stream) # A separate host-controlled gate witnesses waiting for request FIN.
  of 3: owner.stream = NativeStream(nil) # No further access follows native close.
  of 4:
    owner.reset = true
    wantRead(stream, 0)
    wantWrite(stream, 0)
  else: discard # No other events imply protocol progress.
proc source(atSlot: uint32, parent = unavailableGenesis(), body = true,
    blobBytes = 0): BlockSnapshotResult =
  ## Structural complete-map fixtures bind seven empty extrinsic counts to exact sealed headers.
  let captured = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)],
    atSlot = atSlot, parent = parent)
  assert captured.error == GenesisError.None
  if not body: return captured
  var wire = newSeq[byte](304)
  assert encodeOwnedHeader(captured.value.header, wire.toOpenArray(0, 296)).error ==
      HeaderError.None
  for index in 297..<304: wire[index] = 0 # Seven canonical empty extrinsic counts, no frame prefix.
  if blobBytes > 0:
    wire.setLen(297)
    wire.add(0) # Empty ticket sequence, followed by one structural preimage record.
    wire.add(1)
    for index in 0..<4: wire.add(0) # Service index zero is structurally valid; no execution is claimed.
    let length = encode(JamNatural(uint64(blobBytes)))
    for index in 0..<length.len: wire.add(length.bytes[index])
    for index in 0..<blobBytes: wire.add(0) # Oversized local body checks refusal before an output copy.
    for index in 0..<5: wire.add(0) # Guarantees, assurances, and three dispute subsequences.
  result = withBlockBody(captured.value, wire)
  assert result.error == GenesisError.None
proc request(hash: BlockHash, direction: byte, maximum: uint32): seq[byte] =
  ## Literal wire layout independently pins the CE128 selector and one E4 message.
  result = @[128'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): result.add(octet)
  result.add(direction)
  for index in 0..<4: result.add(byte((maximum shr (8*index)) and 255))
proc query(wire: seq[byte]): BlockQuery =
  ## Tests explicitly check the decoder before extracting its admitted request.
  let decoded = decodeBlockQuery(wire.toOpenArray(5, 41))
  assert decoded.error == BlockServiceError.None
  decoded.value
proc framed(blocks: openArray[BlockSnapshotResult]): seq[byte] =
  ## Independent expected transcript contains one E4 around bare concatenated complete blocks.
  result = @[0'u8, 0, 0, 0]
  for snapshot in blocks:
    for octet in snapshot.value.blockBody: result.add(octet)
  for index in 0..<4: result[index] = byte((uint32(result.len-4) shr (8*index)) and 255)
proc rawKey(path: string): array[32, byte] {.raises.} =
  ## Raw fixture identities do not depend on production certificate extraction.
  let bytes = readFile(path)
  assert bytes.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(bytes[index])
proc exchange(view: ChainView, wire, expected: seq[byte], refused = false,
    holdFin = false, recover = false) {.raises.} =
  ## Actual TLS engines retire on every exit; finite deadlines expose stalled or prematurely answered streams.
  var server = default(Server)
  var client = default(Client)
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport)
  assert openTransport(server.transport, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, serverVerify, serverEvent, multi = true)
  client.expected = rawKey(getEnv("RAGNAROK_TEST_PEER_A"))
  client.output = wire
  client.finAllowed = not holdFin
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr client, clientVerify, clientEvent)
  assert client.transport.connectTransport(server.transport.localPort)
  let started = getMonoTime()
  let deadline = started+initDuration(seconds = 3)
  var requested = false
  var jobs = 0
  var recovered = false
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0)
    assert client.transport.pollTransport(0)
    if not requested and client.transport.authenticatedConnections > 0:
      requested = true
      client.transport.openStream() # Engine-ready is not yet proof of a response or accepted FIN.
    if holdFin and not client.finAllowed and client.opened and getMonoTime()-started > initDuration(
        milliseconds = 80):
      assert jobs == 0 and client.input.len == 0, "server must wait for the request FIN"
      client.finAllowed = true
      if client.stream != NativeStream(nil): wantWrite(client.stream, 1)
    for index in 0..<server.routes.len:
      let incoming = server.routes[index].takeRequest()
      if incoming.error == BlockServiceError.None:
        inc jobs
        let reply = serveBlocks(view, incoming.value) # Canonical read occurs after all native callbacks have returned.
        if reply.error == BlockServiceError.None:
          let unrelated = serveBlocks(view, query(request(view.bestBlock.value.blockHash, 1, 0)))
          assert unrelated.error == BlockServiceError.None
          assert server.routes[index].respond(unrelated.value) == BlockServiceError.InvalidRequest
          assert server.routes[index].respond(reply.value) == BlockServiceError.None
        else:
          server.routes[index].reject() # Unavailable data resets instead of inventing an empty success.
    if refused and client.reset:
      if not recover or recovered: break
      assert client.transport.transportStatus == 1, "reset must preserve the authenticated connection"
      recovered = true
      client.output = request(view.bestBlock.value.blockHash, 1, 1)
      client.input = @[]
      client.offset = 0
      client.reset = false
      client.receivedFin = false
      client.sentFin = false
      client.finAllowed = true
      client.opened = false
      client.transport.openStream() # A second stream on this same connection must still complete.
    if recovered and client.receivedFin: break
    if not refused and client.receivedFin: break
  if recover:
    assert recovered and client.receivedFin and not client.reset and client.sentFin
    assert jobs == 2 and client.input == framed([view.bestBlock]), "reset must preserve another stream on the same connection"
  elif refused:
    if not client.reset:
      echo "refusal diagnostic: request=", wire.len, " jobs=", jobs, " EOF=", client.receivedFin,
          " bytes=", client.input.len
    assert client.reset, "malformed or unavailable request must be reset"
  else:
    assert client.receivedFin and not client.reset and client.sentFin
    assert jobs == 1 and client.input == expected, "exact block order, framing and both FINs"
proc main() {.raises.} =
  ## Both directions, retained suffixes, unknown anchors and malformed requests get independent witnesses.
  var history: seq[BlockSnapshotResult] = @[source(7)]
  for index in 1..65:
    history.add(source(uint32(index+7), history[^1])) # A window beyond the response cap proves bounded selection.
  let large = restoreLocalChainView(history, limit = ElementLimit(66))
  assert large.error == ViewAdvanceError.None
  let capped = serveBlocks(large.value, query(request(history[0].value.blockHash, 0,
      0xffffffff'u32)))
  assert capped.error == BlockServiceError.None
  assert capped.value.bytes == framed(history.toOpenArray(1, 64))
  let oversized = source(7, blobBytes = MaxBlockReplyBytes)
  let oversizedView = genesisView(oversized)
  let oversizeReply = serveBlocks(oversizedView, query(request(oversized.value.blockHash, 1, 1)))
  assert oversizeReply.error == BlockServiceError.LimitExceeded
  let smallChild = source(8, oversized)
  let mixed = restoreLocalChainView([oversized, smallChild])
  assert mixed.error == ViewAdvanceError.None
  let prefix = serveBlocks(mixed.value, query(request(smallChild.value.blockHash, 1, 2)))
  assert prefix.error == BlockServiceError.None and prefix.value.bytes == framed([smallChild])
  let first = source(7)
  let second = source(8, first)
  let third = source(9, second)
  let restored = restoreLocalChainView([first, second, third])
  assert restored.error == ViewAdvanceError.None
  let view = restored.value
  exchange(view, request(first.value.blockHash, 0, 0xffffffff'u32), framed([second, third]),
      holdFin = true)
  exchange(view, request(third.value.blockHash, 1, 3), framed([third, second, first]))
  exchange(view, request(second.value.blockHash, 1, 1), framed([second]))
  exchange(view, request(third.value.blockHash, 0, 2), framed([]))
  exchange(view, request(first.value.blockHash, 0, 0), framed([]))
  let suffix = restoreLocalChainView([second, third])
  assert suffix.error == ViewAdvanceError.None
  exchange(suffix.value, request(first.value.blockHash, 0, 2), framed([second, third]))
  exchange(suffix.value, request(third.value.blockHash, 1, 10), framed([third, second]))
  exchange(view, request(BlockHash(default(array[32, byte])), 1, 1), @[], refused = true,
      recover = true)
  let headerOnly = source(7, body = false)
  exchange(genesisView(headerOnly), request(headerOnly.value.blockHash, 1, 1), @[], refused = true)
  exchange(view, request(first.value.blockHash, 2, 1), @[], refused = true)
  var extra = request(first.value.blockHash, 0, 1)
  extra.add(0)
  exchange(view, extra, @[], refused = true)
  let short = @[128'u8, 37, 0, 0, 0, 1]
  exchange(view, short, @[], refused = true)
  assert serveBlocks(view, default(BlockQuery)).error == BlockServiceError.InvalidRequest
  assert decodeBlockQuery(@[]).error == BlockServiceError.InvalidRequest
  let empty = default(ChainView)
  let admitted = query(request(first.value.blockHash, 0, 1))
  assert serveBlocks(empty, admitted).error ==
      BlockServiceError.Unavailable
  echo "jamnp block service: canonical directions and TLS FIN boundaries passed"
try:
  main()
except:
  quit 2 # Fixture setup failures are never successful protocol evidence.
