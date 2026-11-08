# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact live-peer routing rejects stale owner/slot generations across real TLS replacements.

import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/quic/transport
import ../../../src/jamnp-s/protocol

type
  Exchange = object ## One finite byte/FIN exchange retains a borrowed stream only until its close callback.
    handle: NativeStream
    value: byte
    received, readFin, written, reported: bool
  Party = object ## Stable enclosing callback storage closes all native owners before destruction.
    transport: Transport
    server, opened, invalid: bool
    foreign: nil ptr Transport
    pin: array[32, byte]
    peers: array[2, PeerHandle]
    known: array[2, bool]
    exchanges: array[8, Exchange]
    target: PeerHandle
    outgoing, last: byte
    accepted, closed, completed: int

proc `=copy`(destination: var Party, source: Party) {.error.}
  ## No copy may relocate the transport or its borrowed outer callback context.

proc `=dup`(source: Party): Party {.error.}
  ## Foreign callback retirement also forbids implicit duplication.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Both incoming same-key clients remain distinct authenticated connections.
  let owner = cast[ptr Party](user)
  if owner.server: return cint(validPeer(cast[ptr byte](der), length, []))
  cint(validPeer(cast[ptr byte](der), length, owner.pin))

proc peer(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  ## Mint a reference in the exact accepted slot; preserve its old copy when the native peer closes.
  let owner = cast[ptr Party](user)
  if slot >= 2: owner.invalid = true; return
  let index = int(slot)
  # Preserve the accepted callback bound on the converted local before bounded peer lookup.
  assert index >= 0 and index < 2, "accepted callback slot fits the two-peer fixture"
  if event == PeerAccepted:
    let found = owner.transport.peerAt(index)
    if found.error != PeerError.None or owner.known[index]: owner.invalid = true; return
    owner.peers[index] = found.value
    owner.known[index] = true
    inc owner.accepted
  elif event == PeerClosed:
    if not owner.known[index]: owner.invalid = true; return
    owner.known[index] = false
    inc owner.closed
  else: owner.invalid = true # Unknown events cannot mint or release peer observations.

proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Opaque finite exchanges prove per-connection selection independently from JAM message framing.
  let owner = cast[ptr Party](user)
  var position = -1
  if event == 0:
    let found = owner.transport.streamPeer(handle)
    if found.error != PeerError.None: owner.invalid = true; streamAbort(handle); return
    let foreign = owner.foreign
    if foreign != nil and foreign[].streamPeer(handle).error != PeerError.Unavailable:
      owner.invalid = true; streamAbort(handle); return # A live foreign stream has no peer in that engine.
    if owner.server and not (found.value == owner.target):
      owner.invalid = true; streamAbort(handle); return # Targeting must not use a sole/global connection fallback.
    for index in 0..<owner.exchanges.len:
      if owner.exchanges[index].handle == default(NativeStream):
        position = index
        break # Reserve one bounded callback record before subscribing to write work.
    if position < 0: owner.invalid = true; streamAbort(handle); return
    owner.exchanges[position] = Exchange(handle: handle, value: owner.outgoing)
    if owner.server: wantWrite(handle, 1) # The client responds only after receiving this exact byte.
    return
  for index in 0..<owner.exchanges.len:
    if owner.exchanges[index].handle == handle:
      position = index
      break # Reads/writes/close always refer to the same live exchange owner.
  if position < 0: owner.invalid = true; return
  if event == 3:
    owner.exchanges[position] = default(Exchange)
    return # Native close ends the only retained stream pointer lifetime.
  if event == 1:
    var value = 0'u8
    let amount = streamRead(handle, addr value, 1)
    if amount == 1:
      if owner.exchanges[position].received: owner.invalid = true; return
      owner.exchanges[position].received = true
      if owner.server:
        if value != owner.exchanges[position].value: owner.invalid = true; return
      else:
        owner.last = value
        owner.exchanges[position].value = value
        wantWrite(handle, 1) # Echo only the byte delivered to this client connection.
    elif amount == 0:
      owner.exchanges[position].readFin = true
      readDone(handle) # Disable repeated EOF readiness after the finite peer half-close.
    elif amount != -2: owner.invalid = true; return # Would-block is not truncation or failure.
  elif event == 2:
    if not owner.exchanges[position].written:
      var value = owner.exchanges[position].value
      let amount = streamWrite(handle, addr value, 1)
      if amount == 1:
        owner.exchanges[position].written = true
        wantWrite(handle, 0)
        streamFin(handle) # Success still waits for the peer's clean FIN below.
      elif amount < 0 and amount != -2: owner.invalid = true; return
  else:
    owner.invalid = true
    return # No reset/unknown event counts as a completed byte exchange.
  if owner.exchanges[position].received and owner.exchanges[position].readFin and
      owner.exchanges[position].written and not owner.exchanges[position].reported:
    owner.exchanges[position].reported = true
    inc owner.completed # Both one-byte directions and clean FIN must complete once.

proc key(path: string): array[32, byte] {.raises.} =
  ## Public fixture pins have exact32-byte width.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])

proc listen(server: var Party) =
  ## Same stable outer owner can reopen after all earlier foreign callbacks retire.
  server.known = default(array[2, bool])
  assert server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "peer-control/v1", addr server, verify, stream,
    multi = true, incomingPeers = 2), "listener setup"
  assert server.transport.observePeers(peer)

proc connect(client: var Party, server: var Party) {.raises.} =
  ## Explicitly store a stable foreign owner only for synchronous cross-engine extraction checks.
  client.pin = key(getEnv("RAGNAROK_TEST_PEER_A"))
  client.foreign = addr server.transport
  assert client.transport.openTransport(false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "peer-control/v1", addr client, verify, stream)
  client.opened = true
  assert client.transport.connectTransport(localPort(server.transport))

proc pump(server: var Party, clients: var array[3, Party], accepted, closed, completed: int) =
  ## Wait for actual connection/stream milestones under a finite native event-loop deadline.
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while getMonoTime() < deadline:
    assert server.transport.pollTransport(0)
    var responses = 0
    for index in 0..<clients.len:
      if clients[index].opened: assert clients[index].transport.pollTransport(0)
      assert not clients[index].invalid, "client stream owner mismatch"
      responses += clients[index].completed # This finite fixture opens only five exchanges in total.
    assert not server.invalid, "server stream/peer owner mismatch"
    if server.accepted == accepted and server.closed == closed and server.completed == completed and
        responses == completed: return
  assert false, "peer-control milestones: accepted=" & $server.accepted & " closed=" &
      $server.closed & " completed=" & $server.completed

proc send(server: var Party, target: PeerHandle, value: byte) =
  ## The target/value are selected before make_stream may call back synchronously.
  server.target = target
  server.outgoing = value
  assert server.transport.openPeerStream(target), "live targeted stream request"

proc scenario() {.raises.} =
  ## A stale reference must not target replacements in the same slot or a reopened owner.
  var server = Party(server: true)
  var clients = default(array[3, Party])
  defer:
    for index in 0..<clients.len: clients[index].transport.closeTransport()
    server.transport.closeTransport() # Every callback context remains live through native retirement.
  listen(server)
  assert server.transport.peerAt(4095).error == PeerError.Unavailable
  assert server.transport.streamPeer(default(NativeStream)).error == PeerError.Unavailable
  assert not server.transport.live(default(PeerHandle))
  assert not server.transport.cancelPeerStreamOpens(default(PeerHandle))
  connect(clients[0], server)
  pump(server, clients, 1, 0, 0)
  let original = server.peers[0]
  send(server, original, 11)
  pump(server, clients, 1, 0, 1)
  assert clients[0].last == 11
  assert not clients[0].transport.live(original) and not clients[0].transport.disconnectPeer(original)
  assert not clients[0].transport.cancelPeerStreamOpens(original)
  let clientPeer = clients[0].transport.peerAt(0)
  assert clientPeer.error == PeerError.None and not server.transport.live(clientPeer.value)
  connect(clients[1], server)
  pump(server, clients, 2, 0, 1)
  let survivor = server.peers[1]
  send(server, survivor, 22)
  pump(server, clients, 2, 0, 2)
  assert clients[1].last == 22 and clients[0].last == 11
  assert server.transport.disconnectPeer(original)
  pump(server, clients, 2, 1, 2)
  assert not server.transport.live(original) and not server.transport.openPeerStream(original)
  assert not server.transport.disconnectPeer(original) and server.transport.live(survivor)
  assert not server.transport.cancelPeerStreamOpens(original)
  assert server.transport.cancelPeerStreamOpens(survivor)
  send(server, survivor, 23)
  pump(server, clients, 2, 1, 3)
  assert clients[1].last == 23
  clients[0].transport.closeTransport()
  clients[0].opened = false
  connect(clients[2], server)
  pump(server, clients, 3, 1, 3)
  let replacement = server.peers[0]
  assert not (replacement == original), "slot reuse must advance the admission generation"
  assert not server.transport.cancelPeerStreamOpens(original)
  assert not server.transport.live(original) and not server.transport.disconnectPeer(original)
  send(server, replacement, 33)
  pump(server, clients, 3, 1, 4)
  assert clients[2].last == 33 and clients[1].last == 23
  for index in 0..<clients.len:
    clients[index].transport.closeTransport()
    clients[index].opened = false # Every old engine retires before owner-address reuse.
  server.transport.closeTransport()
  assert not server.transport.live(original), "closed owner has no live peers"
  assert server.transport.peerAt(0).error == PeerError.Unavailable, "closed owner cannot mint references"
  listen(server)
  connect(clients[0], server)
  pump(server, clients, 4, 1, 4)
  assert not (server.peers[0] == original), "owner reopening must not revive old slot0 generation1"
  assert not server.transport.live(original) and not server.transport.openPeerStream(original)
  assert not server.transport.disconnectPeer(original)
  send(server, server.peers[0], 44)
  pump(server, clients, 4, 1, 5)
  assert clients[0].last == 44

try:
  scenario()
except:
  quit 2 # Fixture IO/native startup exceptions are not passing peer-control evidence.
echo "quic peer control: exact routing, targeted close, slot generation and owner reopening passed"
