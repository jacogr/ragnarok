# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_ticket_forwarding_arc_release"}

## Real proxy proofs are scheduled across all current validators, independent of the UP0 grid and CPU lease ownership.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/jamnp-s/[ticket_packet, ticket_validation, ticket_forwarding]
import ../../../src/app/[node as application_node, services, options, startup]
import ../../../src/app/proof/worker
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/state/store
import ../../../src/lib/json/writer as json_writer
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, identity, topology]
import ../../../src/codec/[header, tickets]
import ../../../src/codec/state/safrole
import ../../support/[jamnp_ticket_fixture, jamnp_topology_fixture, jamnp_node_probe,
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
  $jsonObject([("protocol_parameters", json(hex(saved.chainParameters.encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])
proc wirePacket(packet: TicketPacket, distribution: bool): seq[byte] =
  ## Independent literal E4 length789 spans two nonzero octets; the proof remains exactly784 bytes.
  result = @[if distribution: 132'u8 else: 131'u8]
  for octet in [21'u8, 3, 0, 0]: result.add(octet)
  for octet in packet.packetBytes: result.add(octet)
proc cycle(streams: var NodeService, source: TicketSource, proof: CheckedNetworkTicket) =
  ## A detached scheduler retains one immutable proof and no canonical graph or active Native exchange.
  var owner = default(TicketForwarding)
  assert owner.advance(streams, source, StateTime(1), StateTime(1))
  assert owner.offer(proof) and owner.offer(proof) and owner.len == 1
  owner.close(streams)
  assert owner.len == 0 and owner.sending == 0
proc pure() {.raises.} =
  ## Selected-source retirement and kind separation are independent from Native handshake timing.
  let local = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let peerKey = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let fixture = ticketFixture(local, peerKey)
  let source = captureTicketSource(fixture.saved).value
  let proof = verifyNetworkTicket(source, fixture.packet,
      TicketRecipient(local: local, peer: peerKey, now: StateTime(1), connectivityEpoch: 0,
          delivery: TicketDelivery.Proxy)).value
  let distributed = verifyNetworkTicket(source, fixture.packet,
      TicketRecipient(local: peerKey, peer: local, now: StateTime(1), connectivityEpoch: 0,
          delivery: TicketDelivery.Distribution)).value
  let view = restoreLocalChainView([fixture.saved], fixture.saved)
  assert view.error == ViewAdvanceError.None
  var streams = default(NodeService)
  var owner = default(TicketForwarding)
  defer:
    owner.close(streams)
    streams.close()
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000", streams = 512)
  assert streams.open(config, view.value, topologyLimits(2)) == NodeError.None
  assert owner.advance(streams, source, StateTime(1), StateTime(1))
  assert not owner.offer(distributed) # Same cryptographic/source context, different authenticated step.
  assert owner.offer(proof) and owner.offer(proof) and owner.len == 1
  let finalized = ticketFixture(local, peerKey, included = true, atSlot = 2)
  assert owner.advance(streams, captureTicketSource(finalized.saved).value, StateTime(2), StateTime(1))
  assert owner.len == 0
  assert not owner.offer(proof)
  owner.close(streams)
  assert owner.advance(streams, source, StateTime(2), StateTime(1)) and owner.offer(proof)
  owner.expire(streams, StateTime(5))
  assert owner.len == 0 and owner.sending == 0
  assert not owner.advance(streams, source, StateTime(5), StateTime(1))
  assert not owner.advance(streams, source, StateTime(4), StateTime(
      4)) # A connectivity application after the usable start cannot reopen an empty window.
  assert owner.advance(streams, source, StateTime(1), StateTime(1)) and owner.offer(proof)
  let changed = ticketFixture(local, peerKey, entropyChanged = true)
  assert owner.advance(streams, captureTicketSource(changed.saved).value, StateTime(1), StateTime(1))
  assert owner.len == 0 and not owner.offer(proof)
  owner.close(streams)
  cycle(streams, source, proof)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(streams, source, proof)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_ticket_forwarding", 1000, before, after)
proc poll(host: var ApplicationNode, services: var Services, source, neighbour: var NodeProbe,
    slot: StateTime) {.raises.} =
  ## All endpoints progress on one thread; source aliases retire before shared proof admission.
  assert host.poll(getMonoTime(), slot)
  source.poll()
  neighbour.poll()
  services.tick(uint32(host.peerCount))
proc live(distribution = false, rejectAck = false, holdFin = false) {.raises.} =
  ## B is a grid neighbour; C occupies a current index outside A's accepted announcement grid and must still receive CE132.
  var diagnostic = ""
  assert ensureIdentity("ticket-forward-peer-c", diagnostic)
  let local = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let peer = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let third = certificateIdentity("ticket-forward-peer-c/cert.pem").value
  let fixture = ticketFixture(local, peer, distribution = distribution,
      neighbour = third, hasNeighbour = true)
  let topology = captureValidatorTopology(fixture.saved, topologyLimits(2))
  assert topology.error == TopologyError.None
  assert not topology.value.neighbours(local, third)
  assert topology.value.neighbours(local, peer)
  let neighbourDue = if fixture.proxyIndex == 4: 3'u32 else: 4'u32
  writeFile("ticket-forwarding-chain.json", chainText(fixture.saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "ticket-forwarding-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var source, neighbour = default(NodeProbe)
  defer:
    source.close()
    neighbour.close()
    host.close()
    services.close()
  assert services.start(options, "ticket forwarding")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      protocol, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(1)) == NodeError.None
  let reply = if rejectAck: @[0'u8, 0, 0, 0] else: newSeq[byte](0)
  source.expectRead(wirePacket(fixture.packet, true), reply)
  neighbour.expectRead(wirePacket(fixture.packet, true), @[], holdFin = holdFin)
  source.open(host.localPort, protocol)
  neighbour.open(host.localPort, protocol, "ticket-forward-peer-c/cert.pem", "ticket-forward-peer-c/key.pem")
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not source.authenticated or not neighbour.authenticated or host.peerCount != 2:
    assert getMonoTime() < deadline
    poll(host, services, source, neighbour, StateTime(1))
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(1)
  for index in 0..<4: hello.add(0)
  discard source.issue(hello, persistent = true)
  while host.source(host.peerAt(0).value).error != NodeError.None and
      host.source(host.peerAt(1).value).error != NodeError.None:
    assert getMonoTime() < deadline
    poll(host, services, source, neighbour, StateTime(1))
  let submitted = source.issue(wirePacket(fixture.packet, distribution))
  while not source.flows[submitted].receivedFin:
    assert getMonoTime() < deadline
    assert not source.flows[submitted].reset
    poll(host, services, source, neighbour, StateTime(1))
  assert host.pendingTicketCount == 1 and source.served == 0 and neighbour.served == 0
  if distribution:
    assert host.ticketForwardingCount == 0
    let settle = getMonoTime()+initDuration(milliseconds = 50)
    while getMonoTime() < settle: poll(host, services, source, neighbour, StateTime(4))
    assert source.served == 0 and neighbour.served == 0
    return # A genuine distribution recipient retains GP input without becoming a proxy.
  assert host.ticketForwardingCount == 1
  let atOne = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < atOne: poll(host, services, source, neighbour, StateTime(1))
  assert source.served == 0 and neighbour.served == 0
  let expected = if rejectAck: 3 else: 1
  while source.served < expected or host.ticketForwardingActive != 0:
    assert getMonoTime() < deadline, "current index0 begins at application1+delay1"
    poll(host, services, source, neighbour, StateTime(2))
  assert source.served == expected and neighbour.served == 0
  let beforeNeighbour = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < beforeNeighbour: poll(host, services, source, neighbour, StateTime(
      neighbourDue-1))
  assert source.served == expected and neighbour.served == 0
  while neighbour.served < 1 or (not holdFin and host.ticketForwardingActive != 0):
    assert getMonoTime() < deadline, "non-grid current recipient is evenly spaced to its independently calculated slot"
    poll(host, services, source, neighbour, StateTime(neighbourDue))
  assert source.served == expected and neighbour.served == 1
  if holdFin:
    assert host.ticketForwardingActive == 1
    let foreign = services.beginNetworkRead(readStateRequest(hash))
    assert foreign.error == StateProofAdmissionError.None
    while services.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
      source.poll()
      neighbour.poll()
    host.close()
    assert services.stateProofActive and host.ticketForwardingActive == 0
    assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
    return # Scheduler shutdown cancels its Native stream, preserving a foreign completed CPU lease.
  assert host.forwardedTickets == uint64(if rejectAck: 1 else: 2)
  let atFour = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < atFour: poll(host, services, source, neighbour, StateTime(4))
  assert source.served == expected and neighbour.served == 1
  poll(host, services, source, neighbour, StateTime(5))
  assert host.ticketForwardingCount == 0 and host.ticketForwardingActive == 0
proc main() {.raises.} =
  ## Timed real-network positives accompany source retirement, finite invalid-ACK retries and exact joined shutdown.
  assert sizeof(ApplicationNode) <= 128*1024, "bounded protocol owners must fit ordinary foreground thread stacks"
  pure()
  live()
  live(distribution = true)
  live(rejectAck = true)
  live(holdFin = true)
  echo "jamnp ticket forwarding: timed all-validator broadcast contracts passed"
try: main()
except: quit 2 # Setup failures never constitute successful protocol observations.
