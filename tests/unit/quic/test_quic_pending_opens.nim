# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real pinned LSQUIC stream credit distinguishes queued opens from live streams during cancellation.

import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/quic/transport
import ../../../src/jamnp-s/protocol

type
  Party = object ## Stable native callbacks retain held streams without FIN until explicit cancellation/close.
    transport: Transport
    client: bool
    expected: array[32, byte]
    handles: array[16, NativeStream]
    opened: int

proc `=copy`(destination: var Party, source: Party) {.error.}
  ## Native engines borrow the original party's address.

proc `=dup`(source: Party): Party {.error.}
  ## ARC initialization cannot duplicate the enclosing transport owner.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## The client independently pins the server's raw public fixture key.
  let party = cast[ptr Party](user)
  if party.client: cint(validPeer(cast[ptr byte](der), length, party.expected))
  else: cint(validPeer(cast[ptr byte](der), length, []))

proc event(user: pointer, stream: NativeStream, kind: cint) {.cdecl, raises: [].} =
  ## A one-byte flushed prefix exposes the stream remotely while deliberately retaining both directions.
  let party = cast[ptr Party](user)
  var index = -1
  if kind == 0:
    for candidate in 0..<party.handles.len:
      if party.handles[candidate] == NativeStream(nil):
        index = candidate
        break # Allocate only fixed callback storage, never one thread or growing container per stream.
    assert index >= 0
    party.handles[index] = stream
    inc party.opened
    wantRead(stream, 1)
    if party.client: wantWrite(stream, 1)
    return
  for candidate in 0..<party.handles.len:
    if party.handles[candidate] == stream:
      index = candidate
      break # Late events can only retire their original still-live borrowed handle.
  if index < 0: return
  case kind
  of 1:
    var octet = 0'u8
    let amount = streamRead(stream, addr octet, 1)
    if amount == -2: return
    if amount == 1:
      assert not party.client and octet == 7
      wantRead(stream, 0) # Withhold read completion/FIN to keep the peer's initial stream credit occupied.
    else: streamAbort(stream) # Our later explicit cancellation may make a reset readable before its reset callback.
  of 2:
    var octet = 7'u8
    let amount = streamWrite(stream, addr octet, 1)
    if amount == -2: return
    assert party.client and amount == 1
    wantWrite(stream, 0)
    discard streamFlush(stream)
  of 3: party.handles[index] = NativeStream(nil)
  of 4:
    wantRead(stream, 0)
    wantWrite(stream, 0)
    streamAbort(stream) # Both application directions retire before the fixed slot can be reused.
  else: discard # Other callbacks do not mint or complete an open request.

proc pump(server, client: var Party, milliseconds: int) =
  ## One serial event loop keeps all raw callback owners and shared native libraries stable.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0) and client.transport.pollTransport(0)

proc main() {.raises.} =
  ## Cancelling delayed opens must not close eight live streams or later create phantom requests as credit returns.
  var server = default(Party)
  var client = Party(client: true)
  defer:
    closeTransport(client.transport)
    closeTransport(server.transport)
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  for index in 0..<32: client.expected[index] = byte(raw[index])
  assert openTransport(server.transport, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "pending-opens/v1", addr server, verify, event,
    multi = true, idleSeconds = 30, keepalive = true)
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "pending-opens/v1", addr client, verify, event,
    idleSeconds = 30, keepalive = true)
  assert not server.transport.cancelPeerStreamOpens(default(PeerHandle))
  assert client.transport.connectTransport(server.transport.localPort)
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while client.transport.authenticatedConnections == 0 and getMonoTime() < deadline:
    pump(server, client, 1)
  let peer = client.transport.peerAt(0)
  assert peer.error == PeerError.None
  assert not server.transport.cancelPeerStreamOpens(peer.value), "a foreign generation cannot cancel another engine's opens"
  for index in 0..<12: assert client.transport.openPeerStream(peer.value)
  pump(server, client, 80)
  assert client.opened == 8 and server.opened == 8, "eight held streams exhaust the pinned multi-peer credit; four opens are delayed"
  assert client.transport.cancelPeerStreamOpens(peer.value)
  pump(server, client, 30)
  assert client.opened == 8 and server.opened == 8, "pending cancellation preserves every existing stream"
  for index in 0..<client.handles.len:
    if client.handles[index] != NativeStream(nil): streamAbort(client.handles[index])
  pump(server, client, 100)
  assert client.opened == 8 and server.opened == 8, "returned credit cannot fulfill cancelled delayed opens"
  assert client.transport.openPeerStream(peer.value)
  pump(server, client, 80)
  assert client.opened == 9 and server.opened == 9, "a fresh request still opens on the same authenticated connection"
  client.transport.closeTransport()
  assert not client.transport.cancelPeerStreamOpens(peer.value), "closed owners reject retained peer generations"
  echo "quic pending opens: public cancellation preserves live streams"
try:
  main()
except:
  quit 2 # Native setup failures cannot substitute for delayed-open cancellation evidence.
