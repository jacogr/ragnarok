# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_ticket_production_arc_release"}

## Genuine optional signing binds a JIP-5 key and TLS identity to the same finalized pending position.

import std/[assertions, syncio, strutils, monotimes, times, envvars]
import ../../../src/app/proof/ticket_production
import ../../../src/app/proof/worker
import ../../../src/app/[services, options, node as application_node]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/state/store
import ../../../src/lib/json/writer as json_writer
import ../../../src/jamnp-s/[ticket_packet, ticket_validation, identity, connections,
    node as node_streams]
import ../../../src/codec/[header, tickets]
import ../../../src/codec/state/safrole
import ../../../src/bandersnatch/bandersnatch
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

proc managed(seed: array[32, byte]) {.raises.} =
  ## Configuration and Done/cancellation retain the exact shared lease until collection/join; no key owner escapes configuration.
  let local = topologyKey(9101)
  let peer = topologyKey(9102)
  let fixture = ticketFixture(local, peer, useSigner = true, signerMasterSeed = seed)
  writeFile("ticket-production-chain.json", chainText(fixture.saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "ticket-production-chain.json"], options)
  var services = default(Services)
  defer: services.close()
  assert services.configureTicketSignerSeed(seed).error == TicketSignerError.Closed
  assert services.start(options, "ticket production")
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  assert not services.hasTicketSigner and services.ticketSigningVersion == 0
  let missing = services.beginTicketProduction(local, StateTime(1), 0, TicketAttempt(0))
  assert missing.error == StateProofAdmissionError.QueryFailure
  assert missing.captureFailure.error == NetworkTicketError.NoSigner
  let malformed = services.configureTicketSignerSeed(newSeq[byte](31))
  assert malformed.error == TicketSignerError.KeyFailure and malformed.keyError ==
      BsError.InvalidLength
  assert not services.hasTicketSigner and services.ticketSigningVersion == 0
  assert services.configureTicketSignerSeed(seed).error == TicketSignerError.None
  assert services.hasTicketSigner and services.ticketSigningVersion == 1
  let first = services.beginTicketProduction(local, StateTime(1), 0, TicketAttempt(0))
  assert first.error == StateProofAdmissionError.None
  assert services.configureTicketSignerSeed(seed).error == TicketSignerError.Busy
  assert services.ticketSigningVersion == 1
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
  assert services.stateProofActive and not services.stateProofAvailable
  assert services.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  assert services.stateProofActive
  let completed = services.collectStateProof(first.value)
  assert completed.kind == ProofWorkerCompletionKind.TicketProduced
  assert completed.producedTicketValue.error == NetworkTicketError.None
  assert array[32, byte](completed.producedTicketValue.value.identifier) == array[32, byte](fixture.output)
  assert services.stateProofAvailable and services.hasTicketSigner
  assert services.configureTicketSignerSeed(seed).error == TicketSignerError.None
  assert services.ticketSigningVersion == 1 # Idempotent key configuration cannot restart production attempts.
  let second = services.beginTicketProduction(local, StateTime(1), 0, TicketAttempt(1))
  assert second.error == StateProofAdmissionError.None
  services.stopStateProofs()
  assert services.stateProofAvailable and services.hasTicketSigner
  assert services.collectStateProof(second.value).kind == ProofWorkerCompletionKind.Uninitialized
  var changed = seed
  changed[0] = changed[0]+1
  assert services.configureTicketSignerSeed(changed).error == TicketSignerError.None
  assert services.ticketSigningVersion == 2
  let unrelated = services.beginTicketProduction(local, StateTime(1), 0, TicketAttempt(0))
  assert unrelated.error == StateProofAdmissionError.None
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
  let rejected = services.collectStateProof(unrelated.value)
  assert rejected.kind == ProofWorkerCompletionKind.TicketProduced
  assert rejected.producedTicketValue.error == NetworkTicketError.WrongRecipient
  services.close()
  assert not services.hasTicketSigner and services.ticketSigningVersion == 0
type
  ProductionScenario = object ## Only public test seed/fixture selection facts escape deterministic bounded setup.
    seed: array[32, byte]
    fixture: TicketFixture

proc scenario(local, peer: StateEdKey, selfProxy: bool): ProductionScenario =
  ## Fixed public fixture seeds search a small deterministic set for a genuine chosen self/remote proxy route.
  for nonce in 0..<16:
    var seed = default(array[32, byte])
    seed[0] = 71
    seed[1] = byte(nonce)
    for index in 0..<6:
      let fixture = ticketFixture(local, peer, useSigner = true, signerMasterSeed = seed,
          signerIndex = index, duration = 120, tail = 100)
      if (fixture.proxyIndex == index) == selfProxy:
        return ProductionScenario(seed: seed, fixture: fixture)
  assert false # Deterministic fixture search must establish a genuine positive; no synthetic proxy/certificate fallback exists.
  default(ProductionScenario)

proc actorPoll(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    slot: StateTime) {.raises.} =
  ## The actual actor serializes canonical signing leases while the independent peer observes literal request/FIN data.
  assert host.poll(getMonoTime(), slot, 0)
  probe.poll()
  services.tick(uint32(host.peerCount))

proc actor(selfProxy = false, absent = false, wrong = false, rejectAck = false,
    holdFin = false, late = false, cutoff = false, closeDone = false,
    foreignReplacement = false) {.raises.} =
  ## E120/Tail100 distinguishes first-step application1+2 from self-proxy forwarding application1+6.
  let local = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let peerKey = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let selected = scenario(local, peerKey, selfProxy)
  let source = captureTicketSource(selected.fixture.saved).value
  let signer = captureTicketSigner(selected.seed).value
  var expectedRemote = 0
  var expectedSelf = 0
  for attempt in 0..<2:
    let job = captureTicketProduction(source, signer, local, StateTime(3), 0, TicketAttempt(uint8(attempt)))
    let result = executeTicketProduction(job.value)
    assert result.error == NetworkTicketError.None
    if array[32, byte](result.value.proxy) == array[32, byte](peerKey): inc expectedRemote
    if array[32, byte](result.value.proxy) == array[32, byte](local): inc expectedSelf
  if selfProxy: assert expectedSelf > 0 and expectedRemote == 0
  else: assert expectedRemote > 0
  writeFile("ticket-production-actor-chain.json", chainText(selected.fixture.saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "ticket-production-actor-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "local ticket actor")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  if not absent:
    var seed = selected.seed
    if wrong: seed[0] = seed[0]+1
    assert services.configureTicketSignerSeed(seed).error == TicketSignerError.None
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      protocol, streams = 512)
  assert host.open(services, config, topologyLimits(2, 120), StateTime(1)) == NodeError.None
  let reply = if rejectAck: @[0'u8, 0, 0, 0] else: newSeq[byte](0)
  probe.expectTickets(1, reply = reply, holdFin = holdFin)
  probe.open(host.localPort, protocol)
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated or host.peerCount == 0:
    assert getMonoTime() < deadline
    actorPoll(host, services, probe, StateTime(1))
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(1)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while host.source(host.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    actorPoll(host, services, probe, StateTime(1))
  let early = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < early: actorPoll(host, services, probe, StateTime(2))
  assert host.generatedTickets == 0 and not host.ticketProductionActive and probe.served == 0
  if absent or wrong:
    let settle = getMonoTime()+initDuration(milliseconds = 150)
    while getMonoTime() < settle: actorPoll(host, services, probe, StateTime(3))
    assert host.generatedTickets == 0 and probe.served == 0 and not host.ticketProductionActive
    if absent: assert host.lastProducedTicket.error == NetworkTicketError.Uninitialized
    else: assert host.lastProducedTicket.error == NetworkTicketError.WrongRecipient
    return # Registered transport identity alone cannot manufacture an optional signing capability.
  if late or closeDone or foreignReplacement:
    while not host.ticketProductionActive:
      assert getMonoTime() < deadline
      actorPoll(host, services, probe, StateTime(3))
    while services.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
      probe.poll() # Preserve a genuinely completed signer activation before any actor collection.
    if foreignReplacement:
      services.stopStateProofs()
      let foreign = services.beginNetworkRead(readStateRequest(hash))
      assert foreign.error == StateProofAdmissionError.None
      while services.stateProofPhase != ProofWorkerPhase.Done:
        assert getMonoTime() < deadline
        probe.poll()
      host.close()
      assert services.stateProofActive and services.hasTicketSigner
      assert services.collectStateProof(foreign.value).kind ==
          ProofWorkerCompletionKind.ReadCompleted
      return # A stale production ticket cannot join a replacement foreign completed job.
    if closeDone:
      host.close()
      assert services.stateProofAvailable and services.hasTicketSigner
      assert not host.ticketProductionActive and host.generatedTickets == 0 and probe.served == 0
      return # Exact joined close retires the private signer borrow without emitting a proof prefix.
    actorPoll(host, services, probe, if cutoff: StateTime(50) else: StateTime(120))
    assert host.lastProducedTicket.error == NetworkTicketError.None
    assert host.generatedTickets == 0 and host.pendingTicketCount == 0
    assert host.ticketOriginActive == 0 and host.ticketForwardingCount == 0 and probe.served == 0
    assert services.stateProofAvailable and not host.ticketProductionActive
    return # Old genuine crypto facts confer no fresh delivery/pending authority after the first-step window or epoch expires.
  let expected = expectedRemote*(if rejectAck: 3 else: 1)
  while host.generatedTickets < 2 or host.ticketProductionActive or probe.served < expected or
      (not holdFin and host.ticketOriginActive != 0):
    assert getMonoTime() < deadline, "genuine first-step requests begin after the E/60 delay"
    actorPoll(host, services, probe, StateTime(3))
  assert probe.served == expected
  let active = host.ticketOriginActive
  assert services.configureTicketSignerSeed(selected.seed).error == TicketSignerError.None
  assert services.ticketSigningVersion == 1
  let unchanged = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < unchanged: actorPoll(host, services, probe, StateTime(3))
  assert host.generatedTickets == 2 and probe.served == expected
  if holdFin: assert host.ticketOriginActive == active # Reapplying the same key neither cancels pending CE131 nor reopens epoch attempts.
  assert host.pendingTicketCount == expectedSelf
  if holdFin:
    assert host.ticketOriginActive > 0
    let foreign = services.beginNetworkRead(readStateRequest(hash))
    assert foreign.error == StateProofAdmissionError.None
    while services.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
      probe.poll()
    host.close()
    assert host.ticketOriginActive == 0 and services.stateProofActive and services.hasTicketSigner
    assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
    return # Native CE131 cancellation cannot join or release a foreign completed CPU lease.
  assert host.originatedTickets == uint64(if rejectAck: 0 else: expectedRemote)
  let beforeForward = getMonoTime()+initDuration(milliseconds = 30)
  while getMonoTime() < beforeForward: actorPoll(host, services, probe, StateTime(6))
  assert probe.served == expected
  if rejectAck:
    assert expectedRemote > 0 and not selfProxy
    return # Three malformed acknowledgments exhaust only bounded origin exchanges; no fourth request appears.
  while probe.served < expectedRemote+expectedSelf or host.ticketForwardingActive != 0:
    assert getMonoTime() < deadline, "self-proxies skip CE131 and retain the later E/20 forwarding delay"
    actorPoll(host, services, probe, StateTime(7))
  assert probe.served == expectedRemote+expectedSelf
  var firstSteps = 0
  var broadcasts = 0
  for index in 0..<16:
    let wire = probe.bytes(index)
    if wire.len != 794: continue # UP0 is a separate persistent stream, never a ticket envelope.
    let packet = decodeTicketPacket(wire.toOpenArray(5, 793))
    assert packet.error == TicketPacketError.None
    let distribution = wire[0] == 132
    let delivery = if distribution: TicketDelivery.Distribution else: TicketDelivery.Proxy
    let verified = verifyNetworkTicket(source, packet.value,
        TicketRecipient(local: peerKey, peer: local, now: StateTime(7), connectivityEpoch: 0,
            delivery: delivery))
    assert verified.error == NetworkTicketError.None
    if distribution: inc broadcasts
    else: inc firstSteps
  assert firstSteps == expectedRemote and broadcasts == expectedSelf
  if selfProxy: assert firstSteps == 0
  actorPoll(host, services, probe, StateTime(50))
  assert host.ticketOriginActive == 0 and host.ticketForwardingCount == 0
  assert host.pendingTicketCount == expectedSelf # Half-lottery delivery retirement does not erase still-valid GP block inputs before the GP cutoff.

proc sourceCycle(saved: BlockSnapshotResult) =
  ## Fresh detached BS/Ed/inclusion metadata must release on every selected-source replacement.
  let source = captureTicketSource(saved)
  assert source.error == NetworkTicketError.None and source.value.pendingCount == 6
  assert source.value.networkAttempts == 2

proc cycle(seed: array[32, byte]) =
  ## Opaque key resource aliases retire through one private callback after the last ARC owner.
  let signer = captureTicketSigner(seed)
  assert signer.error == TicketSignerError.None and signer.value.valid
  let alias = signer.value
  assert alias.valid

proc main() {.raises.} =
  ## Every produced proof is verified again against an independently captured source and ordinary network recipient contract.
  var seed = default(array[32, byte])
  seed[0] = 71
  let local = topologyKey(9101)
  let peer = topologyKey(9102)
  let fixture = ticketFixture(local, peer, useSigner = true, signerMasterSeed = seed)
  let source = captureTicketSource(fixture.saved)
  assert source.error == NetworkTicketError.None
  let signer = captureTicketSigner(seed)
  assert signer.error == TicketSignerError.None
  let admitted = captureTicketProduction(source.value, signer.value, local, StateTime(1), 0,
      TicketAttempt(0))
  assert admitted.error == NetworkTicketError.None
  let produced = executeTicketProduction(admitted.value)
  assert produced.error == NetworkTicketError.None
  assert array[32, byte](produced.value.identifier) == array[32, byte](fixture.output)
  assert uint32(produced.value.packet.epoch) == 1 and uint8(produced.value.packet.ticket.attempt) == 0
  let checked = verifyNetworkTicket(source.value, produced.value.packet,
      TicketRecipient(local: produced.value.proxy, peer: local, now: StateTime(1),
          connectivityEpoch: 0, delivery: TicketDelivery.Proxy))
  assert checked.error == NetworkTicketError.None
  assert array[32, byte](checked.value.identifier) == array[32, byte](produced.value.identifier)
  let second = captureTicketProduction(source.value, signer.value, local, StateTime(1), 0,
      TicketAttempt(1))
  assert executeTicketProduction(second.value).error == NetworkTicketError.None
  let malformed = captureTicketSigner(newSeq[byte](31))
  assert malformed.error == TicketSignerError.KeyFailure and malformed.keyError ==
      BsError.InvalidLength
  assert captureTicketProduction(source.value, default(TicketSigner), local, StateTime(1), 0,
      TicketAttempt(0)).error == NetworkTicketError.NoSigner
  assert captureTicketProduction(source.value, signer.value, local, StateTime(1), 0, TicketAttempt(
      2)).error == NetworkTicketError.InvalidPacket
  let wrongIdentity = captureTicketProduction(source.value, signer.value, peer, StateTime(1), 0,
      TicketAttempt(0))
  assert executeTicketProduction(wrongIdentity.value).error == NetworkTicketError.WrongRecipient
  let wrongKey = captureTicketSigner(default(array[32, byte]))
  let unrelated = captureTicketProduction(source.value, wrongKey.value, local, StateTime(1), 0,
      TicketAttempt(0))
  assert executeTicketProduction(unrelated.value).error == NetworkTicketError.WrongRecipient
  let expired = captureTicketProduction(source.value, signer.value, local, StateTime(12), 0,
      TicketAttempt(0))
  assert executeTicketProduction(expired.value).error == NetworkTicketError.NoSource
  let includedFixture = ticketFixture(local, peer, useSigner = true, signerMasterSeed = seed,
      included = true)
  let includedSource = captureTicketSource(includedFixture.saved)
  assert includedSource.error == NetworkTicketError.None
  let includedJob = captureTicketProduction(includedSource.value, signer.value, local, StateTime(1),
      0, TicketAttempt(0))
  assert includedJob.error == NetworkTicketError.None
  assert executeTicketProduction(includedJob.value).error == NetworkTicketError.AlreadyIncluded
  let smallEpoch = ticketFixture(local, peer, useSigner = true, signerMasterSeed = seed,
      population = 24)
  let constrained = captureTicketSource(smallEpoch.saved)
  assert constrained.error == NetworkTicketError.None and constrained.value.networkAttempts == 1
  assert captureTicketProduction(constrained.value, signer.value, local, StateTime(1), 0,
      TicketAttempt(1)).error == NetworkTicketError.InvalidPacket
  let single = captureTicketProduction(constrained.value, signer.value, local, StateTime(1), 0,
      TicketAttempt(0))
  assert executeTicketProduction(single.value).error == NetworkTicketError.None
  sourceCycle(fixture.saved)
  let sourceBefore = getOccupiedMem()
  for iteration in 0..<1000: sourceCycle(fixture.saved)
  assert getOccupiedMem() == sourceBefore
  managed(seed)
  actor()
  actor(selfProxy = true)
  actor(absent = true)
  actor(wrong = true)
  actor(rejectAck = true)
  actor(holdFin = true)
  actor(late = true)
  actor(selfProxy = true, late = true, cutoff = true)
  actor(closeDone = true)
  actor(foreignReplacement = true)
  cycle(seed)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(seed)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_ticket_production", 1000, before, after)
  echo "jamnp ticket production: registered signing contracts passed"
try: main()
except: quit 2 # Setup failures never manufacture a signing or lease success.
