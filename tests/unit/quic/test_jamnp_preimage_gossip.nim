# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_preimage_gossip_arc_release"}

## Actual third-peer TLS delivery follows verified requested content and effective validator grid admission.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options, startup]
import ../../../src/app/proof/worker
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[header, bounded]
import ../../../src/codec/state/[safrole, service_values, requests, accounts, trie]
import ../../../src/state/store
import ../../../src/crypto/primitives
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, read_validation,
    preimage_announcement, preimage_gossip]
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
proc cycle() =
  ## Detached scheduling namespaces and peer observations retire before the next ARC sample.
  var streams = default(NodeService)
  var gossip = default(PreimageGossip)
  let notice = announcementRequest(ServiceIndex(42), ServicePreimageHash(default(array[32, byte])),
      RequestLength(3)).value
  assert gossip.offer(streams, notice)
  assert gossip.candidate.valid and gossip.len == 1
  gossip.close(streams)
proc pure() =
  ## Capacity and opaque owner/row generations guard foreign, evicted and reopened candidates.
  var streams = default(NodeService)
  var first, second = default(PreimageGossip)
  defer:
    first.close(streams)
    second.close(streams)
  let notice = announcementRequest(ServiceIndex(42), ServicePreimageHash(default(array[32, byte])),
      RequestLength(3)).value
  assert not first.candidate.valid
  assert first.offer(streams, notice) and second.offer(streams, notice)
  let original = first.candidate
  assert not second.reject(streams, original)
  assert first.offer(streams, notice) and first.len == 1
  for index in 1..8:
    var identity = default(array[32, byte])
    identity[0] = byte(index)
    let next = announcementRequest(ServiceIndex(42), ServicePreimageHash(identity), RequestLength(3)).value
    assert first.offer(streams, next)
    assert first.len <= MaxPreimageGossip
  assert first.len == 8 and not first.reject(streams, original)
  let previous = first.candidate
  first.close(streams)
  assert first.offer(streams, previous.notice)
  assert not first.reject(streams, previous)
  assert first.reject(streams, first.candidate) and first.len == 0
  assert first.deliveredCount == 0
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle()
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_preimage_gossip", 1000, before, after)
proc poll(host: var ApplicationNode, services: var Services, source, neighbour: var NodeProbe,
    clock: MonoTime) {.raises.} =
  ## Only the host may acquire a canonical gate; probes retain independent literal transcripts.
  assert host.poll(clock, StateTime(7), 0)
  source.poll()
  neighbour.poll()
  services.tick(uint32(host.peerCount))
proc connect(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    selectedAlpn: string, hash: genesis.BlockHash, identity: array[32, byte], certFile = "",
        keyFile = "", sendHello = true) {.raises.} =
  ## A complete host-side UP0 precedes outbound CE traffic on this authenticated generation.
  probe.open(host.localPort, selectedAlpn, certificate = certFile, keyPath = keyFile)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    assert host.poll(getMonoTime(), StateTime(7), 0)
    probe.poll()
  if sendHello:
    var hello = @[0'u8, 37, 0, 0, 0]
    for octet in array[32, byte](hash): hello.add(octet)
    hello.add(7)
    for index in 0..<4: hello.add(0)
    discard probe.issue(hello, persistent = true)
  var ready = false
  while not ready:
    assert getMonoTime() < deadline
    assert host.poll(getMonoTime(), StateTime(7), 0)
    probe.poll()
    for index in 0..<host.peerCount:
      let peer = host.peerAt(index)
      if peer.error == NodeError.None and array[32, byte](peer.value.identity) == identity:
        if not sendHello or host.source(peer.value).error == NodeError.None: ready = true
proc publicKey(path: string): array[32, byte] {.raises.} =
  ## Fixture public identities are copied without exporting any private key bytes.
  let wire = readFile(path)
  assert wire.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(wire[index])
proc seen(host: ApplicationNode, identity: array[32, byte]): bool =
  ## Historical peer facts never stand in for an active authenticated generation.
  for index in 0..<host.peerCount:
    let peer = host.peerAt(index)
    if peer.error == NodeError.None and array[32, byte](peer.value.identity) ==
        identity: return true
  false
proc live(holdFin = false, rejectAck = false, nonGrid = false, corruptBlob = false,
    secondService = false) {.raises.} =
  ## A non-validator introduces requested bytes; a separate grid validator receives possession only after verification.
  var diagnostic = ""
  assert ensureIdentity("gossip-peer-c", diagnostic)
  let identityC = publicKey("gossip-peer-c/public.key")
  let identityB = publicKey(getEnv("RAGNAROK_TEST_PEER_B"))
  let blob = checked(@[1'u8, 2, 3])
  let notice = announcementRequest(ServiceIndex(42), blob.preimageHash, RequestLength(3)).value
  let position = if nonGrid: 4 else: 1
  var extra: seq[StateEntry] = @[]
  if secondService:
    let metadata = serviceMetadataEntry(ServiceIndex(43), default(ServiceMetadata), ByteLimit(105))
    let entryConfig = RequestEntryConfig(keyBytes: ByteLimit(36),
        history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
    let outstanding = serviceRequestEntry(ServiceIndex(43), blob.preimageHash, RequestLength(3),
        requestedHistory(), entryConfig)
    assert metadata.error == ServiceMetadataError.None and outstanding.error == RequestError.None
    extra = @[metadata.value, outstanding.value]
  let saved = preimageSnapshot(blob.preimageHash, notice.length, extra = extra, hasNeighbour = true,
      neighbour = identityC, neighbourIndex = position)
  assert saved.error == GenesisError.None
  writeFile("preimage-gossip-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "preimage-gossip-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var source, neighbour = default(NodeProbe)
  defer:
    source.close()
    neighbour.close()
    host.close()
    services.close()
  assert services.start(options, "preimage grid gossip")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  let offeredBytes = if corruptBlob: @[1'u8, 2, 4] else: blob.preimageBytes
  source.expectRead(wireRequest(blob.request), frame(offeredBytes))
  let acknowledgment = if rejectAck: @[0'u8, 0, 0, 0] else: newSeq[byte](0)
  neighbour.expectRead(wireRequest(notice.request), acknowledgment, holdFin = holdFin)
  connect(host, services, source, selectedAlpn, hash, identityB)
  connect(host, services, neighbour, selectedAlpn, hash, identityC,
      "gossip-peer-c/cert.pem", "gossip-peer-c/key.pem", sendHello = not nonGrid)
  assert host.cachedPreimageCount == 0 and host.preimageGossipCount == 0 and neighbour.served == 0
  let announcing = source.issue(wireRequest(notice.request))
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while not source.flows[announcing].receivedFin or source.served == 0 or
      host.pendingPreimageCount != 0:
    assert getMonoTime() < deadline
    poll(host, services, source, neighbour, getMonoTime())
  assert source.bytes(announcing).len == 0 and source.served == 1
  if corruptBlob:
    assert host.cachedPreimageCount == 0 and host.preimageGossipCount == 0 and neighbour.served == 0
    return # A complete wrong-hash reply must never become a possession announcement to another validator.
  assert host.cachedPreimageCount == 1 and host.preimageGossipCount == 1
  if nonGrid:
    let settle = getMonoTime()+initDuration(milliseconds = 60)
    while getMonoTime() < settle: poll(host, services, source, neighbour, getMonoTime())
    assert neighbour.served == 0 and not host.preimageGossipSending
  else:
    while neighbour.served == 0:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
  if rejectAck:
    while host.preimageGossipSending:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    assert host.deliveredPreimageGossip == 0
    let base = getMonoTime()
    for attempt in 2..3:
      let at = base+initDuration(seconds = (attempt-1)*31)
      var turn = 0
      while neighbour.served < attempt or host.preimageGossipSending:
        assert getMonoTime() < deadline
        poll(host, services, source, neighbour, at+initDuration(microseconds = turn))
        inc turn
      assert host.deliveredPreimageGossip == 0
    for turn in 0..<200:
      poll(host, services, source, neighbour, base+initDuration(seconds = 100, microseconds = turn))
    assert neighbour.served == 3 and not host.preimageGossipSending
    return # Finite failed acknowledgment retries cannot grow streams without bound.
  if nonGrid:
    assert host.deliveredPreimageGossip == 0 # An authenticated validator outside the accepted grid receives no gossip.
  elif not holdFin:
    while host.preimageGossipSending or host.deliveredPreimageGossip == 0:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    if secondService:
      let other = announcementRequest(ServiceIndex(43), blob.preimageHash, RequestLength(3)).value
      neighbour.expectRead(wireRequest(other.request), @[])
      let introduced = source.issue(wireRequest(other.request))
      while not source.flows[introduced].receivedFin or neighbour.served < 2 or
          host.preimageGossipSending:
        assert getMonoTime() < deadline
        poll(host, services, source, neighbour, getMonoTime())
      assert source.served == 1 and host.cachedPreimageCount == 1
      assert host.preimageGossipCount == 2 and host.deliveredPreimageGossip == 2
      return # Service-specific possession is distributed even when the verified content owner is shared.
    let duplicate = source.issue(wireRequest(notice.request))
    while not source.flows[duplicate].receivedFin:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    let settle = getMonoTime()+initDuration(milliseconds = 30)
    while getMonoTime() < settle: poll(host, services, source, neighbour, getMonoTime())
    assert neighbour.served == 1 and host.deliveredPreimageGossip == 1
    neighbour.disconnect()
    while seen(host, identityC):
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    neighbour.close()
    connect(host, services, neighbour, selectedAlpn, hash, identityC,
        "gossip-peer-c/cert.pem", "gossip-peer-c/key.pem")
    while neighbour.served < 2 or host.preimageGossipSending:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    assert host.deliveredPreimageGossip == 2
  else:
    assert host.preimageGossipSending and host.deliveredPreimageGossip == 0
  var retained = blob
  if not holdFin and not nonGrid:
    for index in 50..<59:
      let replacement = checked(@[byte(index), 2, 3])
      source.expectRead(wireRequest(replacement.request), frame(replacement.preimageBytes))
      let peer = host.peerAt(0).value
      assert array[32, byte](peer.identity) == identityB
      let started = host.requestChecked(peer, replacement.request, readVerificationLimits())
      assert started.error == NodeError.None
      while host.checkedPhase(started.value) != CheckedRequestPhase.Done:
        assert getMonoTime() < deadline
        poll(host, services, source, neighbour, getMonoTime())
      assert host.takeChecked(started.value).value.error == ReadVerificationError.None
      retained = replacement
    while host.preimageGossipCount != 0:
      assert getMonoTime() < deadline
      poll(host, services, source, neighbour, getMonoTime())
    assert host.cachedPreimageCount == 8 and neighbour.served == 2
  let foreign = services.beginNetworkRead(readStateRequest(hash))
  assert foreign.error == StateProofAdmissionError.None
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    source.poll()
    neighbour.poll()
  let reading = neighbour.issue(wireRequest(retained.request))
  while not neighbour.flows[reading].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, source, neighbour, getMonoTime())
  assert neighbour.bytes(reading) == frame(retained.preimageBytes)
  assert services.stateProofActive and services.stateProofPhase == ProofWorkerPhase.Done
  host.close()
  assert host.preimageGossipCount == 0 and not host.preimageGossipSending
  assert services.stateProofActive
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
proc main() {.raises.} =
  ## Independent pure ownership and actual three-party network witnesses cover success, withheld FIN and finite rejection.
  pure()
  live()
  live(holdFin = true)
  live(nonGrid = true)
  live(corruptBlob = true)
  live(secondService = true)
  live(rejectAck = true)
  echo "jamnp preimage gossip: checked possession follows validator grid and peer generations"
try: main()
except: quit 2 # Setup exceptions never establish successful gossip or lease preservation.
