# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_preimage_announcements_arc_release"}

## Independent CE142/143 transcripts exercise role/request gates, empty acknowledgments and checked detached retention.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/preimage_followup
import ../../../src/app/proof/worker
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[header, bounded]
import ../../../src/codec/state/[safrole, service_values, requests]
import ../../../src/state/store
import ../../../src/crypto/primitives
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, read_validation,
    canonical_read, preimage_announcement, preimage_cache]
import ../../../src/lib/json/writer as json_writer
import ../../support/[jamnp_preimage_fixture, jamnp_topology_fixture, jamnp_node_probe,
    jamnp_read_validation_context, arc_evidence]
proc hex(input: openArray[byte]): string =
  ## Independent canonical chainspec encoding does not use a production configuration serializer.
  result = ""
  for octet in input: result.add(toHex(int(octet), 2).toLowerAscii())
proc chainText(saved: BlockSnapshot): string =
  ## Retain the complete fixture's original opaque chapters and exact header/profile.
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(saved.header, wire).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<saved.keyCount:
    let key = saved.keyAt(StateKeyIndex(index))
    entries.add(hex(array[31, byte](key)), json(hex(saved.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hex(topologySettings().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])
proc frame(body: seq[byte]): seq[byte] =
  ## Independent E4 framing includes a zero length for an empty preimage, but not for CE142 acknowledgment.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(body.len) shr (8*index)) and 255))
  for octet in body: result.add(octet)
proc wireRequest(request: ReadRequest): seq[byte] =
  ## Independent selector and fixed payload extent precede the unchanged claim/hash.
  result = @[byte(request.kind), byte(request.payload.len), 0, 0, 0]
  for octet in request.payload: result.add(octet)
proc checked(body: seq[byte]): CheckedReadReply =
  ## Only the real full-hash verifier creates cache input authority.
  let hash = blake2b256(body).value
  let query = decodeReadRequest(ReadKind.Preimage, array[32, byte](hash)).value
  let verified = verifyReadReply(query, frame(body), default(ReadSource), readVerificationLimits())
  assert verified.error == ReadVerificationError.None
  verified.value
proc cycle(blob: CheckedReadReply) =
  ## One isolated value cache retires every ARC wire owner before memory sampling.
  var cache = default(PreimageCache)
  assert cache.remember(blob) == PreimageCacheError.None
  assert cache.contains(blob.request, uint32(blob.preimageByteLength))
  assert cache.find(blob.request).value.bytes == frame(blob.preimageBytes)
  cache.clear()
  assert cache.len == 0 and cache.byteLength == 0
proc pure() {.raises.} =
  ## Exact framing, reserved namespaces, canonical request/account gates and bounded retention have independent witnesses.
  let blob = checked(@[1'u8, 2, 3])
  let notice = announcementRequest(ServiceIndex(42), blob.preimageHash, RequestLength(3)).value
  let request = notice.request
  assert uint64(request.minimumReplyBytes) == 0 and request.replyMessageCount == 0
  assert captureReadReply(request, []).error == ReadError.None
  assert captureReadReply(request, @[0'u8, 0, 0, 0]).error == ReadError.InvalidRequest
  let acknowledged = verifyReadReply(request, [], default(ReadSource), readVerificationLimits())
  assert acknowledged.error == ReadVerificationError.None and acknowledged.value.kind ==
      ReadKind.PreimageAnnouncement
  assert verifyReadReply(request, @[0'u8, 0, 0, 0], default(ReadSource),
      readVerificationLimits()).error != ReadVerificationError.None
  for size in [0, 39, 41]: assert decodeAnnouncement(newSeq[byte](size)).error ==
      ReadError.InvalidRequest
  assert announcementRequest(ServiceIndex(42), blob.preimageHash,
      RequestLength(high(uint32))).error == ReadError.InvalidRequest
  assert announcementRequest(ServiceIndex(42), blob.preimageHash,
      RequestLength(uint32(MaxReadReplyBytes))).error == ReadError.LimitExceeded
  let saved = preimageSnapshot(blob.preimageHash, RequestLength(3))
  assert saved.error == GenesisError.None
  let view = genesisView(saved)
  assert view.requested(notice) == ReadError.None
  let response = serveCanonicalRead(view, request)
  assert response.error == ReadError.None and response.value.byteLength == 0
  assert response.value.effect == ReadEffect.FetchPreimage
  let absent = preimageSnapshot(blob.preimageHash, RequestLength(3), account = false)
  assert genesisView(absent).requested(notice) == ReadError.Unavailable
  let available = preimageSnapshot(blob.preimageHash, RequestLength(3), history = availableHistory(
      RequestSlot(7)))
  assert genesisView(available).requested(notice) == ReadError.Unavailable
  let malformed = preimageSnapshot(blob.preimageHash, RequestLength(3), malformed = true)
  assert genesisView(malformed).requested(notice) == ReadError.BackendFailure
  let stored = servicePreimageEntry(ServiceIndex(42), blob.preimageHash, blob.preimageBytes,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(3)))
  assert stored.error == ServiceValueError.None
  let possessed = preimageSnapshot(blob.preimageHash, RequestLength(3), extra = @[stored.value])
  let noFetch = serveCanonicalRead(genesisView(possessed), request)
  assert noFetch.error == ReadError.None and noFetch.value.effect == ReadEffect.None
  var cache = default(PreimageCache)
  assert cache.remember(default(CheckedReadReply)) == PreimageCacheError.InvalidPreimage
  assert cache.remember(acknowledged.value) == PreimageCacheError.InvalidPreimage
  assert cache.remember(checked(@[])) == PreimageCacheError.None
  assert cache.byteLength == 4
  for index in 0..<9: assert cache.remember(checked(@[byte(index)])) == PreimageCacheError.None
  assert cache.len == 8 and cache.byteLength == 40
  assert cache.find(checked(@[0'u8]).request).error == PreimageCacheError.Missing
  assert cache.contains(checked(@[8'u8]).request, 1)
  assert not cache.contains(checked(@[8'u8]).request, high(uint32))
  cache.clear()
  for index in 0..<5:
    var large = newSeq[byte](7*1024*1024)
    large[0] = byte(index)
    assert cache.remember(checked(large)) == PreimageCacheError.None
    assert cache.byteLength <= MaxPreimageCacheBytes
  assert cache.len == 4, "logical byte capacity evicts before eight-row capacity"
  cache.clear()
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(blob)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_preimage_announcements", 1000, before, after)
proc poll(host: var ApplicationNode, services: var Services, probe: var NodeProbe) {.raises.} =
  ## One host turn performs no canonical graph inspection in this test while a foreign worker owns its lease.
  assert host.poll(getMonoTime(), StateTime(7), 0)
  probe.poll()
  services.tick(uint32(host.peerCount))
proc connect(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    protocol: string, hash: genesis.BlockHash) {.raises.} =
  ## Ready means both authenticated transport and admitted host-side UP0, not first response bytes alone.
  probe.open(host.localPort, protocol)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while host.peerCount == 0 or host.source(host.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    poll(host, services, probe)
proc live(body, returned: seq[byte], validator = true, expected = true) {.raises.} =
  ## A literal announcement causes same-connection acquisition; invalid content/role never populates retention.
  let blob = checked(body)
  let notice = announcementRequest(ServiceIndex(42), blob.preimageHash, RequestLength(uint32(
      body.len))).value
  let saved = preimageSnapshot(blob.preimageHash, notice.length, validator = validator)
  assert saved.error == GenesisError.None
  writeFile("preimage-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "preimage-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "preimage announcements")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, selectedAlpn, hash)
  let refused = host.announcePreimage(host.peerAt(0).value, ServiceIndex(42), blob,
      readVerificationLimits())
  assert refused.error == NodeError.InvalidSource and host.cachedPreimageCount == 0
  probe.expectRead(wireRequest(blob.request), frame(returned))
  let announcing = probe.issue(wireRequest(notice.request))
  let deadline = getMonoTime()+initDuration(seconds = 5)
  if not validator:
    while not probe.flows[announcing].reset:
      assert getMonoTime() < deadline
      poll(host, services, probe)
    assert not probe.flows[announcing].receivedFin and probe.served == 0
    assert host.cachedPreimageCount == 0 and host.pendingPreimageCount == 0
    return
  while not probe.flows[announcing].receivedFin or probe.served == 0 or host.pendingPreimageCount != 0:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert probe.bytes(announcing).len == 0 and not probe.flows[announcing].reset
  assert probe.served == 1
  if not expected:
    assert host.cachedPreimageCount == 0 and host.cachedPreimageBytes == 0
    return # Hash and advertised-length failures must remain ordinary content misses.
  assert host.cachedPreimageCount == 1 and host.cachedPreimageBytes == body.len+4
  assert serveCanonicalRead(services.chainView, blob.request).error == ReadError.Unavailable
  let draining = getMonoTime()+initDuration(milliseconds = 20)
  while getMonoTime() < draining: poll(host, services, probe)
  let duplicate = probe.issue(wireRequest(notice.request))
  while not probe.flows[duplicate].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert probe.bytes(duplicate).len == 0 and probe.served == 1
  assert host.pendingPreimageCount == 0, "retained content suppresses a duplicate announcement fetch"
  let foreign = services.beginNetworkRead(readStateRequest(hash))
  assert foreign.error == StateProofAdmissionError.None
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    probe.poll()
  let reading = probe.issue(wireRequest(blob.request))
  while not probe.flows[reading].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert probe.bytes(reading) == frame(body) and not probe.flows[reading].reset
  assert services.stateProofActive and services.stateProofPhase == ProofWorkerPhase.Done
  host.close()
  assert services.stateProofActive and host.cachedPreimageCount == 0
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
proc queued() {.raises.} =
  ## Eight fixed intents deduplicate exact content and retire after source closure without reconnecting.
  let blob = checked(@[1'u8, 2, 3])
  let saved = preimageSnapshot(blob.preimageHash, RequestLength(3))
  let view = genesisView(saved).finalizeView(saved.value.blockHash).value
  var streams = default(NodeService)
  var services = default(Services)
  var fetches = default(PreimageFollowups)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    fetches.close(services, streams)
    streams.close()
  fetches.reset()
  let selectedAlpn = "jamnp-s/1/00000000"
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert streams.open(config, view, topologyLimits()) == NodeError.None
  probe.open(streams.localPort, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while streams.peerCount == 0 or not probe.authenticated:
    assert getMonoTime() < deadline
    assert streams.poll(getMonoTime(), 0)
    probe.poll()
  let peer = streams.peerAt(0).value
  for index in 0..<8:
    var identity = default(array[32, byte])
    identity[0] = byte(index)
    let notice = announcementRequest(ServiceIndex(42), ServicePreimageHash(identity), RequestLength(3)).value
    assert fetches.enqueue(streams, peer, notice, getMonoTime()), "live source accepts bounded queued intent"
    assert fetches.enqueue(streams, peer, notice, getMonoTime()), "live source accepts bounded queued intent"
    assert fetches.pendingCount == index+1, "duplicate content occupies one intent"
  var ninth = default(array[32, byte])
  ninth[0] = 8
  assert not fetches.enqueue(streams, peer, announcementRequest(ServiceIndex(42),
      ServicePreimageHash(ninth), RequestLength(3)).value, getMonoTime())
  probe.disconnect()
  while streams.peerLive(peer):
    assert getMonoTime() < deadline
    assert streams.poll(getMonoTime(), 0)
    probe.poll() # Send the queued close before retiring the probe socket.
  fetches.poll(services, streams, getMonoTime())
  assert fetches.pendingCount == 0, "queued intents retire after source closure"
  assert streams.peerCount == 0, "source reservation retires"
proc publish(reply: seq[byte], holdFin = false) {.raises.} =
  ## A checked local introduction requires a real validator recipient and exact peer FIN before acknowledgment success.
  let blob = checked(@[7'u8, 8, 9])
  let notice = announcementRequest(ServiceIndex(42), blob.preimageHash, RequestLength(3)).value
  let saved = preimageSnapshot(blob.preimageHash, notice.length, validator = false,
      recipient = true)
  assert saved.error == GenesisError.None
  writeFile("preimage-publisher-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "preimage-publisher-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "preimage publisher")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, selectedAlpn, hash)
  probe.expectRead(wireRequest(notice.request), reply, holdFin = holdFin)
  let missing = host.announcePreimage(host.peerAt(0).value, ServiceIndex(43), blob,
      readVerificationLimits())
  assert missing.error == NodeError.InvalidSource and host.cachedPreimageCount == 0
  let started = host.announcePreimage(host.peerAt(0).value, ServiceIndex(42), blob,
      readVerificationLimits())
  assert started.error == NodeError.None, "publisher admits exact requested local blob"
  assert host.cachedPreimageCount == 1, "publisher retains blob for followup"
  let deadline = getMonoTime()+initDuration(seconds = 5)
  if holdFin:
    while probe.served == 0:
      assert getMonoTime() < deadline
      poll(host, services, probe)
    let paused = getMonoTime()+initDuration(milliseconds = 30)
    while getMonoTime() < paused: poll(host, services, probe)
    assert host.checkedPhase(started.value) == CheckedRequestPhase.Receiving
    probe.enable(1, finish = true) # UP0 occupies flow0; the first remote CE142 owns flow1.
  while host.checkedPhase(started.value) != CheckedRequestPhase.Done:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  let completed = host.takeChecked(started.value)
  if reply.len == 0:
    assert completed.kind == CheckedCompletionKind.Completed
    assert completed.value.error == ReadVerificationError.None
    assert completed.value.value.kind == ReadKind.PreimageAnnouncement
    let reading = probe.issue(wireRequest(blob.request))
    while not probe.flows[reading].receivedFin:
      assert getMonoTime() < deadline
      poll(host, services, probe)
    assert probe.bytes(reading) == frame(blob.preimageBytes)
  else:
    assert completed.kind == CheckedCompletionKind.NetworkFailure # A fabricated E4 acknowledgment fails at the framing boundary.
proc privateWorker(replacement: bool) {.raises.} =
  ## Close joins only a matching private verification; stale cancellation must preserve a later foreign Done lease.
  let blob = checked(@[4'u8, 5, 6])
  let notice = announcementRequest(ServiceIndex(42), blob.preimageHash, RequestLength(3)).value
  let saved = preimageSnapshot(blob.preimageHash, notice.length)
  assert saved.error == GenesisError.None
  writeFile("preimage-private-worker-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "preimage-private-worker-chain.json"], options)
  var services = default(Services)
  var streams = default(NodeService)
  var fetches = default(PreimageFollowups)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    fetches.close(services, streams)
    streams.close()
    services.close()
  assert services.start(options, "preimage private worker")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert streams.open(config, services.chainView, topologyLimits()) == NodeError.None
  fetches.reset()
  probe.open(streams.localPort, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    assert streams.poll(getMonoTime(), 0)
    probe.poll()
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while streams.peerCount == 0 or streams.source(streams.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    assert streams.poll(getMonoTime(), 0)
    probe.poll()
  probe.expectRead(wireRequest(blob.request), frame(blob.preimageBytes))
  assert fetches.enqueue(streams, streams.peerAt(0).value, notice, getMonoTime())
  while not services.stateProofActive:
    assert getMonoTime() < deadline
    assert streams.poll(getMonoTime(), 0)
    probe.poll()
    fetches.poll(services, streams, getMonoTime())
    discard fetches.submitWaiting(services)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    probe.poll() # Do not collect through the followup owner before testing its joined close.
  assert fetches.pendingCount == 1 and fetches.cachedCount == 0
  if replacement:
    services.stopStateProofs()
    let foreign = services.beginNetworkRead(readStateRequest(hash))
    assert foreign.error == StateProofAdmissionError.None
    while services.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
      probe.poll()
    fetches.close(services, streams)
    assert services.stateProofActive and services.stateProofPhase == ProofWorkerPhase.Done
    assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  else:
    fetches.close(services, streams)
    assert services.stateProofAvailable and not services.stateProofActive
  assert fetches.pendingCount == 0 and fetches.cachedCount == 0
proc main() {.raises.} =
  ## Each fresh transport isolates independent success, zero-byte, cryptographic, exact-length and role witnesses.
  pure()
  queued()
  privateWorker(false)
  privateWorker(true)
  publish(@[], holdFin = true)
  publish(@[0'u8, 0, 0, 0])
  live(@[1'u8, 2, 3], @[1'u8, 2, 3])
  live(@[], @[])
  live(@[1'u8, 2, 3], @[1'u8, 2, 4], expected = false)
  live(@[1'u8, 2, 3], @[1'u8, 2], expected = false)
  live(@[1'u8, 2, 3], @[1'u8, 2, 3], validator = false)
  echo "jamnp preimage announcements: exact FIN, requested acquisition and detached checked cache passed"
try: main()
except: quit 2 # Exceptions cannot substitute for protocol/ownership success.
