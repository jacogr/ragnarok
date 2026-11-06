# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual paired node owners exercise preferred replacement, mapped routes and epoch retirement.
import std/[assertions, envvars, monotimes, times]
import ./jamnp_topology_fixture
import ../../src/jamnp-s/[connections, identity, admission]
import ../../src/quic/[transport, address, io]
import ../../src/chain/[genesis, provider]
import ../../src/codec/state/safrole

type
  Exchange = object ## Only native close ends this borrowed stream pointer's lifetime.
    stream: NativeStream
    peer: NodePeer
    local, got, fin, sent, done: bool
    value: byte
  Fixture = object ## The enclosing NodeConnections callback context stays stable through explicit retirement.
    node: NodeConnections
    peer, completedPeer: NodePeer
    known, invalid, retry, stopOnReady, holdOpened: bool
    retryAt: MonoTime
    ready, closed, retired, completed, streamCloses: int
    exchanges: array[8, Exchange]
proc `=copy`(destination: var Fixture, source: Fixture) {.error.}
  ## Native callbacks cannot follow copied enclosing test storage.
proc `=dup`(source: Fixture): Fixture {.error.}
  ## Duplicated ownership cannot retire another fixture's live native contexts.
proc peerEvent(user: pointer, peer: NodePeer, event: NodePeerEvent) {.raises: [].} =
  ## Ready callbacks safely queue work; Closed/Retired cancels every outstanding local open for that generation.
  let fixture = cast[ptr Fixture](user)
  if event == NodePeerEvent.Ready:
    fixture.peer = peer
    fixture.known = true
    inc fixture.ready
    if fixture.stopOnReady:
      fixture.node.stop() # Callback-safe intent must not recursively destroy any engine.
    elif peer.initiated and not fixture.node.queueStream(peer): fixture.invalid = true
  else:
    if event == NodePeerEvent.Closed: inc fixture.closed
    else: inc fixture.retired # Explicit engine retirement is separate from remote-close evidence.
    if fixture.peer == peer:
      fixture.known = false
      fixture.retry = false
proc streamEvent(user: pointer, peer: NodePeer, stream: NativeStream, event: cint) {.raises: [].} =
  ## A finite opaque byte/FIN echo validates raw routing without claiming a JAM message backend.
  let fixture = cast[ptr Fixture](user)
  var position = -1
  if event == 0:
    for index in 0..<fixture.exchanges.len:
      if fixture.exchanges[index].stream == default(NativeStream): position = index; break
    if position < 0: fixture.invalid = true; streamAbort(stream); return
    let local = (uint64(streamId(stream)) and 1) == (if peer.initiated: 0'u64 else: 1'u64)
    fixture.exchanges[position] = Exchange(stream: stream, peer: peer, local: local, value: 88)
    if local and not fixture.holdOpened: wantWrite(stream,
        1) # Connection initiation and individual stream initiation are distinct facts.
    return
  for index in 0..<fixture.exchanges.len:
    if fixture.exchanges[index].stream == stream: position = index; break
  if position < 0: fixture.invalid = true; return
  if event == 3:
    fixture.exchanges[position] = default(Exchange)
    inc fixture.streamCloses
    return # Clear before any later callback can reuse this local exchange slot.
  if event == 4:
    if fixture.exchanges[position].local and fixture.node.active(peer):
      fixture.retry = true
      fixture.retryAt = getMonoTime()+initDuration(
          milliseconds = 50) # Pending replacement may legitimately reject an early CE stream.
    streamAbort(stream)
    return # A reset is failure/cancellation, never a completed finite exchange.
  if event == 1:
    var value = 0'u8
    let amount = streamRead(stream, addr value, 1)
    if amount == 1:
      if fixture.exchanges[position].got or value != 88: fixture.invalid = true; return
      fixture.exchanges[position].got = true
      if not fixture.exchanges[position].local: wantWrite(stream, 1)
    elif amount == 0:
      fixture.exchanges[position].fin = true
      readDone(stream)
    elif amount != -2: fixture.invalid = true; return
  elif event == 2:
    if not fixture.exchanges[position].sent:
      var value = 88'u8
      let amount = streamWrite(stream, addr value, 1)
      if amount == 1:
        fixture.exchanges[position].sent = true
        wantWrite(stream, 0)
        streamFin(stream)
      elif amount < 0 and amount != -2: fixture.invalid = true; return
  else: fixture.invalid = true; return
  if fixture.exchanges[position].got and fixture.exchanges[position].fin and
      fixture.exchanges[position].sent and not fixture.exchanges[position].done:
    fixture.exchanges[position].done = true
    fixture.completedPeer = peer
    inc fixture.completed
proc connectionRoster*(left, right: StateEdKey, leftPort, rightPort: uint16,
    address: NetworkAddress, removeRight = false): array[3, seq[StateValidator]] =
  ## Every alias has exact metadata; absent remote membership becomes the pinned null validator.
  result = [newSeq[StateValidator](6), newSeq[StateValidator](9), newSeq[StateValidator](12)]
  for epoch in 0..<3:
    for index in 0..<result[epoch].len:
      if removeRight and index mod 2 == 1:
        result[epoch][index] = nullValidator()
      else:
        let key = if index mod 2 == 0: left else: right
        let port = if index mod 2 == 0: leftPort else: rightPort
        var metadata = default(array[128, byte])
        let raw = address.bytes
        for octet in 0..<16: metadata[octet] = raw[octet]
        metadata[16] = byte(port and 255)
        metadata[17] = byte(port shr 8)
        result[epoch][index] = StateValidator(ed25519: key, metadata: StateValidatorMetadata(metadata))
proc step(fixture: var Fixture, clock: MonoTime) =
  ## Retry an explicitly rejected finite request with bounded backoff, retaining no success claim.
  assert fixture.node.poll(clock, 0), "paired node event loop"
  assert not fixture.invalid, "paired node callback ownership"
  if fixture.retry and getMonoTime() >= fixture.retryAt and fixture.known and fixture.node.active(fixture.peer):
    fixture.retry = false
    assert fixture.node.queueStream(fixture.peer), "bounded retry queue"
proc held(fixture: Fixture): bool =
  ## A live current-generation local stream deliberately retains its borrowed pointer until shutdown.
  for exchange in fixture.exchanges:
    if exchange.stream != default(NativeStream) and exchange.local and exchange.peer ==
        fixture.peer: return true
  false
proc connectionPair*(ipv6: bool, stopReady = false, holdOpened = false, idle = false) =
  ## Both sides become fallback-eligible at once, deterministically exercising concurrent cross-dials.
  let leftIdentity = certificateIdentity(getEnv("RAGNAROK_TEST_CERT"))
  let rightIdentity = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B"))
  assert leftIdentity.error == CertificateIdentityError.None and rightIdentity.error ==
      CertificateIdentityError.None
  let left = leftIdentity.value
  let right = rightIdentity.value
  var address = default(NetworkAddress)
  assert parseNetworkAddress((if ipv6: "::1" else: "127.0.0.1"), address)
  let seed = topologyCaptured(connectionRoster(left, right, 0, 0, address))
  assert seed.error == GenesisError.None
  var first, second = default(Fixture)
  first.stopOnReady = stopReady
  second.stopOnReady = stopReady
  first.holdOpened = holdOpened
  second.holdOpened = holdOpened
  defer:
    first.node.close()
    second.node.close() # Both user contexts outlive all final stream/peer retirement notifications.
  let firstConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    "jamnp-s/1/00000000", binding = address, others = 0, streams = 32)
  let secondConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv(
      "RAGNAROK_TEST_KEY_B"),
    "jamnp-s/1/00000000", binding = address, others = 0, streams = 32)
  assert first.node.open(firstConfig, seed, topologyLimits(), streamEvent, peerEvent, addr first) ==
      ConnectionError.None
  assert second.node.open(secondConfig, seed, topologyLimits(), streamEvent, peerEvent,
      addr second) == ConnectionError.None
  let advertised = topologyCaptured(connectionRoster(left, right, first.node.localPort,
    second.node.localPort,
    address), atSlot = 8, parent = seed)
  let view = advanceView(genesisView(seed), advertised)
  assert view.error == ViewAdvanceError.None
  assert first.node.advance(view.value, StateTime(8)).value == EpochUpdate.Applied
  assert second.node.advance(view.value, StateTime(8)).value == EpochUpdate.Applied
  if stopReady:
    let deadline = getMonoTime()+initDuration(seconds = 5)
    while getMonoTime() < deadline and (not first.node.stopped or not second.node.stopped):
      let clock = getMonoTime()+initDuration(seconds = 6)
      if not first.node.stopped:
        let progressed = first.node.poll(clock, 0)
        assert progressed or first.node.stopped, "stop callback leaves the event loop coherently"
      if not second.node.stopped:
        let progressed = second.node.poll(clock, 0)
        assert progressed or second.node.stopped, "peer stop callback leaves the event loop coherently"
    assert first.node.stopped and second.node.stopped, "both authenticated Ready hooks request stop"
    assert first.ready == 1 and second.ready == 1, "no later Ready notification follows stop intent"
    assert not first.node.queueStream(first.peer) and not second.node.queueStream(second.peer)
    first.node.close()
    second.node.close()
    assert first.retired == 1 and second.retired == 1, "final engine retirement has distinct lifecycle evidence"
    assert first.node.peerCount == 0 and second.node.peerCount == 0
    return # Explicit close completed while both enclosing callback contexts were still alive.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  var converged = false
  while getMonoTime() < deadline:
    let clock = getMonoTime()+initDuration(seconds = 6)
    step(first, clock)
    step(second, clock)
    let live = first.known and second.known and first.node.active(first.peer) and
        second.node.active(second.peer)
    let preferred = first.peer.initiated == preferredInitiator(left, right) and
        second.peer.initiated == preferredInitiator(right, left)
    let exchanged = if holdOpened: held(first) or held(second) else:
      first.completed > 0 and second.completed > 0 and first.completedPeer == first.peer and
          second.completedPeer == second.peer
    if live and preferred and exchanged:
      converged = true
      break # The surviving preferred connection completed both byte/FIN directions after arbitration.
  assert converged, "paired preferred connections failed to converge"
  assert first.node.peerCount == 1 and second.node.peerCount == 1, "one logical reservation per authenticated identity"
  if holdOpened:
    let closes = first.streamCloses+second.streamCloses
    first.node.close()
    second.node.close()
    assert first.streamCloses+second.streamCloses > closes, "shutdown must deliver close for the blocked live stream"
    assert not held(first) and not held(second), "no borrowed stream survives engine retirement"
    assert first.retired == 1 and second.retired == 1, "live peers retire after their engines"
    return # Both user callback contexts remain alive through all final closes.
  if idle:
    let originalFirst = first.peer
    let originalSecond = second.peer
    first.retry = false
    second.retry = false
    let idleDeadline = getMonoTime()+initDuration(seconds = 7)
    while getMonoTime() < idleDeadline:
      let clock = getMonoTime()+initDuration(seconds = 6)
      step(first, clock)
      step(second, clock)
      assert first.peer == originalFirst and second.peer == originalSecond
      assert first.node.active(originalFirst) and second.node.active(originalSecond), "idle node pair must not inherit the two-second crash experiment"
  let oldFirst = first.peer
  let oldSecond = second.peer
  assert first.node.announcements(oldFirst) and second.node.announcements(oldSecond)
  let next = topologyCaptured(connectionRoster(left, right, first.node.localPort,
    second.node.localPort,
    address, removeRight = true), atSlot = 12, parent = advertised)
  let later = advanceView(view.value, next)
  assert later.error == ViewAdvanceError.None
  assert first.node.advance(later.value, StateTime(1000)).value == EpochUpdate.Held
  assert first.node.active(oldFirst), "best-head progress cannot drop validator connectivity"
  let finalized = finalizeView(later.value, next.value.blockHash)
  assert finalized.error == ViewFinalizeError.None
  assert first.node.advance(finalized.value, StateTime(12)).value == EpochUpdate.Held
  assert first.node.advance(finalized.value, StateTime(13)).value == EpochUpdate.Applied
  assert second.node.advance(finalized.value, StateTime(13)).value == EpochUpdate.Applied
  assert not first.node.active(oldFirst) and not first.node.queueStream(oldFirst)
  let closing = getMonoTime()+initDuration(seconds = 3)
  while getMonoTime() < closing and (first.known or second.known):
    let clock = getMonoTime()+initDuration(seconds = 6)
    step(first, clock)
    step(second, clock)
  assert not first.known and not second.known, "role-expired physical peers must actually retire"
  assert first.node.peerCount == 0 and second.node.peerCount == 0
  assert not first.node.disconnect(oldFirst) and not second.node.queueStream(oldSecond), "stale NodePeer cannot control a replacement"
proc headUpdateFairness*() =
  ## Repeated head updates and early route refusals cannot starve a later useful target.
  let selected = certificateIdentity(getEnv("RAGNAROK_TEST_CERT"))
  let other = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B"))
  assert selected.error == CertificateIdentityError.None and other.error ==
      CertificateIdentityError.None
  var v4, v6 = default(NetworkAddress)
  assert parseNetworkAddress("127.0.0.1", v4) and parseNetworkAddress("::1", v6)
  var sink = default(UdpEndpoint)
  defer: sink.close()
  assert sink.open(false, 0)
  var third, fourth = default(array[32, byte])
  third[0] = 21
  fourth[0] = 22
  let keys = [selected.value, other.value, StateEdKey(third), StateEdKey(fourth)]
  var source = [newSeq[StateValidator](6), newSeq[StateValidator](9), newSeq[StateValidator](12)]
  for epoch in 0..<3:
    for index in 0..<source[epoch].len:
      let ordinal = index mod 6
      let key = keys[min(ordinal, 3)]
      var metadata = default(array[128, byte])
      if ordinal == 1 or ordinal == 2:
        let raw = v6.bytes
        for octet in 0..<16: metadata[octet] = raw[octet]
        metadata[16] = 55 # These early IPv6 routes cannot use the explicitly IPv4-only local binding.
      elif ordinal >= 3:
        let raw = v4.bytes
        for octet in 0..<16: metadata[octet] = raw[octet]
        metadata[16] = byte(sink.port and 255)
        metadata[17] = byte(sink.port shr 8) # A real IPv4-mapped later route has an observable UDP destination.
      source[epoch][index] = StateValidator(ed25519: key, metadata: StateValidatorMetadata(metadata))
  let seed = topologyCaptured(source)
  assert seed.error == GenesisError.None
  var node = default(NodeConnections)
  defer: node.close()
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    "jamnp-s/1/00000000", binding = v4, streams = 32)
  assert node.open(config, seed, topologyLimits()) == ConnectionError.None
  var view = genesisView(seed)
  var parent = seed
  let clock = getMonoTime()+initDuration(seconds = 6)
  for iteration in 0..<4:
    let child = topologyCaptured(source, atSlot = uint32(8+iteration), parent = parent)
    let next = advanceView(view, child)
    assert next.error == ViewAdvanceError.None
    view = next.value
    parent = child
    assert node.advance(view, StateTime(uint32(8+iteration))).value == EpochUpdate.Applied
    assert node.poll(clock+initDuration(milliseconds = iteration*300), 0), "head-update fairness turn"
  var buffer = default(array[2048, byte])
  var remote = default(NetworkEndpoint)
  var received = false
  let deadline = getMonoTime()+initDuration(milliseconds = 100)
  while getMonoTime() < deadline:
    if sink.receive(buffer, remote) > 0:
      received = true
      break # Do not progress the node after the head-update turns; observe only already-sent packets.
  assert received, "new heads must preserve progress past repeatedly refused early routes"
