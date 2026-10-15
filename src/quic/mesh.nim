## Included by peer.nim: bounded two-peer IPv6 lifecycle policy. Owners never move while callbacks borrow them.

# Compare the full public-key byte strings lexicographically, then apply pinned JAMNP-S Required connectivity.
proc preferred(local, remote: array[32, byte]): bool {.raises: [].} =
  var less = false
  # The first unequal byte determines the ordering; the high bit is separately taken from byte 31.
  for index in 0..<32:
    if local[index] != remote[index]: less = local[index] < remote[index]; break
  (local[31] > 127) xor (remote[31] > 127) xor less

# Test ordering, both final-byte high bits and direction symmetry without any cryptographic secret material.
proc meshSelfTest() =
  # Exercise all high-bit combinations with both possible lexicographic orders.
  for highA in [0'u8, 128'u8]:
    # Vary the remote high bit independently of the local high bit.
    for highB in [0'u8, 128'u8]:
      # Exercise both first-byte ordering outcomes for this parity combination.
      for firstA in [0'u8, 2'u8]:
        var a, b: array[32, byte]
        a[0] = firstA; b[0] = 1
        a[31] = highA; b[31] = highB
        doAssert preferred(a, b) == ((highA != highB) xor (firstA < 1))
        doAssert preferred(a, b) != preferred(b, a)
  var a, b: array[32, byte]
  b[31] = 127
  doAssert preferred(a, b) # Ordering reaches the final byte without treating 127 as high.
  b[31] = 128
  doAssert not preferred(a, b) # Exactly 128 changes the parity.
  echo "MESH_POLICY_OK"

# Count live stream owners; a settled reply alone does not prove all native close callbacks have retired.
proc liveMesh(peer: ptr Peer): int {.raises: [].} =
  # A slot owns its buffers until its handle becomes nil in the final close callback.
  for state in peer.streams:
    if state.handle != NativeStream(nil): inc result

# Prove eight pending owners contain four fully sent queries and four complete request prefixes without FIN.
proc pendingMesh(peer: ptr Peer): bool {.raises: [].} =
  var local, remote = 0
  # Ignore retired slots; every retained slot must still be unsettled and waiting for the missing peer/FIN.
  for state in peer.streams:
    if state.handle == NativeStream(nil): continue # Final close has already released this owner.
    if state.counted or state.readFin: return false # A completed message cannot stand in for pending work.
    if state.responder:
      if state.receivedLength != 37: return false # Require the complete CE query prefix to have arrived.
      inc remote
    else:
      if state.sendOffset != 37 or state.writeFin: return false # All request bytes must be sent without FIN.
      inc local
  local == 4 and remote == 4

# Drive both role engines from their one selector, surfacing framing or socket failures as bounded outcomes.
proc meshPoll(incoming, outgoing: var Peer): bool =
  pollPair(incoming.transport, outgoing.transport) and not incoming.failed and not outgoing.failed

# Retain two IPv6 engines through sixteen externally gated reconnects and simultaneous CE queries.
proc runMesh(): bool =
  # Validate all trusted controls before opening sockets or narrowing ports.
  if paramCount() != 9: return false
  let localPort = parseInt(paramStr(2))
  let remotePort = parseInt(paramStr(3))
  let rounds = parseInt(getEnv("RAGNAROK_MESH_ROUNDS", "16"))
  if localPort notin 1..65535 or remotePort notin 1..65535 or rounds notin 1..64: return false
  let localKey = readFile(paramStr(6))
  let remoteKey = readFile(paramStr(7))
  if localKey.len != 32 or remoteKey.len != 32 or localKey == remoteKey: return false # No self/ambiguous peer.
  var a, b: array[32, byte]
  var expected = newSeq[byte](32)
  # Retain owned identity bytes across both engines' TLS callbacks, with no certificate pointer escaping.
  for index in 0..<32:
    a[index] = byte(localKey[index]); b[index] = byte(remoteKey[index]); expected[index] = b[index]
  let initiator = preferred(a, b)
  let disrupted = getEnv("RAGNAROK_MESH_DISRUPT") == "1"
  let profile = if disrupted: CrashRecovery else: RetainedPeer
  let gate = paramStr(9)
  let dispatcher = newSelector[int]()
  defer: dispatcher.close() # Both borrowed endpoint registrations retire first, in reverse defer order.
  var incoming = Peer(server: true, mesh: true, expected: expected, attack: "valid")
  var outgoing = Peer(mesh: true, expected: expected, attack: "valid")
  defer:
    incoming.stopping = true; outgoing.stopping = true
    closeTransport(outgoing.transport)
    closeTransport(incoming.transport) # TLS globals outlive the first engine destruction.
  # The listener is persistent; outgoing binds once to an ephemeral IPv6 port and keeps it across reconnects.
  if not openTransport(incoming.transport, true, false, uint16(localPort), paramStr(4), paramStr(5),
      paramStr(8), addr incoming, verifyPeer, onStream, ipv6 = true,
          dispatcher = dispatcher, profile = profile): return false
  if not openTransport(outgoing.transport, false, false, 0, paramStr(4), paramStr(5),
      paramStr(8), addr outgoing, verifyPeer, onStream, ipv6 = true,
          dispatcher = dispatcher, profile = profile): return false
  echo "MESH_READY ", int(initiator)
  var authenticatedIn, authenticatedOut = 0'u64
  # All rounds retain these exact stack/socket/selector/TLS/engine owners.
  for round in 0..<rounds:
    var started = getMonoTime()
    # External barriers permit both simultaneous dials and post-retirement resource observations.
    while not fileExists(gate / ("start-" & $round)):
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
    # A final healthy generation proves recovery after the last forced loss without introducing another crash.
    let lossRound = disrupted and not fileExists(gate / "healthy-final")
    let fallback = round == 0 and getEnv("RAGNAROK_MESH_FALLBACK") == "1"
    started = getMonoTime()
    # A suppressed preferred dial lets the other peer initiate after the spec's example five-second timeout.
    if fallback:
      while (getMonoTime() - started).inMilliseconds < 5000:
        if not meshPoll(incoming, outgoing): return false # Keep the listener responsive while waiting.
      if not initiator and not connectTransport(outgoing.transport, uint16(
          remotePort)): return false
    else:
      if not connectTransport(outgoing.transport, uint16(
          remotePort)): return false # Deliberately race both dials.
    let useOutgoing = if fallback: not initiator else: initiator
    let kept = if useOutgoing: addr outgoing else: addr incoming
    let discarded = if useOutgoing: addr incoming else: addr outgoing
    # Expected handshake generations advance independently of callbacks, which may arrive after the losing close.
    if fallback:
      if useOutgoing: inc authenticatedOut
      else: inc authenticatedIn # Only the fallback direction is attempted.
    else:
      inc authenticatedIn; inc authenticatedOut # Both authenticated directions are required for the duplicate proof.
    started = getMonoTime()
    # Duplicate arbitration runs only after both directions authenticate; fallback has only one live direction.
    while transportStatus(kept.transport) != 1 or peerMetric(incoming.transport, 4) <
        authenticatedIn or peerMetric(outgoing.transport, 4) < authenticatedOut:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    if not fallback:
      echo "MESH_DUPLICATE ", round
      disconnectTransport(discarded.transport) # Local policy: keep the preferred-initiator direction.
    started = getMonoTime()
    # Never open application work on an engine whose duplicate close still owns a connection.
    while peerMetric(discarded.transport, 0) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    if peerMetric(kept.transport, 0) != 1: return false # The selected connection must survive duplicate retirement.
    echo "MESH_CONNECTED ", round, " ", int(useOutgoing)
    # Four local queries share this connection with the remote peer's four queries.
    for query in 0..<4: openStream(kept.transport)
    started = getMonoTime()
    while kept.healthy != 8 or liveMesh(kept) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    echo "MESH_EXCHANGED ", round, " ", kept.healthy
    # Opt-in crash rounds retain real incomplete request owners before the harness kills the other process.
    if lossRound:
      started = getMonoTime()
      # Both peers must finish and retire healthy work before either introduces incomplete streams into that phase.
      while not fileExists(gate / ("pending-" & $round)):
        if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds >
            15: return false
      kept.recovering = true
      kept.attack = "no-fin"
      for request in 0..<4: openStream(kept.transport) # Four outgoing requests accompany the peer's four pending queries.
      started = getMonoTime()
      while not pendingMesh(kept):
        if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds >
            10: return false
      echo "MESH_PENDING ", round, " 8"
    started = getMonoTime()
    # Hold a live connection for resource/thread sampling until the harness permits orderly close.
    while not fileExists(gate / ("close-" & $round)):
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
    # Crash rounds await negotiated idle expiry; graceful rounds still explicitly queue connection close.
    if not lossRound: disconnectTransport(kept.transport)
    started = getMonoTime()
    # Connection and stream owners must all retire before the next gate releases a reconnect.
    while peerMetric(incoming.transport, 0) != 0 or peerMetric(outgoing.transport, 0) != 0 or
        liveMesh(addr incoming) != 0 or liveMesh(addr outgoing) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    # Every pending request must settle exactly once when the vanished connection retires.
    if lossRound:
      if kept.rejected != 8: return false # Retained buffers cannot disappear without terminal outcomes.
      echo "MESH_RECOVERED ", round, " ", kept.rejected
    kept.healthy = 0; kept.completed = 0; kept.rejected = 0
    kept.recovering = false; kept.attack = "valid" # A malformed request in the next healthy phase remains a real failure.
    echo "MESH_IDLE ", round, " ", getOccupiedMem(), " ", peerMetric(incoming.transport, 1), " ",
        peerMetric(outgoing.transport, 1), " ", peerMetric(incoming.transport, 2), " ", peerMetric(
            outgoing.transport, 2)
  let started = getMonoTime()
  # Retain the final idle owner scope for the last sample before normal ARC/native teardown.
  while not fileExists(gate / "stop"):
    if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
  true
