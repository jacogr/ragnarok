# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent raw TLS responder checks client framing and completion after actual native retirement.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../src/quic/transport
import ../../src/jamnp-s/[protocol, read_stream, read_client]
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
      assert amount <= int64(buffer.len) and server.request.len+int(amount) <= 103
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
  ## Only production framing handles inbound response bytes; native close is observed independently.
  let client = cast[ptr RawClient](user)
  if event == 0:
    client.opened = true
    assert client.route.bindStream(stream) == ReadError.None
    return
  let owned = uint64(client.route.bufferedBytes)
  assert owned <= client.budget
  client.route.event(stream, event, ByteLimit(client.budget-owned))
  if event == 3: client.closed = true # Extraction below is deliberately delayed until this exact real native event.
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
  for octet in payload: server.expected.add(octet)
  server.response = response
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
  while getMonoTime()-start < initDuration(seconds = 3):
    assert server.transport.pollTransport(0) and client.transport.pollTransport(0)
    if not issued and client.transport.authenticatedConnections > 0:
      issued = true
      client.transport.openStream()
    if holdFin and not server.finAllowed and server.requestFin and server.offset ==
        server.response.len and getMonoTime()-start > initDuration(milliseconds = 60):
      assert client.route.take().error == ReadError.Unavailable and not client.closed,
        "complete response bytes grant no successful reply before native FIN"
      server.finAllowed = true
      wantWrite(server.stream, 1)
    if client.closed: break
  assert issued and client.opened and client.closed, "response route reaches actual native retirement"
  if failure == ReadError.None:
    let completed = client.route.take()
    assert completed.error == ReadError.None and completed.value.valid
    assert completed.value.bytes == response and completed.value.request.kind == kind
    assert client.route.take().error == ReadError.Unavailable
  else:
    assert client.route.error == failure, "first parser/limit failure survives native close"
    assert client.route.take().error == failure # No malformed/default outcome exposes a partial body.
