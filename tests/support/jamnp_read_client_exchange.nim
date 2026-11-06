# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent raw TLS responder checks client framing and completion after actual native retirement.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../src/quic/transport
import ../../src/jamnp-s/[protocol, read_stream, read_client, sharing_client, sharing_wire]
import ../../src/codec/bounded

type
  RawServer = object ## Callback-owned transcript and FIN gate remain stable through explicit transport close.
    transport: Transport
    stream: NativeStream
    request, expected, response: seq[byte]
    offset: int
    finAllowed, sentFin, requestFin: bool
  RawClient = object ## The production route outlives its native stream so host extraction can test physical-close ordering.
    transport: Transport
    route: ReadClientRoute
    sharing: bool
    sharingRoute: SharingClientRoute
    expected: array[32, byte]
    opened, closed: bool
    budget: uint64
proc `=copy`(destination: var RawServer, source: RawServer) {.error.}
  ## Native callbacks cannot follow copied test storage.
proc `=dup`(source: RawServer): RawServer {.error.}
  ## Initialization also preserves the one stable callback owner.
proc `=copy`(destination: var RawClient, source: RawClient) {.error.}
  ## The client route and native transport retain their original enclosing address.
proc `=dup`(source: RawClient): RawClient {.error.}
  ## Callback contexts may not be duplicated during ARC lowering.
proc serverVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Both certificates still pass the ordinary Ed25519/SAN checks before application bytes are used.
  cint(validPeer(cast[ptr byte](der), length, []))
proc clientVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Pin the raw fixture public identity independently of production certificate extraction.
  let client = cast[ptr RawClient](user)
  cint(validPeer(cast[ptr byte](der), length, client.expected))
proc serverEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Read the entire literal request/FIN before sending the independently supplied response bytes.
  let server = cast[ptr RawServer](user)
  case event
  of 0:
    assert server.stream == NativeStream(nil)
    server.stream = stream
    wantRead(stream, 1)
  of 1:
    var buffer = default(array[256, byte])
    let amount = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if amount == -2: return
    if amount > 0:
      assert amount <= int64(buffer.len) and server.request.len+int(amount) <= server.expected.len
      for index in 0..<int(amount): server.request.add(buffer[index])
    elif amount == 0:
      server.requestFin = true
      readDone(stream)
      wantRead(stream, 0)
      assert server.request == server.expected, "client sends one exact literal selector/E4/request before FIN"
      wantWrite(stream, 1)
    else:
      streamAbort(stream) # A reset is not a successful request FIN.
  of 2:
    if server.offset < server.response.len:
      let amount = streamWrite(stream, addr server.response[server.offset], csize_t(min(4096,
          server.response.len-server.offset)))
      if amount == -2: return
      assert amount >= 0 and amount <= int64(server.response.len-server.offset)
      server.offset += int(amount)
    if server.offset == server.response.len:
      wantWrite(stream, 0)
      discard streamFlush(stream)
      if server.finAllowed and not server.sentFin:
        server.sentFin = true
        streamFin(stream) # The host separately releases FIN after all response bytes have been flushed.
  of 3: server.stream = NativeStream(nil)
  of 4:
    wantRead(stream, 0)
    wantWrite(stream, 0)
    streamAbort(stream) # Explicitly retire our remaining direction after the client's rejection.
  else: discard # No other events imply transcript completion.
proc clientEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Both production clients use the same independent native responder/retirement observations.
  let client = cast[ptr RawClient](user)
  if event == 0:
    client.opened = true
    let bound = if client.sharing: client.sharingRoute.bindSharingClient(
        stream) else: client.route.bindStream(stream)
    assert bound == ReadError.None
    return
  let owned = uint64(if client.sharing: client.sharingRoute.bufferedBytes else: client.route.bufferedBytes)
  assert owned <= client.budget
  if client.sharing:
    client.sharingRoute.event(stream, event, ByteLimit(client.budget-owned))
  else:
    client.route.event(stream, event, ByteLimit(client.budget-owned))
  if event == 3: client.closed = true # Host extraction is delayed until actual native retirement.
proc runExchange(server: var RawServer, client: var RawClient, holdFin: bool) {.raises.} =
  ## Reuse one actual TLS/FIN driver for both fixed reads and the independent bounded sharing client.
  server.finAllowed = not holdFin
  let key = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert key.len == 32
  for index in 0..<32: client.expected[index] = byte(key[index])
  assert openTransport(server.transport, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, serverVerify, serverEvent, multi = true)
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr client, clientVerify, clientEvent)
  assert client.transport.connectTransport(server.transport.localPort)
  let start = getMonoTime()
  var issued = false
  let deadline = initDuration(seconds = if client.sharing: 8 else: 3)
  while getMonoTime()-start < deadline:
    assert server.transport.pollTransport(0) and client.transport.pollTransport(0)
    if not issued and client.transport.authenticatedConnections > 0:
      issued = true
      client.transport.openStream()
    if holdFin and not server.finAllowed and server.requestFin and server.offset ==
        server.response.len and getMonoTime()-start > initDuration(milliseconds = 60):
      let waiting = if client.sharing: client.sharingRoute.take().error else: client.route.take().error
      assert waiting == ReadError.Unavailable and not client.closed
      server.finAllowed = true
      wantWrite(server.stream, 1)
    if client.closed: break
  assert issued and client.opened and client.closed, "response route reaches actual native retirement"
proc exchangeClient*(kind: ReadKind, payload, response: seq[byte],
    failure = ReadError.None, holdFin = false, maximum = ByteLimit(MaxReadReplyBytes),
    budget = uint64(MaxReadReplyBytes)) {.raises.} =
  ## Fresh authenticated transports witness exact framing, failure reasons and no host success before FIN.
  var server = default(RawServer)
  var client = default(RawClient)
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport)
  let request = decodeReadRequest(kind, payload)
  assert request.error == ReadError.None
  assert client.route.configure(request.value, maximum) == ReadError.None
  client.budget = budget
  server.expected = case kind
    of ReadKind.Blocks: @[128'u8, 37, 0, 0, 0]
    of ReadKind.State: @[129'u8, 98, 0, 0, 0]
    of ReadKind.TicketProxy: @[131'u8, 21, 3, 0, 0]
    of ReadKind.TicketDistribution: @[132'u8, 21, 3, 0, 0]
    of ReadKind.Report: @[136'u8, 32, 0, 0, 0]
    of ReadKind.PreimageAnnouncement: @[142'u8, 40, 0, 0, 0]
    of ReadKind.Preimage: @[143'u8, 32, 0, 0, 0]
    of ReadKind.Availability: @[137'u8, 34, 0, 0, 0]
    of ReadKind.Audit: @[138'u8, 34, 0, 0, 0]
    of ReadKind.Bundle: @[147'u8, 32, 0, 0, 0]
    of ReadKind.AuditAnnouncement:
      var header = @[144'u8] # Independent literal CE144 selector and E4 extent preserve the bare-FIN upload transcript.
      for index in 0..<4: header.add(byte((uint32(payload.len) shr (8*index)) and 255))
      header
    of ReadKind.Judgment:
      var header = @[145'u8] # Independently frame the CE145 upload with its E4 payload length.
      for index in 0..<4: header.add(byte((uint32(payload.len) shr (8*index)) and 255))
      header
    of ReadKind.Assurance:
      var header = @[141'u8] # Independent literal CE141 selector, followed by its one E4-framed upload.
      for index in 0..<4: header.add(byte((uint32(payload.len) shr (8*index)) and 255))
      header
    of ReadKind.Guarantee, ReadKind.SegmentShards, ReadKind.ProvenSegmentShards, ReadKind.Segments:
      var header = @[byte(kind)]
      for index in 0..<4: header.add(byte((uint32(payload.len) shr (8*index)) and 255))
      header
  for octet in payload: server.expected.add(octet)
  server.response = response
  runExchange(server, client, holdFin)
  if failure == ReadError.None:
    let completed = client.route.take()
    assert completed.error == ReadError.None and completed.value.valid
    assert completed.value.bytes == response and completed.value.request.kind == kind
    assert client.route.take().error == ReadError.Unavailable
  else:
    assert client.route.error == failure, "first parser/limit failure survives native close"
    assert client.route.take().error == failure # No malformed/default outcome exposes a partial body.

proc exchangeSharingClient*(request: SharedWorkRequest, expectedRequest, response: seq[byte],
    failure = ReadError.None, holdFin = false, budget = 100'u64) {.raises.} =
  ## Literal independent selector/two-E4 bytes and actual native close verify sharing framing without a second test transport harness.
  var server = default(RawServer)
  var client = default(RawClient)
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport)
  client.sharing = true
  client.budget = budget
  assert client.sharingRoute.configureSharing(request) == ReadError.None
  server.expected = expectedRequest
  server.response = response
  runExchange(server, client, holdFin)
  let completed = client.sharingRoute.take()
  if failure == ReadError.None:
    assert completed.error == ReadError.None and completed.value.valid
    let payload = completed.value.bytes
    assert response.len == 100
    for index in 0..<payload.len: assert payload[index] == response[4+index]
    assert client.sharingRoute.take().error == ReadError.Unavailable
  else:
    assert completed.error == failure # The first framing/quota failure survives actual native retirement without any prefix.
