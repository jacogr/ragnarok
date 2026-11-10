# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw authenticated TLS transcripts drive canonical reads outside native callbacks.

import std/[assertions, envvars, syncio, monotimes, times]
import ../../src/jamnp-s/[read_stream, canonical_read, protocol]
import ../../src/chain/provider
import ../../src/quic/transport

type
  Server = object ## Stable callback storage owns fixed routes; canonical work stays in the host loop.
    transport: Transport
    routes: array[4, ReadRoute]
    pending: array[4, NativeStream]
    kind: ReadKind
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
  ## Fixed multiplexer consumes exactly one selector before binding the shared route.
  let owner = cast[ptr Server](user)
  if event == 0:
    if owner.transport.locallyOpened(stream):
      streamAbort(stream)
      return # Only remote-initiated requests can become responder jobs.
    for index in 0..<owner.routes.len:
      if owner.routes[index].handle == NativeStream(nil) and owner.pending[index] == NativeStream(nil):
        owner.pending[index] = stream
        wantRead(stream, 1)
        return # Native close, not parser failure, releases this physical routing slot.
    streamAbort(stream)
    return
  for index in 0..<owner.routes.len:
    if owner.pending[index] == stream:
      if event == 1:
        var selector = 0'u8
        let count = streamRead(stream, addr selector, 1)
        if count == -2: return
        if count != 1 or selector != byte(owner.kind):
          streamAbort(stream)
          return # Invalid selector grants no canonical work or route allocation.
        assert owner.routes[index].bindReadStream(stream, owner.kind, kindConsumed = true) == ReadError.None
        owner.pending[index] = NativeStream(nil)
      elif event == 3:
        owner.pending[index] = NativeStream(nil) # Unbound native retirement also releases its fixed slot.
      elif event == 4:
        wantRead(stream, 0)
        wantWrite(stream, 0) # Reset before selection cannot authorize a later read.
      return
    if owner.routes[index].handle == stream:
      owner.routes[index].event(stream, event)
      return # One event belongs to one exact still-live native handle.

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
    assert count <= int64(buffer.len) and owner.input.len+int(count) <= MaxReadReplyBytes
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

proc rawKey(path: string): array[32, byte] {.raises.} =
  ## Raw fixture identities do not depend on production certificate extraction.
  let bytes = readFile(path)
  assert bytes.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(bytes[index])

proc exchangeRead*(view: ChainView, kind: ReadKind, payload, expected: seq[byte],
    refused = false, holdFin = false) {.raises.} =
  ## Independent request framing and both FIN observations verify complete runtime transcripts.
  var server = default(Server)
  var client = default(Client)
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport)
  server.kind = kind
  assert openTransport(server.transport, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, serverVerify, serverEvent, multi = true)
  client.expected = rawKey(getEnv("RAGNAROK_TEST_PEER_A"))
  client.output = @[byte(kind)]
  for index in 0..<4: client.output.add(byte((uint32(payload.len) shr (8*index)) and 255))
  for octet in payload: client.output.add(octet)
  client.finAllowed = not holdFin
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr client, clientVerify, clientEvent)
  assert client.transport.connectTransport(server.transport.localPort)
  let started = getMonoTime()
  let deadline = started+initDuration(seconds = 3)
  var requested = false
  var jobs = 0
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0)
    assert client.transport.pollTransport(0)
    if not requested and client.transport.authenticatedConnections > 0:
      requested = true
      client.transport.openStream() # Authentication alone does not prove request completion.
    if holdFin and not client.finAllowed and client.opened and getMonoTime()-started > initDuration(
        milliseconds = 60):
      assert jobs == 0 and client.input.len == 0, "no canonical read before FIN"
      client.finAllowed = true
      if client.stream != NativeStream(nil): wantWrite(client.stream, 1)
    for index in 0..<server.routes.len:
      let incoming = server.routes[index].takeRequest()
      if incoming.error == ReadError.None:
        inc jobs
        let reply = serveCanonicalRead(view, incoming.value) # No canonical graph is borrowed by a foreign callback.
        if reply.error == ReadError.None:
          assert server.routes[index].respond(reply.value) == ReadError.None
        else:
          server.routes[index].reject()
    if refused and client.reset: break
    if not refused and client.receivedFin: break
  if refused:
    assert client.reset, "unavailable/malformed reads require actual stream reset"
  else:
    assert client.receivedFin and not client.reset and client.sentFin
    assert jobs == 1 and client.input == expected, "exact E4 sequence and complete FIN transcript"
