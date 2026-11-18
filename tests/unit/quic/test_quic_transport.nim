# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Link the real maintained transport bridge; no protocol peer migration is claimed by these
## tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, syncio, monotimes, times]
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
  assert counts.failures == IncomingHandshakeSlots - 1, "tracked attempts settle on teardown"
  assert counts.dropped == 1, "one overflow attempt is observed once, including teardown"
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

# Exercise native construction failure and success with the exact production I/O owner and QUICHE engine.
type IdleStream = object ## One open bidirectional stream confirms the handshake before transport-only idle observation.
  handle: NativeStream
  sent, got, failed: bool

proc idleStream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Exchange exactly one byte each way, then leave the stream open without application traffic.
  let flow = cast[ptr IdleStream](user)
  case event
  of 0:
    flow.handle = handle
    wantRead(handle, 1)
    wantWrite(handle, 1)
  of 1:
    var octet = 0'u8
    let count = streamRead(handle, addr octet, 1)
    if count == -2: return
    if count == 1 and octet == 42:
      flow.got = true
      wantRead(handle, 0)
    else:
      flow.failed = true # Idle shutdown may end a silent control; healthy keepalive must not.
      wantRead(handle, 0)
  of 2:
    if flow.sent:
      wantWrite(handle, 0)
      return # A queued/spurious writable callback must never refresh idle with another app byte.
    var octet = 42'u8
    let count = streamWrite(handle, addr octet, 1)
    if count == -2: return
    if count != 1: flow.failed = true
    else: flow.sent = true
    wantWrite(handle, 0)
    discard streamFlush(handle) # No FIN or further app writes can artificially refresh idle state.
  of 3: flow.handle = NativeStream(nil)
  of 4:
    flow.failed = true
    wantRead(handle, 0)
    wantWrite(handle, 0)
  else: discard # No other event changes the independently observed transcript.

type SendFault = object ## A targeted UDP fault leaves every other destination on the real sender.
  flow: IdleStream
  blockedPort, refusedPort: uint16
  blocked: bool
  refusal: cint

proc faultStream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Forward the healthy sibling's traffic to the existing one-byte transcript.
  let fault = cast[ptr SendFault](user)
  idleStream(addr fault.flow, handle, event)

proc faultSend(user: pointer, bytes: ptr ConstByte, length: csize_t,
    address: ptr ConstByte, port: uint16): cint {.cdecl, raises: [].} =
  ## Backpressure once for the healthy peer; use a real forbidden UDP destination for the other.
  let owner = cast[ptr Transport](user)
  let fault = cast[ptr SendFault](owner.user)
  if port == fault.blockedPort and not fault.blocked:
    fault.blocked = true
    return EAGAIN # QUICHE must retry this datagram without retiring the connection.
  if port == fault.refusedPort:
    var broadcast = default(array[16, byte])
    for octet in 12..15: broadcast[octet] = 255 # The UDP endpoint never enables SO_BROADCAST.
    let error = sendPacket(user, bytes, length, cast[ptr ConstByte](addr broadcast[0]), port)
    fault.refusal = error
    return error
  sendPacket(user, bytes, length, address, port)

proc duplicateFd(fd: cint): cint {.importc: "dup", header: "<unistd.h>".}
  ## Retain the original test diagnostics descriptor while QUICHE emits a known error.

proc driveSendRefusal(server, healthy, refused: var Transport): bool =
  ## Ignore only the native logger's variable timestamp and peer port during the intentional failure.
  let saved = duplicateFd(2)
  assert saved >= 0
  defer: discard posix.close(saved)
  let sink = posix.open("/dev/null", O_WRONLY)
  assert sink >= 0
  defer: discard posix.close(sink)
  assert posix.dup2(sink, 2) == 2
  defer: assert posix.dup2(saved, 2) == 2
  refused.openStream()
  let deadline = getMonoTime() + initDuration(seconds = 3)
  while server.closedConnections == 0 and getMonoTime() < deadline:
    # The shared listener must never report failure while the refused stream retires.
    if not (server.pollTransport(1) and healthy.pollTransport(1) and refused.pollTransport(1)):
      return false
  server.closedConnections == 1

proc sendFailureIsolation(cert, key: string) =
  ## Exercise the real bridge and UDP sender with two retained sessions on the same listener.
  var fault = default(SendFault)
  var healthyFlow, refusedFlow = default(IdleStream)
  var server, healthy, refused = default(Transport)
  defer:
    healthy.closeTransport()
    refused.closeTransport()
    server.closeTransport()
  # The native constructor's existing callback is the injection boundary; endpoints still use real UDP.
  assert server.socket.open(false, 0)
  let dispatcher = newDispatcher()
  server.selector = dispatcher
  server.selectorOwned = true
  assert dispatcher.register(server.socket)
  server.registered = true
  server.user = addr fault
  server.verify = acceptFixture
  server.stream = faultStream
  var certText = cert
  var keyText = key
  var alpn = "jamnp-s/1/00000000"
  var options = NativeTransportOptions(profile: 2, server: 1, multi: 1)
  server.engine = transportNew(addr options, server.localPort, certText.toCString(),
    keyText.toCString(), alpn.toCString(), addr server, verifyForward, faultSend, streamForward)
  assert server.engine != nil
  assert healthy.openTransport(false, false, 0, cert, key, alpn, addr healthyFlow,
    acceptFixture, idleStream)
  assert refused.openTransport(false, false, 0, cert, key, alpn, addr refusedFlow,
    acceptFixture, idleStream)
  assert healthy.connectTransport(server.localPort) and refused.connectTransport(server.localPort)
  let handshakeDeadline = getMonoTime() + initDuration(seconds = 3)
  while server.authenticatedConnections < 2 or healthy.authenticatedConnections == 0 or
      refused.authenticatedConnections == 0:
    # Arm the targeted fault only after both TLS sessions are fully admitted.
    assert getMonoTime() < handshakeDeadline
    assert server.pollTransport(1) and healthy.pollTransport(1) and refused.pollTransport(1)
  fault.refusedPort = refused.localPort
  assert driveSendRefusal(server, healthy, refused), "UDP destination failure must leave the listener live"
  assert fault.refusal in [EACCES, ENETUNREACH] and healthy.closedConnections == 0
  fault.flow = default(IdleStream)
  fault.blockedPort = healthy.localPort
  healthy.openStream()
  let exchangeDeadline = getMonoTime() + initDuration(seconds = 3)
  while not (healthyFlow.sent and healthyFlow.got and fault.flow.sent and fault.flow.got):
    # Drive one full exchange after sibling retirement and one transient send refusal.
    assert getMonoTime() < exchangeDeadline
    assert server.pollTransport(1) and healthy.pollTransport(1)
    assert not fault.flow.failed and not healthyFlow.failed
  assert fault.blocked and server.closedConnections == 1 and healthy.closedConnections == 0

proc idlePolicy(cert, key: string, ipv6: bool, serverIdle, clientIdle: range[1..600],
    serverKeepalive, clientKeepalive: bool) =
  ## No application stream/traffic can mask idle expiry: only configured QUIC pings keep this pair alive.
  var server, client = default(Transport)
  var serverFlow, clientFlow = default(IdleStream)
  defer:
    client.closeTransport()
    server.closeTransport()
  assert server.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000", addr serverFlow,
    acceptFixture, idleStream, multi = true, ipv6 = ipv6, idleSeconds = serverIdle,
    keepalive = serverKeepalive)
  assert client.openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000", addr clientFlow,
    acceptFixture, idleStream, ipv6 = ipv6, idleSeconds = clientIdle, keepalive = clientKeepalive)
  assert client.connectTransport(server.localPort)
  let handshakeDeadline = getMonoTime()+initDuration(seconds = 3)
  while server.authenticatedConnections == 0 or client.authenticatedConnections == 0:
    assert getMonoTime() < handshakeDeadline
    assert server.pollTransport(1) and client.pollTransport(1)
  client.openStream()
  let streamDeadline = getMonoTime()+initDuration(seconds = 3)
  while not (serverFlow.sent and serverFlow.got and clientFlow.sent and clientFlow.got):
    assert getMonoTime() < streamDeadline
    assert server.pollTransport(1) and client.pollTransport(1)
    assert not serverFlow.failed and not clientFlow.failed
  # Seven seconds exceeds both two-second idle and the early client deadline,
  # and crosses the stock retransmittable-on-wire probe backoff threshold.
  let keptAlive = serverKeepalive or clientKeepalive
  let deadline = getMonoTime()+initDuration(seconds = 7)
  while getMonoTime() < deadline:
    assert server.pollTransport(1) and client.pollTransport(1)
    if keptAlive:
      assert not serverFlow.failed and not clientFlow.failed
      assert server.closedConnections == 0 and client.closedConnections == 0, "configured PING must prevent idle retirement"
    elif server.closedConnections > 0 or client.closedConnections > 0:
      return # Same idle policy without pings must actually expire, validating the positive control.
  assert keptAlive, "explicit silent timeout must expire without application traffic"

proc startupPolicy(cert, key: string, ipv6: bool, delayed: bool) =
  ## Delay the server's first response beyond stock startup idle, or prove explicit short idle still expires.
  var server, client = default(Transport)
  var token = 0
  defer:
    client.closeTransport()
    server.closeTransport()
  let idle: range[1..600] = if delayed: 30 else: 2
  assert server.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000", addr token,
    acceptFixture, stream, ipv6 = ipv6, idleSeconds = idle)
  assert client.openTransport(false, false, 0, cert, key, "jamnp-s/1/00000000", addr token,
    acceptFixture, stream, ipv6 = ipv6, idleSeconds = idle)
  assert client.connectTransport(server.localPort)
  let heldUntil = getMonoTime()+initDuration(seconds = 6)
  while getMonoTime() < heldUntil:
    # Leave the server socket unread: only a real client startup alarm can retire the attempt.
    assert client.pollTransport(1)
    if not delayed and client.closedConnections > 0:
      assert client.authenticatedConnections == 0
      return # The shorter configured startup idle must remain effective without a response.
    assert client.closedConnections == 0, "configured startup idle survives the delayed first flight"
  assert delayed, "silent short-idle startup must expire within the observation bound"
  let handshakeDeadline = getMonoTime()+initDuration(seconds = 3)
  while server.authenticatedConnections == 0 or client.authenticatedConnections == 0:
    # Releasing the held socket must complete real mutual TLS with the same client attempt.
    assert getMonoTime() < handshakeDeadline, "delayed startup completes after the server resumes"
    assert server.pollTransport(1) and client.pollTransport(1)
    assert server.closedConnections == 0 and client.closedConnections == 0

proc windowPolicy(cert, key: string) =
  ## Optional public receive windows refuse invalid domains atomically and accept the pinned minimum with real TLS resources.
  var owner = default(Transport)
  var token = 0
  defer: owner.closeTransport()
  for window in [1, 16383]:
    # Both refusal samples fit the public numeric range while remaining below its valid minimum.
    assert window >= 1 and window <= 16383, "window refusal sample stays below the valid minimum"
    # Each invalid half uses genuine otherwise-valid credentials; refusal cannot be attributed to missing test files.
    assert not owner.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
      addr token, rejectFixtureIdentity, stream, streamWindow = window)
    assert not owner.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
      addr token, rejectFixtureIdentity, stream, connectionWindow = window)
    assert owner.engine == nil and not owner.socket.isOpen
  assert not owner.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
    addr token, rejectFixtureIdentity, stream, streamWindow = 65536, connectionWindow = 32768)
  assert owner.engine == nil and not owner.socket.isOpen
  assert owner.openTransport(true, false, 0, cert, key, "jamnp-s/1/00000000",
    addr token, rejectFixtureIdentity, stream, streamWindow = 16384, connectionWindow = 16384)
  assert owner.pollTransport(0)
  owner.closeTransport()

proc main() {.raises.} =
  let args = @[getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")]
  assert args[0].len > 0 and args[1].len > 0, "missing prepared native fixtures"
  var owner = default(Transport)
  var token: byte = 0
  assert not owner.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
    addr token, acceptFixture, stream, idleSeconds = 0, keepalive = true)
  assert owner.transportStatus == -1 # Invalid timing must not acquire a socket or native owner.
  assert owner.transportStatus == -1
  assert owner.closedConnections == 0 and owner.authenticatedConnections ==
      0 # Default/retired metrics cannot dereference a missing engine.
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
  windowPolicy(args[0], args[1])
  sendFailureIsolation(args[0], args[1])
  for ipv6 in [false, true]: # Reuse the process-wide SSL observer index across complete engine retirement.
    saturation(args[0], args[1], ipv6)
    admissionRefusal(args[0], args[1], ipv6)
  for ipv6 in [false, true]:
    # Both address families honor normal delayed startup and an explicit short silent timeout.
    startupPolicy(args[0], args[1], ipv6, true)
    startupPolicy(args[0], args[1], ipv6, false)
    # Each role must maintain negotiated idle independently, including a longer local proposal.
    idlePolicy(args[0], args[1], ipv6, 2, 2, false, false)
    idlePolicy(args[0], args[1], ipv6, 2, 2, true, true)
    idlePolicy(args[0], args[1], ipv6, 2, 30, true, true)
    idlePolicy(args[0], args[1], ipv6, 30, 2, true, false)
    idlePolicy(args[0], args[1], ipv6, 2, 30, true, false)
    idlePolicy(args[0], args[1], ipv6, 30, 2, false, true)
    idlePolicy(args[0], args[1], ipv6, 2, 30, false, true)
  echo "Nimony shared transport: 4 IPv4/IPv6 engine pairs passed"
  echo "Nimony transport: 16 IPv4/IPv6 native setup/teardown cycles passed"

# Fixture/thread setup errors cannot be reported as a successful native lifecycle check.
try:
  main()
except:
  quit(2)
