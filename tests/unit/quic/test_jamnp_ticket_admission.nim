# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_ticket_admission_arc_release"}

## Real RingVRF positives bind independent exact packet transcripts to finalized epoch and authenticated recipient roles.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/jamnp-s/[ticket_packet, ticket_validation, ticket_pool]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/proof/[ticket_verification, worker]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/state/store
import ../../../src/lib/json/writer as json_writer
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, identity]
import ../../../src/codec/[header, tickets]
import ../../../src/bandersnatch/bandersnatch
import ../../../src/codec/state/safrole
import ../../support/[jamnp_ticket_fixture, jamnp_topology_fixture, jamnp_node_probe,
    jamnp_read_validation_context, arc_evidence]
proc pure() =
  ## Decoder boundaries never grant a proof prefix; source/clock/proxy checks retain genuine cryptographic causes.
  let local = topologyKey(9001)
  let peer = topologyKey(9002)
  let fixture = ticketFixture(local, peer)
  let source = captureTicketSource(fixture.saved)
  assert source.error == NetworkTicketError.None
  let recipient = TicketRecipient(local: local, peer: peer, now: StateTime(1), connectivityEpoch: 0,
      delivery: TicketDelivery.Proxy)
  let verified = verifyNetworkTicket(source.value, fixture.packet, recipient)
  assert verified.error == NetworkTicketError.None
  assert array[32, byte](verified.value.identifier) == array[32, byte](fixture.output)
  assert verified.value.packet.packetBytes == fixture.packet.packetBytes
  assert array[32, byte](verified.value.proxy) == array[32, byte](local)
  let job = captureTicketVerification(source.value, fixture.packet, recipient)
  assert job.error == NetworkTicketError.None
  assert executeTicketVerification(job.value).error == NetworkTicketError.None
  var pool = default(PendingTicketPool)
  assert pool.advance(source.value, StateTime(1)) == TicketPoolError.None
  assert pool.retain(verified.value, StateTime(1)) == TicketPoolError.None and pool.len == 1
  assert pool.retain(verified.value, StateTime(1)) == TicketPoolError.Duplicate and pool.len == 1
  assert pool.retain(verified.value, StateTime(12)) == TicketPoolError.InvalidWindow
  pool.expire(StateTime(12))
  assert pool.len == 0 and pool.retain(verified.value, StateTime(12)) == TicketPoolError.NoSource
  var late = default(PendingTicketPool)
  assert late.advance(source.value, StateTime(1)) == TicketPoolError.None
  assert late.retain(verified.value, StateTime(12)) == TicketPoolError.InvalidWindow and late.len == 0
  let finalized = ticketFixture(local, peer, included = true, atSlot = 2)
  let included = captureTicketSource(finalized.saved)
  assert included.error == NetworkTicketError.None
  assert verifyNetworkTicket(included.value, fixture.packet, recipient).error ==
      NetworkTicketError.NoSource
  var atSecond = recipient
  atSecond.now = StateTime(2)
  assert verifyNetworkTicket(included.value, fixture.packet, atSecond).error ==
      NetworkTicketError.AlreadyIncluded
  assert pool.advance(source.value, StateTime(1)) == TicketPoolError.None
  assert pool.retain(verified.value, StateTime(1)) == TicketPoolError.None
  assert pool.advance(included.value, StateTime(2)) == TicketPoolError.None and pool.len == 0, "finalized inclusion retires a pending identifier"
  var wrong = recipient
  wrong.local = peer
  assert verifyNetworkTicket(source.value, fixture.packet, wrong).error ==
      NetworkTicketError.WrongProxy
  wrong = recipient
  wrong.now = StateTime(12)
  assert verifyNetworkTicket(source.value, fixture.packet, wrong).error ==
      NetworkTicketError.NoSource
  wrong = recipient
  wrong.connectivityEpoch = 1
  assert verifyNetworkTicket(source.value, fixture.packet, wrong).error ==
      NetworkTicketError.NoSource
  wrong = recipient
  wrong.now = StateTime(10)
  assert verifyNetworkTicket(source.value, fixture.packet, wrong).error ==
      NetworkTicketError.InvalidWindow
  let changed = ticketFixture(local, peer, entropyChanged = true)
  let wrongEntropy = verifyNetworkTicket(captureTicketSource(changed.saved).value, fixture.packet, recipient)
  assert wrongEntropy.error == NetworkTicketError.RingFailure
  assert wrongEntropy.ringError == BsError.VerificationFailure
  for size in [0, 788, 790]: assert decodeTicketPacket(newSeq[byte](size)).error ==
      TicketPacketError.InvalidLength
  var wire = fixture.packet.packetBytes
  wire[4] = 2
  assert decodeTicketPacket(wire).error == TicketPacketError.InvalidAttempt
  let distributed = ticketFixture(local, peer, distribution = true)
  let accepted = verifyNetworkTicket(captureTicketSource(distributed.saved).value,
      distributed.packet, TicketRecipient(local: local, peer: peer, now: StateTime(1),
          connectivityEpoch: 0, delivery: TicketDelivery.Distribution))
  assert accepted.error == NetworkTicketError.None
  let rejectedProxy = verifyNetworkTicket(captureTicketSource(distributed.saved).value,
      distributed.packet, TicketRecipient(local: local, peer: local, now: StateTime(1),
          connectivityEpoch: 0, delivery: TicketDelivery.Distribution))
  assert rejectedProxy.error == NetworkTicketError.WrongProxy
  var unregistered = recipient
  unregistered.peer = topologyKey(9999)
  assert verifyNetworkTicket(source.value, fixture.packet, unregistered).error ==
      NetworkTicketError.WrongRecipient


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
  $jsonObject([("protocol_parameters", json(hex(saved.chainParameters.encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])
proc wirePacket(packet: TicketPacket, distribution: bool): seq[byte] =
  ## Independent literal E4 length789 spans two nonzero octets; the proof remains exactly784 bytes.
  result = @[if distribution: 132'u8 else: 131'u8]
  for octet in [21'u8, 3, 0, 0]: result.add(octet)
  for octet in packet.packetBytes: result.add(octet)
proc poll(host: var ApplicationNode, services: var Services, probe: var NodeProbe, now = StateTime(
    1)) {.raises.} =
  ## Only the managed actor can acquire the graph/CPU gate; the raw sender keeps an independent transcript.
  assert host.poll(getMonoTime(), now, 0)
  probe.poll()
  services.tick(uint32(host.peerCount))
proc live(distribution = false, corrupt = false, late = false, disconnect = false,
    foreignReplacement = false, localNotValidator = false, included = false,
        cutoff = false) {.raises.} =
  ## Actual TLS accepts a cryptographic packet only at its finalized proxy/current validator and exact live generation.
  let local = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let peer = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let recipient = if localNotValidator: topologyKey(9900) else: local
  let fixture = ticketFixture(recipient, peer, distribution = distribution,
      entropyChanged = corrupt, included = included)
  writeFile("ticket-admission-chain.json", chainText(fixture.saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "ticket-admission-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "ticket admission")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(1)) == NodeError.None, "ticket actor opens with exact two-core source geometry"
  probe.open(host.localPort, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(1)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while host.peerCount == 0 or host.source(host.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  let submitted = probe.issue(wirePacket(fixture.packet, distribution))
  if late or disconnect or foreignReplacement:
    while not services.stateProofActive:
      assert getMonoTime() < deadline
      poll(host, services, probe)
    while services.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
      probe.poll() # Preserve the exact completed proof before the host can collect it.
    if foreignReplacement:
      services.stopStateProofs()
      let foreign = services.beginNetworkRead(readStateRequest(hash))
      assert foreign.error == StateProofAdmissionError.None
      while services.stateProofPhase != ProofWorkerPhase.Done:
        assert getMonoTime() < deadline
        probe.poll()
      host.close()
      assert services.stateProofActive and host.pendingTicketCount == 0
      assert services.collectStateProof(foreign.value).kind ==
          ProofWorkerCompletionKind.ReadCompleted
      return # A stale ticket cannot join/release a replacement foreign job.
    if disconnect:
      probe.abort(submitted)
      let flush = getMonoTime()+initDuration(milliseconds = 100)
      while getMonoTime() < flush: probe.poll() # Progress the real native pacing deadline before the host can collect Done.
      while services.stateProofActive:
        assert getMonoTime() < deadline, "reset stream releases its exact completed proof lease"
        poll(host, services, probe)
      assert host.pendingTicketCount == 0 and not probe.flows[submitted].receivedFin, "a transmitted stream reset revokes admission before Done collection"
      return
    while not probe.flows[submitted].reset:
      assert getMonoTime() < deadline
      poll(host, services, probe, if cutoff: StateTime(10) else: StateTime(12))
    assert not probe.flows[submitted].receivedFin and host.pendingTicketCount == 0
    return # A proof valid in the old epoch cannot become current pending data or an acknowledgment after the clock advances.
  if corrupt or localNotValidator:
    while not probe.flows[submitted].reset:
      assert getMonoTime() < deadline
      poll(host, services, probe)
    assert not probe.flows[submitted].receivedFin and host.pendingTicketCount == 0
    return
  while not probe.flows[submitted].receivedFin:
    assert not probe.flows[submitted].reset, "valid ticket must not reset before bare FIN"
    assert getMonoTime() < deadline, "valid ticket reaches a complete bare-FIN acknowledgment"
    poll(host, services, probe)
  assert not probe.flows[submitted].reset and probe.bytes(submitted).len == 0
  if included:
    assert host.pendingTicketCount == 0 # A freshly verified finalized ticket is acknowledged without reintroducing it into pending data.
    return
  assert host.pendingTicketCount == 1
  assert array[32, byte](host.pendingTicketAt(0).identifier) == array[32, byte](fixture.output)
  let duplicate = probe.issue(wirePacket(fixture.packet, distribution))
  while not probe.flows[duplicate].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert host.pendingTicketCount == 1 and probe.bytes(duplicate).len == 0
  host.close()
  assert host.pendingTicketCount == 0 and services.stateProofAvailable
proc cycle(source: TicketSource, ticket: CheckedNetworkTicket) =
  ## One fixed proof-pool activation owns no source map, native handle or worker cancellation authority.
  var pool = default(PendingTicketPool)
  assert pool.advance(source, StateTime(1)) == TicketPoolError.None
  assert pool.retain(ticket, StateTime(1)) == TicketPoolError.None
  assert pool.ticketAt(0).valid
  pool.clear()
  assert pool.len == 0
proc main() {.raises.} =
  ## Every scoped counterexample has an exact runtime rejection and successful ordinary-control witness.
  pure()
  let local = topologyKey(9001)
  let peer = topologyKey(9002)
  let fixture = ticketFixture(local, peer)
  let source = captureTicketSource(fixture.saved).value
  let ticket = verifyNetworkTicket(source, fixture.packet,
      TicketRecipient(local: local, peer: peer, now: StateTime(1), connectivityEpoch: 0,
          delivery: TicketDelivery.Proxy)).value
  cycle(source, ticket)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(source, ticket)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_ticket_admission", 1000, before, after)
  live()
  live(distribution = true)
  live(corrupt = true)
  live(late = true)
  live(late = true, cutoff = true)
  live(included = true)
  live(late = true, included = true)
  live(disconnect = true)
  live(foreignReplacement = true)
  live(localNotValidator = true)
  echo "jamnp ticket admission: finalized proof and proxy contracts passed"
try: main()
except: quit 2 # Setup exceptions never establish cryptographic or cancellation success.
