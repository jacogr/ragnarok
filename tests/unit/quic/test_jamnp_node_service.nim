# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_node_service_arc_release"}

## Stable full-state node owner: explicit finality, native factory failure and retirement lifetimes.

import std/[assertions, syncio, envvars, monotimes, times]
import ../../support/[jamnp_topology_fixture, arc_evidence, jamnp_node_probe, jamnp_connection_pair]
import ../../../src/jamnp-s/[node, connections, read_stream, read_client, canonical_read, identity,
    admission, topology]
import ../../../src/chain/[genesis, provider]
import ../../../src/quic/[transport, address]
import ../../../src/codec/bounded
import ../../../src/codec/state/safrole
import ../../../src/app/proof/[worker, network_read]

proc source(): ChainView =
  ## A trusted local fixture explicitly selects finality; its best head never implies it automatically.
  let saved = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  assert saved.error == GenesisError.None
  let initialized = genesisView(saved)
  let finalized = initialized.finalizeView(saved.value.blockHash)
  assert finalized.error == ViewFinalizeError.None
  finalized.value

proc config(missing = false): ConnectionConfig =
  ## Startup input remains owned by the caller; no private-key bytes are read by the Nim identity helper.
  initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"),
    (if missing: "missing-node-key.pem" else: getEnv("RAGNAROK_TEST_KEY")),
    "jamnp-s/1/00000000", streams = 512)

proc lifetime(view: ChainView, failed: bool) =
  ## Only explicit native retirement precedes destruction of this stable callback aggregate.
  var service = default(NodeService)
  defer: service.close()
  let outcome = service.open(config(failed), view, topologyLimits())
  if failed:
    assert outcome == NodeError.BackendFailure and not service.isOpen
  else:
    assert outcome == NodeError.None and service.isOpen and service.localPort > 0
    assert service.poll(getMonoTime(), 0)
  service.close()
  assert service.peerCount == 0 and not service.isOpen

proc pump(service: var NodeService, probe: var NodeProbe, milliseconds: int) =
  ## Real bounded polling services native callbacks without acquiring a canonical alias.
  let until = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < until:
    assert service.poll(getMonoTime(), 0)
    probe.poll()

template awaitEvent(service, probe, condition, description: untyped) =
  ## Advance both real endpoints until the expected state transition or a bounded failure.
  block:
    let until = getMonoTime()+initDuration(seconds = 3)
    while not condition:
      assert getMonoTime() < until, description
      pump(service, probe, 1)

proc handshake(view: ChainView): seq[byte] =
  ## Literal E4 and empty leaf count are independent of the production announcement encoder.
  result = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](view.bestBlock.value.blockHash): result.add(octet)
  for index in 0..<4: result.add(byte((uint32(view.bestBlock.value.slot) shr (index*8)) and 255))
  result.add(0)

proc emptyBlocks(view: ChainView): seq[byte] =
  ## CE128 descending known anchor with zero maximum has exactly one empty E4 response.
  result = @[128'u8, 37, 0, 0, 0]
  for octet in array[32, byte](view.bestBlock.value.blockHash): result.add(octet)
  result.add(1)
  for index in 0..<4: result.add(0)

proc transcript(view: ChainView) {.raises.} =
  ## A real authenticated peer exercises delayed lower UP0, read saturation, worker reply and cancellation.
  var service = default(NodeService)
  var probe = default(NodeProbe)
  var cpu = default(StateProofWorker)
  defer:
    cpu.close() # No canonical owner may retire before a queued/running worker joins.
    probe.close()
    service.close()
  let hello = handshake(view)
  let request = emptyBlocks(view)
  assert service.open(config(), view, topologyLimits()) == NodeError.None
  probe.open(service.localPort)
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while not probe.authenticated and getMonoTime() < deadline: pump(service, probe, 1)
  assert probe.authenticated, "client TLS authentication"
  awaitEvent(service, probe, service.peerCount == 1, "node peer admission")
  let peer = service.peerAt(0).value
  let original = probe.issue(hello, persistent = true)
  var expectedHello: seq[byte] = @[]
  for index in 1..<hello.len: expectedHello.add(hello[index])
  awaitEvent(service, probe, service.source(peer).error == NodeError.None and
    probe.bytes(original) == expectedHello, "literal UP0 handshake reply")
  assert not probe.flows[original].receivedFin
  let delayed = probe.issue(hello, persistent = true, enabled = false)
  awaitEvent(service, probe, probe.flows[delayed].opened, "open delayed UP0")
  let newer = probe.issue(hello, persistent = true)
  awaitEvent(service, probe, service.source(peer).error == NodeError.None and
    uint64(service.source(peer).value.stream) == uint64(probe.flows[newer].number) and
    probe.flows[original].reset, "higher UP0 replaces and resets the old source")
  probe.enable(delayed)
  awaitEvent(service, probe, probe.flows[delayed].reset, "delayed lower UP0 is refused")
  assert uint64(service.source(peer).value.stream) == uint64(probe.flows[newer].number)
  let heldA = probe.issue(@[128'u8], persistent = true)
  pump(service, probe, 20)
  let heldB = probe.issue(@[128'u8], persistent = true)
  pump(service, probe, 20)
  let refused = probe.issue(request)
  awaitEvent(service, probe, probe.flows[refused].reset, "saturated read is reset")
  assert service.takeRead().error == NodeError.Unavailable, "refused read never enters the queue"
  let reserved = probe.issue(hello, persistent = true)
  awaitEvent(service, probe, service.source(peer).error == NodeError.None and
    uint64(service.source(peer).value.stream) == uint64(probe.flows[reserved].number),
    "reserved UP0 survives read saturation")
  probe.abort(heldA)
  probe.abort(heldB)
  pump(service, probe, 30)
  let reading = probe.issue(request, persistent = true)
  pump(service, probe, 30)
  assert service.takeRead().error == NodeError.Unavailable # Complete payload still grants no job before FIN.
  probe.enable(reading, finish = true)
  var task = service.takeRead()
  awaitEvent(service, probe, (block:
    if task.error != NodeError.None: task = service.takeRead()
    task.error == NodeError.None), "request FIN admits read")
  assert task.error == NodeError.None and service.readLive(task.value.ticket), "complete FIN admits one live read"
  assert cpu.start()
  var job = captureNetworkRead(view, task.value.request).value
  let admitted = cpu.submit(job)
  assert admitted.error == ProofWorkerError.None
  while cpu.phase != ProofWorkerPhase.Done: pump(service, probe, 1)
  let completed = cpu.collect(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
  assert completed.readValue.error == ReadError.None, "canonical worker read success"
  assert service.respond(task.value.ticket, completed.readValue.value) == ReadError.None
  awaitEvent(service, probe, probe.flows[reading].receivedFin, "block response reaches FIN")
  assert not probe.flows[reading].reset, "successful reply is not reset"
  assert probe.bytes(reading) == @[0'u8, 0, 0, 0]
  awaitEvent(service, probe, not service.readLive(task.value.ticket), "answered read retires")
  let cancelled = probe.issue(request)
  var stale = service.takeRead()
  awaitEvent(service, probe, (block:
    if stale.error != NodeError.None: stale = service.takeRead()
    stale.error == NodeError.None), "cancellable read is admitted")
  job = captureNetworkRead(view, stale.value.request).value
  let second = cpu.submit(job)
  assert second.error == ProofWorkerError.None
  while cpu.phase != ProofWorkerPhase.Done: pump(service, probe, 1)
  probe.abort(cancelled)
  awaitEvent(service, probe, not service.readLive(stale.value.ticket), "cancelled read retires")
  assert cpu.cancel(second.value) # Done retains the worker lease until cancellation is collected.
  assert cpu.collect(second.value).kind == ProofWorkerCompletionKind.Cancelled
  assert service.respond(stale.value.ticket, completed.readValue.value) == ReadError.InvalidStream
  let unsupported = probe.issue(@[255'u8])
  awaitEvent(service, probe, probe.flows[unsupported].reset, "unsupported selector is reset")
  assert service.peerCount == 1, "unsupported selector leaves the connection live"
  assert service.source(peer).error == NodeError.None, "usable UP0 handshake"
  let fast = probe.issue(request)
  pump(service, probe, 20)
  let firstQueued = service.takeRead()
  assert firstQueued.error == NodeError.None and firstQueued.value.request.kind == ReadKind.Blocks,
    "the first request is admitted before the second arrives"
  var missingPreimage = @[143'u8, 32, 0, 0, 0]
  for index in 0..<32: missingPreimage.add(0)
  discard probe.issue(missingPreimage)
  pump(service, probe, 20)
  assert service.respond(firstQueued.value.ticket, completed.readValue.value) == ReadError.None, "finish first queued reply"
  awaitEvent(service, probe, probe.flows[fast].receivedFin, "first queued reply reaches FIN")
  discard probe.issue(request)
  pump(service, probe, 30)
  let waiting = service.takeRead()
  assert waiting.error == NodeError.None and waiting.value.request.kind == ReadKind.Preimage,
    "a reused lower read slot cannot overtake an already waiting request"
  assert service.reject(waiting.value.ticket), "waiting read remains live until explicit rejection"
  let retried = service.takeRead()
  assert retried.error == NodeError.None and retried.value.request.kind == ReadKind.Blocks, "reused low slot remains pending after fair selection"
  assert service.reject(retried.value.ticket)
  pump(service, probe, 30)
  let withheld = probe.issue(hello, persistent = true, enabled = false)
  awaitEvent(service, probe, probe.flows[withheld].opened, "open withheld UP0")
  let malformed = probe.issue(@[0'u8, 0, 0, 16, 0], persistent = true)
  awaitEvent(service, probe, probe.flows[malformed].reset, "oversized UP0 prefix is rejected")
  assert service.source(peer).error == NodeError.Unavailable
  probe.enable(withheld)
  awaitEvent(service, probe, probe.flows[withheld].reset, "withheld lower UP0 is rejected")
  assert service.source(peer).error == NodeError.Unavailable # A failed highest ID must never revive a lower source.
  let recovered = probe.issue(hello, persistent = true)
  awaitEvent(service, probe, service.source(peer).error == NodeError.None and
    uint64(service.source(peer).value.stream) == uint64(probe.flows[recovered].number),
    "fresh UP0 recovers the source")

proc replyToOne(receiver: var NodeService, view: ChainView): int =
  ## Component host work executes outside native callbacks; Services worker exclusion has its own integration suite.
  let incoming = receiver.takeRead()
  if incoming.error != NodeError.None: return 0
  let reply = serveCanonicalRead(view, incoming.value.request)
  if reply.error == ReadError.None:
    assert receiver.respond(incoming.value.ticket, reply.value) == ReadError.None
  else:
    assert receiver.reject(incoming.value.ticket) # Missing canonical data never becomes an empty successful wire.
  1

proc outbound(sender, receiver: var NodeService, peer: NodePeer, view: ChainView,
    request: ReadRequest, expected: seq[byte], refused = false) =
  ## Delayed collection observes completed bytes after native retirement without opening another authenticated connection.
  let submitted = sender.request(peer, request)
  assert submitted.error == NodeError.None, "bounded outbound request admitted"
  let ticket = submitted.value
  assert sender.takeReply(ticket).error == ReadError.Unavailable
  var jobs = 0
  let deadline = getMonoTime()+initDuration(milliseconds = 150)
  while getMonoTime() < deadline:
    assert sender.poll(getMonoTime(), 0) and receiver.poll(getMonoTime(), 0)
    jobs += receiver.replyToOne(view)
  assert jobs == 1, "one local open intent produces exactly one remote request"
  let reply = sender.takeReply(ticket)
  if refused:
    assert reply.error == ReadError.InvalidStream and not sender.requestLive(ticket)
  else:
    assert reply.error == ReadError.None and reply.value.valid
    assert reply.value.bytes == expected
    assert reply.value.request.kind == request.kind and reply.value.request.payload ==
        request.payload
    assert not sender.requestLive(ticket), "completed ticket cannot collect a reused stream"
    assert sender.takeReply(ticket).error == ReadError.InvalidStream
  assert sender.peerCount == 1 and receiver.peerCount == 1

proc paired(ipv6: bool) =
  ## Two production owners automatically establish the preferred connection and UP0 in both directions.
  let left = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let right = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let bindingAddress = loopbackAddress(ipv6)
  let seed = topologyCaptured(connectionRoster(left, right, 0, 0, bindingAddress))
  let trusted = genesisView(seed).finalizeView(seed.value.blockHash).value
  var first, second = default(NodeService)
  defer:
    first.close()
    second.close() # Both stable aggregate addresses outlive every final native callback.
  let firstConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    "jamnp-s/1/00000000", binding = bindingAddress, others = 0, streams = 512)
  let secondConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv(
      "RAGNAROK_TEST_KEY_B"),
    "jamnp-s/1/00000000", binding = bindingAddress, others = 0, streams = 512)
  assert first.open(firstConfig, trusted, topologyLimits()) == NodeError.None
  assert second.open(secondConfig, trusted, topologyLimits()) == NodeError.None
  let advertised = topologyCaptured(connectionRoster(left, right, first.localPort, second.localPort,
    bindingAddress), atSlot = 8, parent = seed)
  let next = advanceView(trusted, advertised).value
  assert first.advance(next, StateTime(8)).error == NodeError.None
  assert second.advance(next, StateTime(8)).error == NodeError.None
  let deadline = getMonoTime()+initDuration(seconds = 3)
  var ready = false
  while getMonoTime() < deadline:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    if first.peerCount != 1 or second.peerCount != 1: continue
    let firstReady = first.peerAt(0)
    let secondReady = second.peerAt(0)
    if firstReady.error != NodeError.None or secondReady.error != NodeError.None: continue
    let a = firstReady.value
    let b = secondReady.value
    if first.source(a).error == NodeError.None and second.source(b).error == NodeError.None:
      assert a.initiated != b.initiated
      ready = true
      break # Both sides must parse a real handshake rather than merely observe authenticated TLS.
  assert ready, "paired node owners establish UP0"
  let firstPeer = first.peerAt(0).value
  let secondPeer = second.peerAt(0).value
  assert first.advance(next, StateTime(8)).error == NodeError.None
  let broadcastDeadline = getMonoTime()+initDuration(seconds = 2)
  var broadcast = false
  while getMonoTime() < broadcastDeadline:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    let claims = second.source(secondPeer)
    if claims.error == NodeError.None and claims.value.claims.sequence > 1:
      broadcast = true
      break # Independently scheduled host processing receives the subsequent complete header message.
  assert broadcast and first.source(firstPeer).error == NodeError.None, "paired header announcement"
  var blockPayload: seq[byte] = @[]
  for octet in array[32, byte](next.bestBlock.value.blockHash): blockPayload.add(octet)
  blockPayload.add(1)
  for index in 0..<4: blockPayload.add(0)
  let blocks = decodeReadRequest(ReadKind.Blocks, blockPayload).value
  assert first.request(firstPeer, default(ReadRequest)).error == NodeError.InvalidConfig
  let cancelled = first.request(firstPeer, blocks)
  assert cancelled.error == NodeError.None and first.cancelRequest(cancelled.value)
  assert first.takeReply(cancelled.value).error == ReadError.InvalidStream
  first.outbound(second, firstPeer, next, blocks, @[0'u8, 0, 0, 0])
  second.outbound(first, secondPeer, next, blocks, @[0'u8, 0, 0,
      0]) # Server-initiated CE streams share the same connection too.
  var statePayload: seq[byte] = @[]
  for octet in array[32, byte](next.bestBlock.value.blockHash): statePayload.add(octet)
  for index in 0..<62: statePayload.add(0)
  statePayload.add(0)
  statePayload.add(128)
  statePayload.add(0)
  statePayload.add(0)
  let stateRead = decodeReadRequest(ReadKind.State, statePayload).value
  let expectedState = serveCanonicalRead(next, stateRead)
  assert expectedState.error == ReadError.None
  first.outbound(second, firstPeer, next, stateRead, expectedState.value.bytes)
  let preimage = decodeReadRequest(ReadKind.Preimage, newSeq[byte](32)).value
  first.outbound(second, firstPeer, next, preimage, @[], refused = true)
  let active = first.request(firstPeer, blocks)
  assert active.error == NodeError.None
  assert first.poll(getMonoTime(), 0)
  let competing = first.request(firstPeer, blocks)
  assert competing.error == NodeError.None
  assert first.poll(getMonoTime(), 0)
  assert first.request(firstPeer, blocks).error == NodeError.LimitExceeded
  assert first.cancelRequest(competing.value)
  assert first.requestLive(active.value), "cancelling a sibling leaves the original outbound request live"
  assert first.cancelRequest(active.value)
  let drain = getMonoTime()+initDuration(milliseconds = 50)
  while getMonoTime() < drain:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    let orphan = second.takeRead()
    if orphan.error == NodeError.None: discard second.reject(orphan.value.ticket)
  first.outbound(second, firstPeer, next, blocks, @[0'u8, 0, 0, 0])
  assert first.peerAt(0).value == firstPeer and second.peerAt(0).value == secondPeer
  assert first.source(firstPeer).error == NodeError.None and second.source(secondPeer).error == NodeError.None
  let retained = first.request(firstPeer, blocks)
  assert retained.error == NodeError.None
  let finish = getMonoTime()+initDuration(milliseconds = 150)
  while getMonoTime() < finish:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    discard second.replyToOne(next)
  assert first.requestLive(retained.value), "complete uncollected reply remains owned after native retirement"
  let queuedAtClose = second.request(secondPeer, blocks)
  assert queuedAtClose.error == NodeError.None
  second.close()
  assert not second.requestLive(queuedAtClose.value)
  first.close() # Complete/uncollected and never-opened queued reservations retire before destruction.
  assert not first.requestLive(retained.value)

proc bootstrap(finalizeNew: bool) {.raises.} =
  ## A future validator appears only in the unfinalized new epoch's pending roster; it has no old-union reservation.
  let peerKey = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let previous = topologyRecords(0, 6)
  let current = topologyRecords(1, 9)
  let pending = topologyRecords(2, 12)
  let parent = topologyCaptured([previous, current, pending])
  var next = topologyRecords(3, 6)
  next[0].ed25519 = peerKey
  let child = topologyCaptured([current, pending, next], atSlot = 12, parent = parent)
  assert parent.error == GenesisError.None and child.error == GenesisError.None
  assert not captureValidatorTopology(parent, topologyLimits()).value.contains(peerKey)
  assert captureValidatorTopology(child, topologyLimits()).value.contains(peerKey)
  let selected = if finalizeNew: child else: parent
  let restored = restoreLocalChainView([parent, child], selected)
  assert restored.error == ViewAdvanceError.None
  var service = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    service.close()
  let startup = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000", builders = 0, others = 0, streams = 512)
  assert service.open(startup, restored.value, topologyLimits()) == NodeError.None
  probe.open(service.localPort)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  if finalizeNew:
    while not probe.authenticated or service.peerCount == 0:
      assert getMonoTime() < deadline, "finalized new epoch admits the same authenticated validator"
      assert service.poll(getMonoTime(), 0)
      probe.poll()
    assert service.peerCount == 1
  else:
    while probe.retiredConnections == 0:
      assert getMonoTime() < deadline, "refused source completes a real connection-close observation"
      assert service.poll(getMonoTime(), 0)
      probe.poll()
      assert service.peerCount == 0, "unfinalized new-epoch topology must not grant a startup validator reservation"
    assert service.peerCount == 0 and probe.retiredConnections > 0 # TLS completion is not validator admission.

proc demandedConnection() {.raises.} =
  ## A disconnected original assurer may be outside every current topology set; only its exact TLS key and temporary lease apply.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  let other = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert raw.len == 32 and other.len == 32, "temporary peer: raw.len == 32 and other.len == 32"
  var localBytes, peerBytes = default(array[32, byte])
  for index in 0..<32:
    # Independent raw fixture keys supply expectations, never a claimed peer-provided identity.
    localBytes[index] = byte(raw[index])
    peerBytes[index] = byte(other[index])
  let local = StateEdKey(localBytes)
  let expected = StateEdKey(peerBytes)
  var rosters = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
  for epoch in 0..<3:
    for index in 0..<rosters[epoch].len: rosters[epoch][
        index].ed25519 = local # The demanded key has no validator membership or grid privilege.
  let seed = topologyCaptured(rosters)
  let view = genesisView(seed).finalizeView(seed.value.blockHash).value
  var service = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    service.close()
  var configuration = config()
  configuration.binding = ipv4Address([127'u8, 0, 0, 1])
  assert service.open(configuration, view, topologyLimits()) == NodeError.None, "temporary peer: service.open(config(), view, topologyLimits()) == NodeError.None"
  probe.listen()
  var mapped = default(array[16, byte])
  mapped[10] = 255
  mapped[11] = 255
  mapped[12] = 127
  mapped[15] = 1
  let endpoint = networkEndpoint(ipv6Address(mapped),
      probe.localPort) # Advertised IPv4-mapped metadata must match the explicit IPv4 binding after normalization.
  assert service.beginPeerConnection(local, endpoint).error == DialError.Unavailable, "temporary peer: service.beginPeerConnection(local, endpoint).error == DialError.Unavailable"
  assert service.beginPeerConnection(expected, networkEndpoint(endpoint.address, 0)).error ==
      DialError.Unavailable, "temporary peer: service.beginPeerConnection(expected, networkEndpoint(endpoint.address, 0)).error == DialError.Unava"
  let started = service.beginPeerConnection(expected, endpoint)
  assert started.error == DialError.None, "temporary peer: started.error == DialError.None"
  assert service.peerConnectionLive(started.value), "temporary peer: service.peerConnectionLive(started.value)"
  assert service.beginPeerConnection(expected, endpoint).error == DialError.Unavailable, "temporary peer: service.beginPeerConnection(expected, endpoint).error == DialError.Unavailable"
  block:
    # Two independent nodes can both have slot0/serial1; a foreign ticket must confer no cancellation authority.
    var foreign = default(NodeService)
    defer: foreign.close()
    assert foreign.open(configuration, view, topologyLimits()) == NodeError.None
    let detached = networkEndpoint(ipv4Address([127'u8, 0, 0, 1]), 1)
    let foreignDial = foreign.beginPeerConnection(expected, detached)
    assert foreignDial.error == DialError.None
    assert not foreign.cancelPeerConnection(started.value), "foreign node rejects this node's dial token"
    assert not service.cancelPeerConnection(foreignDial.value), "this node rejects a foreign dial token"
    assert foreign.peerConnectionLive(foreignDial.value)
    assert service.peerConnectionLive(started.value)
  let deadline = getMonoTime()+initDuration(seconds = 7)
  while service.peerCount != 1:
    assert getMonoTime() < deadline, "demanded non-validator TLS peer"
    pump(service, probe, 1)
  let peer = service.peerForIdentity(expected)
  assert peer.error == NodeError.None, "temporary peer: peer.error == NodeError.None"
  assert service.source(peer.value).error == NodeError.Unavailable, "temporary peer: service.source(peer.value).error == NodeError.Unavailable"
  var payload = newSeq[byte](32)
  for octet in [0'u8, 0, 1, 0, 0]: payload.add(octet)
  let request = decodeReadRequest(ReadKind.SegmentShards, payload)
  assert request.error == ReadError.None, "temporary peer: request.error == ReadError.None"
  var wire = @[139'u8, 37, 0, 0, 0]
  for octet in payload: wire.add(octet)
  let reply = @[1'u8, 0, 0, 0, 99]
  probe.expectRead(wire, reply)
  var reading = default(NodeResult[NodeRequestTicket])
  while reading.error != NodeError.None:
    reading = service.request(peer.value, request.value, ByteLimit(1000))
    assert reading.error in [NodeError.None, NodeError.Unavailable], "temporary named read admission"
    assert getMonoTime() < deadline, "temporary named read backpressure"
    if reading.error != NodeError.None: pump(service, probe,
        1) # The optional UP0 open must drain before this independent CE request can reserve its own stream.
  var observed = false
  while not observed:
    assert getMonoTime() < deadline, "named read needs no current validator role or UP0 claim"
    pump(service, probe, 1)
    let received = service.takeReply(reading.value)
    if received.error == ReadError.None:
      assert received.value.bytes == reply, "temporary peer: received.value.bytes == reply"
      observed = true
  assert service.cancelPeerConnection(started.value), "temporary peer: service.cancelPeerConnection(started.value)"
  while service.peerConnectionLive(started.value):
    assert getMonoTime() < deadline, "temporary connection retirement"
    pump(service, probe, 1)
  assert service.peerCount == 0, "temporary peer: service.peerCount == 0"
  let next = service.beginPeerConnection(expected, endpoint)
  assert next.error == DialError.None, "temporary peer: next.error == DialError.None"
  assert not service.cancelPeerConnection(started.value), "temporary peer: not service.cancelPeerConnection(started.value)"
  assert service.peerConnectionLive(next.value), "temporary peer: service.peerConnectionLive(next.value)"
  assert service.cancelPeerConnection(next.value), "temporary peer: service.cancelPeerConnection(next.value)"
  while service.peerConnectionLive(next.value):
    assert getMonoTime() < deadline, "pending handshake cancellation"
    pump(service, probe, 1)
  assert not service.cancelPeerConnection(next.value), "temporary peer: not service.cancelPeerConnection(next.value)"
  let wrong = service.beginPeerConnection(topologyKey(900), endpoint)
  assert wrong.error == DialError.None, "temporary peer: wrong.error == DialError.None"
  while service.peerConnectionLive(wrong.value):
    assert getMonoTime() < deadline, "wrong TLS identity must retire without admission"
    pump(service, probe, 1)
  assert service.peerCount == 0, "temporary peer: service.peerCount == 0"
  service.close()
  assert service.open(configuration, view, topologyLimits()) == NodeError.None, "temporary peer: service.open(config(), view, topologyLimits()) == NodeError.None"
  let reopened = service.beginPeerConnection(expected, endpoint)
  assert reopened.error == DialError.None, "temporary peer: reopened.error == DialError.None"
  assert not service.cancelPeerConnection(started.value), "temporary peer: not service.cancelPeerConnection(started.value)"
  assert not service.cancelPeerConnection(next.value), "temporary peer: not service.cancelPeerConnection(next.value)"
  assert service.peerConnectionLive(reopened.value), "temporary peer: service.peerConnectionLive(reopened.value)"
  assert service.cancelPeerConnection(reopened.value), "temporary peer: service.cancelPeerConnection(reopened.value)"
  service.close()
  service = default(NodeService) # Reusing the same storage for a fresh owner cannot recycle a retained ticket's issuer identity.
  assert service.open(configuration, view, topologyLimits()) == NodeError.None
  let fresh = service.beginPeerConnection(expected, networkEndpoint(ipv4Address([127'u8, 0, 0, 1]), 1))
  assert fresh.error == DialError.None
  assert not service.cancelPeerConnection(started.value), "fresh owner rejects tickets retained across storage reuse"
  assert service.peerConnectionLive(fresh.value)
  assert service.cancelPeerConnection(fresh.value)

proc main() {.raises.} =
  ## Failed/default inputs cannot grant a socket, ticket or peer source; repeated full lifetimes release ARC owners.
  bootstrap(false)
  bootstrap(true)
  let view = source()
  var unopened = default(NodeService)
  assert not unopened.isOpen and unopened.localPort == 0 and unopened.peerCount == 0
  assert unopened.takeRead().error == NodeError.Unavailable
  assert not unopened.readLive(default(NodeReadTicket))
  assert not unopened.requestLive(default(NodeRequestTicket))
  assert not unopened.cancelRequest(default(NodeRequestTicket))
  assert unopened.takeReply(default(NodeRequestTicket)).error == ReadError.InvalidStream
  assert unopened.respond(default(NodeReadTicket), default(ReadReply)) == ReadError.InvalidStream
  unopened.close()
  let noFinality = genesisView(view.bestBlock)
  assert unopened.open(config(), noFinality, topologyLimits()) == NodeError.NoFinality
  assert unopened.open(default(ConnectionConfig), view, topologyLimits()) == NodeError.InvalidConfig
  demandedConnection()
  transcript(view)
  let beforeTranscript = getOccupiedMem()
  transcript(view)
  assertArcRelease(beforeTranscript, getOccupiedMem(), "node service stream/worker lifetimes")
  paired(false)
  paired(true)
  lifetime(view, false)
  lifetime(view, true)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    lifetime(view, iteration mod 3 == 0) # Exercise successful and post-allocation failed TLS/native setup.
  let after = getOccupiedMem()
  assertArcRelease(before, after, "node service factory allocations")
  recordArcRelease("jamnp_node_service", 1000, before, after)
  echo "jamnp node service: startup and stream lifetimes passed"
try:
  main()
except:
  quit 2 # Setup exceptions cannot satisfy a successful authenticated transcript.
