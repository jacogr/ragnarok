# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Link the real maintained transport bridge; no protocol peer migration is claimed by these
## tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, syncio]
include ../../../src/quic/transport

# The real transport invokes identity validation only while the stack owner remains alive.
proc rejectFixtureIdentity(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl.} = 0
# Setup/teardown should create no application streams, but preserve a valid synchronous callback.
proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl.} = discard

# This lifecycle-only test accepts its generated fixture; JAM certificate policy is tested separately.
proc acceptFixture(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl.} = 1

# Test-owned observations retain counters only; all native pointers are borrowed for one callback.
type HandshakeCounts = object
  starts, successes, failures, dropped: int
  peerStarts, peerCloses, refusals: int
  refusedPort: uint16
  peers: array[IncomingPeerSlots, bool]
  ipv6: bool
  active: array[IncomingHandshakeSlots, bool]

# Observe real native attempts and ensure teardown settles each tracked slot exactly once.
proc handshake(user: pointer, slot: cuint, event: cint, address: ptr ConstByte,
    port: uint16, der: ptr ConstByte, length: csize_t) {.cdecl, raises: [].} =
  let counts = cast[ptr HandshakeCounts](user)
  if event == AdmissionRefused:
    assert slot == cuint(IncomingHandshakeSlots) and address != nil and port != 0
    let remote = cast[ptr UncheckedArray[byte]](address)
    assert remote[15] == 1
    if counts.ipv6:
      for i in 0..<15: assert remote[i] == 0 # Refusals preserve native IPv6 loopback.
    else:
      assert remote[10] == 255 and remote[11] == 255 and remote[12] == 127
    inc counts.refusals
    counts.refusedPort = port
    return # Capacity refusal has no TLS correlation slot to retire.
  if event == HandshakeDropped:
    inc counts.dropped # Overflow carries no invented correlation or identity.
    return
  assert slot < cuint(IncomingHandshakeSlots)
  let index = int(slot)
  if event == HandshakeStarted:
    assert not counts.active[index] and address != nil and port != 0
    let remote = cast[ptr UncheckedArray[byte]](address)
    assert remote[15] == 1
    if counts.ipv6:
      for i in 0..<15: assert remote[i] == 0 # IPv6 loopback is copied directly.
    else:
      for i in 0..<10: assert remote[i] == 0 # IPv4 loopback uses the mapped address prefix.
      assert remote[10] == 255 and remote[11] == 255 and remote[12] == 127
      assert remote[13] == 0 and remote[14] == 0
    counts.active[index] = true
    inc counts.starts
  elif event == HandshakeSucceeded:
    assert counts.active[index] and der != nil and length > 0
    counts.active[index] = false
    inc counts.successes
  else:
    assert event == HandshakeFailed and counts.active[index]
    counts.active[index] = false
    inc counts.failures

# Admission supplies an extractable certificate; only a later live close retires its slot.
proc peerEvent(user: pointer, slot: cuint, event: cint, der: ptr ConstByte,
    length: csize_t) {.cdecl, raises: [].} =
  let counts = cast[ptr HandshakeCounts](user)
  assert slot < cuint(IncomingPeerSlots)
  let index = int(slot)
  if event == PeerAccepted:
    assert not counts.peers[index] and der != nil and length > 0 and length <= 8192
    var fields {.noinit.}: CertFields
    assert parseCert(cast[ptr byte](der), length, addr fields) == 1
    assert fields.edKey == 1 and fields.keyLength == 32
    counts.peers[index] = true
    inc counts.peerStarts
  else:
    assert event == PeerClosed and counts.peers[index]
    counts.peers[index] = false
    inc counts.peerCloses

# Hold client handshakes before their server response; the extra attempt exceeds observation storage only.
proc saturation(cert, key: string, ipv6: bool) =
  var counts = default(HandshakeCounts)
  counts.ipv6 = ipv6
  var server = default(Transport)
  var clients = default(array[IncomingHandshakeSlots + 1, Transport])
  defer:
    server.closeTransport() # All callbacks finish while the counter owner still lives.
    for i in 0..<clients.len: clients[i].closeTransport() # Every native engine owns one cleanup.
  assert server.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
      addr counts, acceptFixture, stream, ipv6 = ipv6)
  assert server.observePeers(peerEvent)
  assert not server.observePeers(peerEvent) # Replacement cannot steal an existing observer.
  assert server.observeHandshakes(handshake)
  assert not server.observeHandshakes(handshake) # An observer cannot replace an installed callback.
  for i in 0..<clients.len:
    assert clients[i].openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000",
        addr counts, acceptFixture, stream, ipv6 = ipv6)
    assert not clients[i].observePeers(peerEvent) # Incoming peer observers cannot attach to a dialer.
    assert not clients[i].observeHandshakes(handshake) # Outgoing engines cannot install incoming observers.
    assert clients[i].connectTransport(server.localPort)
    assert clients[i].pollTransport(0) # Emit ClientHello once; never consume the server's response.
    for turn in 0..<300:
      process(clients[i].engine) # Flush paced ClientHello fragments without consuming server responses.
      assert server.pollTransport(1) # Drain bounded UDP work before the next client starts.
      if counts.starts + counts.dropped == i + 1: break # No wall-clock ordering assumption between packets.
    assert counts.starts + counts.dropped == i + 1, "start " & $i & " observed=" & $(counts.starts +
        counts.dropped)
  assert counts.starts == IncomingHandshakeSlots and counts.dropped == 1
  assert counts.successes == 0 and counts.failures == 0
  for turn in 0..<300:
    assert clients[0].pollTransport(1) # Complete only one handshake; all other clients remain pending.
    assert server.pollTransport(1)
    if counts.successes == 1 and clients[0].authenticatedConnections == 1: break
  assert counts.successes == 1 and clients[0].authenticatedConnections == 1, "complete successes=" &
      $counts.successes
  clients[0].disconnectTransport()
  for turn in 0..<300:
    assert clients[0].pollTransport(1) # Send a graceful close before retiring the completed client's engine.
    assert server.pollTransport(1)
    if server.closedConnections == 1: break # The successful SSL must be destroyed before slot reuse.
  assert counts.peerStarts == 1 and counts.peerCloses == 1
  assert server.closedConnections == 1, "close count=" & $server.closedConnections
  clients[0].closeTransport()
  assert clients[0].openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000",
      addr counts, acceptFixture, stream, ipv6 = ipv6)
  assert clients[0].connectTransport(server.localPort)
  assert clients[0].pollTransport(0)
  for turn in 0..<300:
    process(clients[0].engine) # Flush the new attempt without reading its response.
    assert server.pollTransport(1) # A fresh SSL must occupy the released slot, not overflow.
    if counts.starts == IncomingHandshakeSlots + 1: break
  assert counts.starts == IncomingHandshakeSlots + 1 and counts.dropped == 1, "reuse starts=" &
      $counts.starts & " dropped=" & $counts.dropped
  for turn in 0..<300:
    assert clients[0].pollTransport(1) # Authenticate the recycled slot before deliberate engine destruction.
    assert server.pollTransport(1)
    if counts.peerStarts == 2: break
  assert counts.peerStarts == 2 and counts.peerCloses == 1
  server.closeTransport()
  assert counts.peerCloses == 1 # Engine teardown must not fabricate a second observed close.
  assert counts.failures == IncomingHandshakeSlots - 1 and counts.dropped == 2
  assert counts.refusals == 0 # Observation saturation never implies admission refusal.
  for active in counts.active: assert not active # Every tracked lifetime settled before storage retirement.

# Fill the real admitted-peer table and observe only the explicit excess-connection refusal.
proc admissionRefusal(cert, key: string, ipv6: bool) =
  var counts = default(HandshakeCounts)
  counts.ipv6 = ipv6
  var server = default(Transport)
  var clients = default(array[IncomingPeerSlots + 1, Transport])
  defer:
    server.closeTransport() # Teardown cannot invent closures for the refused peer.
    for i in 0..<clients.len: clients[i].closeTransport() # Retire every test engine once.
  assert server.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
      addr counts, acceptFixture, stream, multi = true, ipv6 = ipv6, profile = SaturatedService)
  assert server.observePeers(peerEvent) and server.observeHandshakes(handshake)
  for i in 0..<clients.len:
    assert clients[i].openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000",
        addr counts, acceptFixture, stream, ipv6 = ipv6)
    assert clients[i].connectTransport(server.localPort)
    for turn in 0..<500:
      for live in 0..i: discard clients[live].pollTransport(0) # Drive all retained engines, including keepalives.
      assert server.pollTransport(1)
      if counts.peerStarts + counts.refusals == i + 1: break # Observe decisions, not elapsed sleeps.
    assert counts.peerStarts + counts.refusals == i + 1
  assert counts.peerStarts == IncomingPeerSlots and counts.refusals == 1
  assert counts.refusedPort == clients[IncomingPeerSlots].localPort
  assert counts.peerCloses == 0 and server.peerMetric(0) == uint64(IncomingPeerSlots)
  assert server.peerMetric(5) == 1 and counts.successes == IncomingPeerSlots + 1
  server.closeTransport()
  assert counts.refusals == 1 and counts.peerCloses == 0 # Refused connections never occupy a peer slot.

# Exercise native construction failure and success with the exact production I/O owner and LSQUIC engine.
proc main() {.raises.} =
  let args = @[getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")]
  assert args[0].len > 0 and args[1].len > 0, "missing prepared native fixtures"
  var owner = default(Transport)
  var token: byte = 0
  assert owner.transportStatus == -1
  assert not owner.observePeers(peerEvent) # Failed registration on a default owner retains no callback.
  assert not owner.pollTransport(0)
  owner.closeTransport()
  owner.closeTransport()
  # Failed certificate setup must retire the socket/dispatcher so the same stack owner can recover.
  assert not owner.openTransport(true, false, 0, "missing-certificate.pem", "missing-key.pem",
      "jamnp-s/1/00000000", addr token, rejectFixtureIdentity, stream)
  assert owner.transportStatus == -1
  # Repeated real engines validate synchronous callbacks, C string lifetimes and resource teardown.
  for iteration in 0..<16:
    assert owner.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, rejectFixtureIdentity, stream, ipv6 = iteration mod 2 == 1)
    assert not owner.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, rejectFixtureIdentity, stream) # Refuse to replace live native resources.
    assert owner.pollTransport(0)
    owner.closeTransport()
    owner.closeTransport()
    assert owner.transportStatus == -1
  let dispatcher = newDispatcher()
  defer: dispatcher.close()
  var incoming = default(Transport)
  var outgoing = default(Transport)
  # Shared native engines borrow one dispatcher; retiring one must leave the other's socket usable.
  for iteration in 0..<4:
    assert incoming.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, rejectFixtureIdentity, stream, ipv6 = iteration mod 2 == 1,
            dispatcher = dispatcher)
    assert outgoing.openTransport(false, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, rejectFixtureIdentity, stream, ipv6 = iteration mod 2 == 1,
            dispatcher = dispatcher)
    assert pollPair(incoming, outgoing)
    incoming.closeTransport()
    assert outgoing.pollTransport(0)
    outgoing.closeTransport()
  for ipv6 in [false, true]: # Reuse the process-wide SSL observer index across complete engine retirement.
    saturation(args[0], args[1], ipv6)
    admissionRefusal(args[0], args[1], ipv6)
  echo "Nimony shared transport: 4 IPv4/IPv6 engine pairs passed"
  echo "Nimony transport: 16 IPv4/IPv6 native setup/teardown cycles passed"

# Fixture/thread setup errors cannot be reported as a successful native lifecycle check.
try:
  main()
except:
  quit(2)
