# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Three ordinary ApplicationNode loops drive CE146 through managed report/signing and independent CE134 receivers to canonical credential collection.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[node as application_node, services, options, startup, work_dispatch,
    work_exchange, work_distribution as distribution_host]
import ../../../src/app/proof/worker
import ../../../src/app/[node_work_policy, work_policy]
import ../../support/jamnp_node_work_policy
import ../../../src/jamnp-s/[node as node_streams, connections, endpoints, work_signer,
  work_sharing, work_duty, work_guarantee, sharing_wire, read_stream, read_client,
  work_distribution as distribution_rules]
import ../../../src/quic/address
import ../../../src/jamnp-s/availability_read
import ../../../src/state/computed/[guarantee, report]
import ../../../src/state/availability/specifier
import ../../support/jamnp_segment_batch_fixture
import ../../../src/codec/[bounded, guarantees, assurances]
import ../../../src/codec/work/package
import ../../../src/codec/state/safrole
import ../../../src/chain/[provider, genesis]
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_managed_work_context, jamnp_read_validation_context, jamnp_topology_fixture,
  jamnp_node_probe, pvm_input_refinement]

type Variant {.pure.} = enum ## The same real builder source proves optional activation, three credentials, bounded third-peer grace and joined cancellation.
  Three, Two, Foreign, CloseDone, ReceiverClose, Refused, Deliver, DeliveryForeign, DeliveryRefresh,
    DeliveryClose, DeliveryRefused, DeliveryConcurrent, DeliveryCloseForeign, Segments, Startup
proc policy(raw: WorkFixture): WorkExchangePolicy =
  ## Every cryptographic/execution/copy ceiling is explicit; only peer response timing differs from the production default.
  let limits = WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes),
    bundleBytes: ByteLimit(MaxBundleBytes), submission: raw.limits, execution: executionLimits(),
    report: workReportLimits(), eligibility: guaranteeLimits(), retention: guarantorLimits())
  workExchangePolicy(limits, ByteLimit(20000), guarantorStorageLimits(), guarantorReadLimits())
proc start(services: var Services, host: var ApplicationNode, certificate,
    privateKey: string) {.raises.} =
  ## Each Services instance decodes independent complete canonical ownership before this host borrows its stable address.
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "work-exchange-chain.json"], settings)
  assert services.start(settings, "exchange runtime")
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let config = initConnectionConfig(certificate, privateKey, services.nodeProtocol, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(20)) == NodeError.None
proc pump(a, b, c: var ApplicationNode, sa, sb, sc: var Services, probe: var NodeProbe,
    clock: MonoTime, now = StateTime(20)) {.raises.} =
  ## The production poll entry owns all admission and collection; the test never calls a worker stage or computes a remote response itself.
  assert a.poll(clock, now, 0), "exchange origin poll"
  assert b.poll(clock, now, 0), "exchange peer B poll"
  assert c.poll(clock, now, 0), "exchange peer C poll"
  probe.poll()
  sa.tick(uint32(a.peerCount))
  sb.tick(uint32(b.peerCount))
  sc.tick(uint32(c.peerCount))
proc packet(fixture: GuaranteeFixture, raw: WorkFixture): seq[byte] =
  ## Literal two-header CE146 plus original bodies uses independent E4 bytes and the genuine anchored package.
  result = @[146'u8]
  for message in [raw.first, fixture.package, raw.extrinsics, raw.segments, raw.proofs]:
    for octet in frame(message): result.add(octet)
proc verify(bytes: seq[byte], count: int) =
  ## Decode the actual runtime output with the independent canonical GP codec and inspect original sorted validator positions.
  let decoded = decodeGuarantee(bytes, GuaranteeConfig(cores: CoreCount(2),
      validators: ValidatorCount(6), maxBytes: ByteLimit(20000)))
  assert decoded.error == GuaranteeError.None and decoded.value.consumed == bytes.len
  let value = decoded.value.value
  assert value.credentialCount == count and uint32(value.slot) == 20
  assert uint16(value.credentials[0].validator) == 1
  assert uint16(value.credentials[1].validator) == 2
  if count == 3: assert uint16(value.credentials[2].validator) == 5
proc peer(host: ApplicationNode, key: StateEdKey): NodePeer =
  ## Compare actual authenticated identities rather than relying on connection arrival order.
  for index in 0..<host.peerCount:
    let found = host.peerAt(index)
    if found.error == NodeError.None:
      if array[32, byte](found.value.identity) == array[32, byte](key): return found.value
  assert false, "missing authenticated distribution peer"
  default(NodePeer)
proc retainedRequests(a, b, c: var ApplicationNode, sa, sb, sc: var Services,
    probe: var NodeProbe, fixture: GuaranteeFixture) {.raises.} =
  ## Actual authenticated CE137/147/148 requests must still succeed after the source's completed signed session is gone.
  assert sa.retainedWorkBundles == 1
  let source = fixture.transcript.computedGuaranteeReport.value.computedReportSource.value
  let policy = guarantorReadLimits()
  let target = peer(b, fixture.local)
  let deadline = getMonoTime()+initDuration(seconds = 15)
  let metadata = source.availabilityInfo.value.specifier
  for coordinate in 0..7:
    # Independent original computation supplies exact shard/bundle wire and actual original-export paths; default fixtures have no export to request.
    if coordinate == 7 and uint16(metadata.segmentCount) == 0: continue
    let kind = if coordinate == 7: ReadKind.Segments elif coordinate ==
        6: ReadKind.Bundle else: ReadKind.Availability
    var payload: seq[byte] = @[]
    if kind == ReadKind.Segments:
      payload = segmentGroup(kind, metadata.segmentRoot.bytes, 0, [0'u16, 0])
    else:
      for octet in metadata.erasureRoot.bytes: payload.add(octet)
      if kind == ReadKind.Availability:
        payload.add(byte(coordinate))
        payload.add(0)
    let request = decodeReadRequest(kind, payload).value
    let expected = if kind == ReadKind.Segments: serveOriginalSegmentBatch(source, request,
        policy) else: serveAvailabilityRead(source, request, policy)
    assert expected.error == ReadError.None
    var ticket = default(NodeRequestTicket)
    while true:
      # Completed/closing streams remain physically charged until native retirement, so bounded progress may be required before the next query.
      let admitted = b.request(target, request, ByteLimit(uint64(expected.value.byteLength)))
      if admitted.error == NodeError.None:
        ticket = admitted.value
        break
      assert admitted.error in [NodeError.Unavailable, NodeError.LimitExceeded]
      assert getMonoTime() < deadline, "retained native request admission"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime())
    while true:
      let reply = b.takeReply(ticket)
      if reply.error == ReadError.None:
        assert reply.value.bytes == expected.value.bytes
        if kind == ReadKind.Segments:
          verifyOriginalSegments(metadata, [0'u16, 0], segmentMessages(reply.value.bytes))
        break
      assert reply.error == ReadError.Unavailable, "retained native reply " & $reply.error
      assert getMonoTime() < deadline, "retained native response FIN"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  assert sa.retainedWorkBundles == 1
proc otherSlot(bytes: seq[byte]): seq[byte] =
  ## The GP signature transcript omits the slot: a second structurally valid current-rotation candidate tests distinct retention capacity.
  let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  var value = decodeGuarantee(bytes, config).value.value
  value.slot = GuaranteeSlot(21)
  encodeGuaranteeValue(value, config).value
proc distributionRequest(a, b, c: var ApplicationNode, sa, sb, sc: var Services,
    probe: var NodeProbe, target: NodePeer, request: ReadRequest, now: StateTime): NodeResult[
        NodeRequestTicket] {.raises.} =
  ## Completed/closing native streams still consume the real two-per-peer quota; bounded polling retires them before another test request is admitted.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while true:
    let admitted = a.request(target, request, ByteLimit(0))
    if admitted.error notin [NodeError.Unavailable, NodeError.LimitExceeded]: return admitted
    assert getMonoTime() < deadline, "distribution request backpressure deadline"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
proc distributionReceipt(a, b, c: var ApplicationNode, sa, sb, sc: var Services,
    probe: var NodeProbe, bytes: seq[byte], keyB, keyC: StateEdKey) {.raises.} =
  ## Ordinary host admission proves default refusal, exclusive worker waiting, exact retention before FIN, duplicate handling and bounded refusal.
  let limits = WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
  let selected = workDistributionPolicy(limits, 1, ByteLimit(20000), deliver = false)
  assert selected.valid
  assert not b.configureWorkDistribution(default(WorkDistributionPolicy))
  assert a.configureWorkDistribution(selected) and b.configureWorkDistribution(selected)
  assert not b.configureWorkDistribution(selected)
  let targetB = a.peer(keyB)
  let targetC = a.peer(keyC)
  let raw = decodeReadRequest(ReadKind.Guarantee, bytes).value
  let second = decodeReadRequest(ReadKind.Guarantee, otherSlot(bytes)).value
  var corrupted = bytes
  corrupted[corrupted.high] = corrupted[corrupted.high] xor 1
  let bad = decodeReadRequest(ReadKind.Guarantee, corrupted).value
  let disabled = distributionRequest(a, b, c, sa, sb, sc, probe, targetC, raw, StateTime(20))
  assert disabled.error == NodeError.None
  let deadline = getMonoTime()+initDuration(seconds = 15)
  block:
    while true:
      assert getMonoTime() < deadline, "default CE135 refusal"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime())
      let reply = a.takeReply(disabled.value)
      if reply.error != ReadError.Unavailable:
        assert reply.error != ReadError.None and c.receivedWorkGuarantees == 0
        break
  let foreign = sb.beginNetworkRead(readStateRequest(sb.chainView.bestBlock.value.blockHash))
  assert foreign.error == StateProofAdmissionError.None
  sb.waitDone()
  let accepted = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, raw, StateTime(20))
  assert accepted.error == NodeError.None
  let heldUntil = getMonoTime()+initDuration(milliseconds = 100)
  while getMonoTime() < heldUntil:
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
    assert sb.stateProofPhase == ProofWorkerPhase.Done and sb.rpc.chainPaused
    assert a.takeReply(accepted.value).error == ReadError.Unavailable
    assert b.pendingWorkGuarantees == 0 and b.receivedWorkGuarantees == 0
  assert sb.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  while not sb.stateProofActive:
    assert getMonoTime() < deadline, "managed CE135 admission"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  sb.waitDone()
  assert b.pendingWorkGuarantees == 0 and b.receivedWorkGuarantees == 0
  assert a.takeReply(accepted.value).error == ReadError.Unavailable
  while true:
    assert getMonoTime() < deadline, "retained CE135 FIN"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
    let reply = a.takeReply(accepted.value)
    if reply.error == ReadError.None:
      assert reply.value.bytes.len == 0
      break
    assert reply.error == ReadError.Unavailable
  assert b.pendingWorkGuarantees == 1 and b.pendingWorkGuaranteeBytes == bytes.len
  assert b.pendingWorkGuarantee(0) == bytes and b.receivedWorkGuarantees == 1
  assert b.cachedReportCount == 1
  for variant in 0..<2:
    # Exact duplicate succeeds without another row; invalid credentials never receive success FIN.
    let request = if variant == 0: raw else: bad
    let sent = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, request, StateTime(20))
    assert sent.error == NodeError.None
    while true:
      assert getMonoTime() < deadline, "CE135 duplicate/refusal"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime())
      let reply = a.takeReply(sent.value)
      if reply.error != ReadError.Unavailable:
        assert (reply.error == ReadError.None) == (variant == 0)
        break
    assert b.receivedWorkGuarantees == 2 and b.pendingWorkGuarantees == 1
    assert b.pendingWorkGuarantee(0) == bytes and sb.stateProofAvailable
  let stale = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, raw, StateTime(20))
  assert stale.error == NodeError.None, "clock-change request admission: " & $stale.error
  while not sb.stateProofActive:
    assert getMonoTime() < deadline, "CE135 clock-change admission"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  sb.waitDone()
  pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
  assert b.receivedWorkGuarantees == 2 and sb.stateProofActive, "new clock must requeue verification before FIN"
  assert a.takeReply(stale.value).error == ReadError.Unavailable
  sb.waitDone() # A fresh observed-slot job must replace the old completed result before acknowledgment.
  while true:
    assert getMonoTime() < deadline, "CE135 fresh-slot acknowledgment"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
    let reply = a.takeReply(stale.value)
    if reply.error == ReadError.None: break
    assert reply.error == ReadError.Unavailable
  assert b.receivedWorkGuarantees == 3 and b.pendingWorkGuarantee(0) == bytes
  let full = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, second, StateTime(21))
  assert full.error == NodeError.None, "full-pool request admission: " & $full.error
  while true:
    # Slot21 is current now: the independently verified managed fixture proves this refusal exercises retention capacity rather than a future credential.
    assert getMonoTime() < deadline, "CE135 full-pool refusal"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
    let reply = a.takeReply(full.value)
    if reply.error != ReadError.Unavailable:
      assert reply.error != ReadError.None, "full pool cannot acknowledge another valid candidate"
      break
  assert b.receivedWorkGuarantees == 3 and b.pendingWorkGuarantee(0) == bytes
  let cancelled = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, raw, StateTime(21))
  assert cancelled.error == NodeError.None, "cancellation request admission: " & $cancelled.error
  while not sb.stateProofActive:
    assert getMonoTime() < deadline, "CE135 cancellation admission"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
  sb.waitDone()
  assert a.cancelRequest(cancelled.value)
  while not sb.stateProofAvailable:
    assert getMonoTime() < deadline, "CE135 exact cancellation collection"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
  # The remote reset may arrive after a valid server acceptance: client cancellation cannot retroactively revoke that earlier acceptance.
  assert b.receivedWorkGuarantees in [3'u64, 4'u64]
  assert not a.requestLive(cancelled.value)
  assert a.takeReply(cancelled.value).error != ReadError.None
  assert b.pendingWorkGuarantees == 1 and b.pendingWorkGuarantee(0) == bytes
  let beforeClose = b.receivedWorkGuarantees
  let closing = distributionRequest(a, b, c, sa, sb, sc, probe, targetB, raw, StateTime(21))
  assert closing.error == NodeError.None, "joined-close request admission: " & $closing.error
  while not sb.stateProofActive:
    assert getMonoTime() < deadline, "CE135 joined-close admission"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), StateTime(21))
  sb.waitDone()
  b.close()
  assert sb.stateProofAvailable and b.pendingWorkGuarantees == 0
  assert b.receivedWorkGuarantees == beforeClose, "locally stopped stream cannot be acknowledged by Done collection"
  let unrelated = sb.beginNetworkRead(readStateRequest(sb.chainView.bestBlock.value.blockHash))
  assert unrelated.error == StateProofAdmissionError.None
  sb.waitDone()
  b.close() # An already retired dispatcher cannot join this foreign completed worker.
  assert sb.stateProofPhase == ProofWorkerPhase.Done and sb.rpc.chainPaused
  assert sb.collectStateProof(unrelated.value).kind == ProofWorkerCompletionKind.ReadCompleted
  let reopened = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"),
      sb.nodeProtocol, streams = 512)
  assert b.open(sb, reopened, topologyLimits(2), StateTime(21)) == NodeError.None
  assert b.configureWorkDistribution(selected)
proc deliveryPolicy(outgoing: bool): WorkDistributionPolicy =
  ## Genuine roster contains three real peers and nine unreachable fixture endpoints; bounded refusals must remain distinct from two remote acknowledgments.
  let limits = WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
  workDistributionPolicy(limits, 4, ByteLimit(80000), timeoutMs = 8000,
      peerTimeoutMs = 500, parallel = 16, deliver = outgoing)
proc deliver(a, b, c: var ApplicationNode, sa, sb, sc: var Services,
    probe: var NodeProbe, variant: Variant, original: seq[byte],
        source: BlockHash, origin: StateEdKey): StateTime {.raises.} =
  ## The ordinary host automatically offers the collected session; tests never supply a recipient list or forge a remote acknowledgment.
  let deadline = getMonoTime()+initDuration(seconds = 15)
  var now = StateTime(20)
  var refreshed = false
  var releasedRefresh = false
  var refreshLease = default(ProofWorkerTicket)
  var incoming = default(NodeResult[NodeRequestTicket])
  if variant == Variant.DeliveryRefresh:
    let admitted = sc.beginNetworkRead(readStateRequest(source))
    assert admitted.error == StateProofAdmissionError.None
    refreshLease = admitted.value
    sc.waitDone() # Keep C's initial request unaccepted while B's acknowledgment becomes known to A.
  if variant == Variant.DeliveryConcurrent:
    let request = decodeReadRequest(ReadKind.Guarantee, original).value
    incoming = distributionRequest(c, a, b, sc, sa, sb, probe, c.peer(origin), request, now)
    assert incoming.error == NodeError.None
  while a.workDeliveryPhase != WorkDeliveryPhase.Sending:
    assert getMonoTime() < deadline, "outgoing qualification phase " & $a.workDeliveryPhase
    if variant == Variant.DeliveryClose and a.workDeliveryPhase == WorkDeliveryPhase.Checking:
      sa.waitDone()
      assert sa.rpc.chainPaused
      a.close()
      assert sa.stateProofAvailable
      return now
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
  assert a.pendingWorkGuarantees == 1 and a.pendingWorkGuarantee(0) == original
  if variant == Variant.DeliveryCloseForeign:
    assert a.workDeliveryAttempts > 0, "foreign close owns queued delivery requests"
    let admitted = sa.beginNetworkRead(readStateRequest(source))
    assert admitted.error == StateProofAdmissionError.None
    sa.waitDone()
    a.close()
    assert sa.stateProofPhase == ProofWorkerPhase.Done and sa.rpc.chainPaused
    assert a.workDeliveryPhase == WorkDeliveryPhase.Idle and a.workDeliveryDemandConnections == 0
    assert sa.collectStateProof(admitted.value).kind == ProofWorkerCompletionKind.ReadCompleted
    assert sa.stateProofAvailable
    return now
  if variant == Variant.DeliveryForeign:
    let foreign = sa.beginNetworkRead(readStateRequest(source))
    assert foreign.error == StateProofAdmissionError.None
    sa.waitDone()
    while b.receivedWorkGuarantees == 0 or c.receivedWorkGuarantees == 0:
      # Already queued source-free sends and complete remote verification progress while this unrelated Done lease remains uncollected.
      assert getMonoTime() < deadline, "delivery peers through foreign lease"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
      assert sa.stateProofPhase == ProofWorkerPhase.Done and sa.rpc.chainPaused
    assert sa.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  while a.workDeliveryRounds == 0:
    assert getMonoTime() < deadline, "bounded outgoing delivery phase " & $a.workDeliveryPhase
    if variant == Variant.DeliveryRefresh and not refreshed and a.workDeliveryAcknowledgments > 0:
      now = StateTime(21)
      refreshed = true # Preserve B's known acknowledgment and original slot/signatures; C has not accepted yet.
    if refreshed and not releasedRefresh and a.workDeliveryPhase == WorkDeliveryPhase.Checking:
      assert sc.stateProofPhase == ProofWorkerPhase.Done and sc.rpc.chainPaused
      assert sc.collectStateProof(refreshLease).kind == ProofWorkerCompletionKind.ReadCompleted
      releasedRefresh = true
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
  assert a.workDeliveryPhase == WorkDeliveryPhase.Idle
  assert a.pendingWorkGuarantees == 1 and a.pendingWorkGuarantee(0) == original
  assert a.workDeliveryRefusals > 0 and a.workDeliveryRounds == 1
  if variant == Variant.DeliveryRefused:
    assert a.workDeliveryAcknowledgments == 0
    assert b.receivedWorkGuarantees == 0 and c.receivedWorkGuarantees == 0
  else:
    assert a.workDeliveryAcknowledgments == 2
    assert b.pendingWorkGuarantee(0) == original and c.pendingWorkGuarantee(0) == original
    assert b.receivedWorkGuarantees == 1 and c.receivedWorkGuarantees == 1
    if variant == Variant.DeliveryRefresh: assert refreshed and releasedRefresh
  if variant == Variant.DeliveryConcurrent:
    while true:
      assert getMonoTime() < deadline, "concurrent incoming/outgoing namespace progress"
      pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
      let reply = c.takeReply(incoming.value)
      if reply.error == ReadError.None:
        assert reply.value.bytes.len == 0 and a.receivedWorkGuarantees == 1
        break
      assert reply.error == ReadError.Unavailable
    assert a.pendingWorkGuarantees == 1 and a.pendingWorkGuarantee(0) == original
  let attempts = a.workDeliveryAttempts
  for turn in 0..<4:
    # A retained Ready primary session is offered exactly once, even after the bounded round finishes with unavailable recipients.
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), now)
  assert a.workDeliveryRounds == 1 and a.workDeliveryAttempts == attempts
  now
proc scenario(variant: Variant, fixture: GuaranteeFixture, keyB, keyC: StateEdKey) {.raises.} =
  ## A fresh trio gives every case independent native sockets, worker namespaces and private signing owners.
  let raw = workFixture(exported = variant == Variant.Segments)
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None
  writeFile("work-exchange-chain.json", workChainText(parent.value))
  var sa, sb, sc = default(Services)
  var a, b, c = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    a.close()
    b.close()
    c.close()
    sa.close()
    sb.close()
    sc.close()
  start(sa, a, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  start(sb, b, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  start(sc, c, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
  let sourceHash = sa.chainView.bestBlock.value.blockHash
  let selected = policy(raw)
  assert selected.valid
  assert not a.configureWorkExchange(default(WorkExchangePolicy), "missing", "missing")
  assert not sa.workSigningConfigured
  if variant == Variant.Startup:
    # The same file loader and activation function used by the foreground command configures all real actors, not a parallel test setup path.
    writeFile("work-exchange.policy", encodeGuarantorPolicy(guarantorSettings()))
    let loaded = loadNodeWorkPolicy("work-exchange.policy")
    assert loaded.error == WorkPolicyError.None and loaded.value.guaranteeing
    let configured = loaded.value
    let setupA = a.configureNodeWork(configured, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
    assert setupA == NodeWorkSetupError.None, "startup a: " & $setupA
    let setupB = b.configureNodeWork(configured, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
    assert setupB == NodeWorkSetupError.None, "startup b: " & $setupB
    let setupC = c.configureNodeWork(configured, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
    assert setupC == NodeWorkSetupError.None, "startup c: " & $setupC
  else:
    assert a.configureWork(workDispatchPolicy(raw.limits, executionLimits(), guaranteeLimits().duty))
    assert a.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
    if variant != Variant.Refused:
      assert b.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
    if variant notin [Variant.Two, Variant.Refused]:
      assert c.configureWorkExchange(selected, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
  assert not a.configureWorkExchange(selected, "missing", "missing")
  if variant in [Variant.Deliver, Variant.DeliveryForeign, Variant.DeliveryRefresh,
      Variant.DeliveryClose, Variant.DeliveryRefused, Variant.DeliveryConcurrent,
      Variant.DeliveryCloseForeign]:
    assert a.configureWorkDistribution(deliveryPolicy(true))
    if variant != Variant.DeliveryRefused:
      assert b.configureWorkDistribution(deliveryPolicy(false))
      assert c.configureWorkDistribution(deliveryPolicy(false))
  assert a.beginPeerConnection(keyB, networkEndpoint(loopbackAddress(false), b.localPort)).error == DialError.None
  assert a.beginPeerConnection(keyC, networkEndpoint(loopbackAddress(false), c.localPort)).error == DialError.None
  probe.open(a.localPort, sa.nodeProtocol & "/builder", "work-exchange-builder/cert.pem", "work-exchange-builder/key.pem")
  let deadline = getMonoTime()+initDuration(seconds = 25)
  while not probe.authenticated or a.peerCount < 3:
    assert getMonoTime() < deadline, "runtime TLS setup"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  let flow = probe.issue(packet(fixture, raw))
  var held = default(ProofWorkerTicket)
  var foreignStarted = false
  var secondAt = default(MonoTime)
  var secondSeen = false
  var retried = false
  var previousPoll = getMonoTime()
  while a.workExchangePhase != WorkExchangePhase.Ready:
    assert getMonoTime() < deadline, "runtime exchange phase " & $a.workExchangePhase
    let clock = getMonoTime()
    if variant == Variant.Refused and a.workExchangePhase == WorkExchangePhase.Idle and
        a.workPhase == WorkDispatchPhase.Idle and a.acceptedWork > 0 and
        (not retried or a.acceptedWork == 2):
      assert sa.stateProofAvailable and not sa.rpc.chainPaused
      if retried:
        assert a.acceptedWork == 2
        return
      assert probe.flows[flow].receivedFin
      discard probe.issue(packet(fixture, raw))
      retried = true
    if variant == Variant.ReceiverClose and sb.stateProofActive:
      sb.waitDone()
      assert sb.rpc.chainPaused
      b.close()
      assert sb.stateProofAvailable
      let reopened = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv(
          "RAGNAROK_TEST_KEY_B"), sb.nodeProtocol, streams = 512)
      assert b.open(sb, reopened, topologyLimits(2), StateTime(20)) == NodeError.None
      assert b.configureWorkExchange(selected, "unused", "unused")
      assert b.workExchangePhase == WorkExchangePhase.Idle
      return
    if variant == Variant.CloseDone and a.workExchangePhase == WorkExchangePhase.Checking:
      let closedToken = a.completedWork
      sa.waitDone()
      assert sa.rpc.chainPaused
      a.close()
      assert sa.stateProofAvailable
      assert sa.workSessionPhase(closedToken) == WorkSessionPhase.Empty
      return
    if a.workPhase == WorkDispatchPhase.Ready:
      let token = a.completedWork
      let info = sa.workExchangeInfo(token)
      if info.credentials == 2 and not secondSeen:
        secondSeen = true
        secondAt = previousPoll # This is the host clock that collected the second credential and started its grace, before observation overhead.
      if variant == Variant.Foreign and not foreignStarted and a.workExchangePhase ==
          WorkExchangePhase.Exchanging and sa.stateProofAvailable:
        let job = sa.beginNetworkRead(readStateRequest(sourceHash))
        assert job.error == StateProofAdmissionError.None
        held = job.value
        foreignStarted = true
        sa.waitDone()
        let peersDone = getMonoTime()+initDuration(seconds = 8)
        while b.receivedWorkContributions == 0 or c.receivedWorkContributions == 0:
          # Both remote computations and native responses finish while this unrelated completed lease remains uncollected.
          assert getMonoTime() < peersDone, "sharing peers progress through foreign lease"
          pump(a, b, c, sa, sb, sc, probe, getMonoTime())
          assert sa.stateProofPhase == ProofWorkerPhase.Done and sa.rpc.chainPaused
        assert sa.workExchangeInfo(token).credentials == 1
        assert sa.collectStateProof(held).kind == ProofWorkerCompletionKind.ReadCompleted
    previousPoll = getMonoTime()
    pump(a, b, c, sa, sb, sc, probe, previousPoll)
  assert probe.flows[flow].receivedFin and not probe.flows[flow].reset
  assert a.collectedWorkGuarantees == 1 and b.receivedWorkContributions == 1
  let token = a.completedWork
  assert sa.workSessionPhase(token) == WorkSessionPhase.Guaranteed
  let count = if variant == Variant.Two: 2 else: 3
  verify(sa.workGuaranteePayload(token), count)
  if variant == Variant.Two:
    assert secondSeen and (getMonoTime()-secondAt).inMilliseconds >= 2000
    assert c.receivedWorkContributions == 0 and not sc.workSigningConfigured
  else:
    assert c.receivedWorkContributions == 1
  if variant == Variant.Foreign: assert foreignStarted
  var retirementSlot = StateTime(20)
  if variant == Variant.Three:
    retirementSlot = StateTime(21)
    distributionReceipt(a, b, c, sa, sb, sc, probe, sa.workGuaranteePayload(token), keyB, keyC)
  if variant in [Variant.Deliver, Variant.DeliveryForeign, Variant.DeliveryRefresh,
      Variant.DeliveryClose, Variant.DeliveryRefused, Variant.DeliveryConcurrent,
      Variant.DeliveryCloseForeign, Variant.Startup]:
    retirementSlot = deliver(a, b, c, sa, sb, sc, probe, variant, sa.workGuaranteePayload(token),
        sourceHash, fixture.local)
    if variant in [Variant.DeliveryClose, Variant.DeliveryCloseForeign]: return
  assert a.releaseWork()
  while a.workExchangePhase != WorkExchangePhase.Idle:
    assert getMonoTime() < deadline, "runtime retirement"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime(), retirementSlot)
  assert sa.workSessionPhase(token) == WorkSessionPhase.Empty
  if variant in [Variant.Two, Variant.Segments]:
    retainedRequests(a, b, c, sa, sb, sc, probe, fixture)
  a.close()
  let reopened = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      sa.nodeProtocol, streams = 512)
  assert a.open(sa, reopened, topologyLimits(2), StateTime(20)) == NodeError.None
  assert a.configureWorkExchange(selected, "unused", "unused")
  assert a.workExchangePhase == WorkExchangePhase.Idle
proc repeatedRuntime(fixture: GuaranteeFixture, keyB, keyC: StateEdKey, remote: int) {.raises.} =
  ## Physical peer discovery must retain all GP indices while issuing zero self requests and one request per distinct remote key.
  let raw = workFixture()
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None
  writeFile("work-exchange-chain.json", workChainText(parent.value))
  var sa, sb, sc = default(Services)
  var a, b, c = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    a.close()
    b.close()
    c.close()
    sa.close()
    sb.close()
    sc.close()
  start(sa, a, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  start(sb, b, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  start(sc, c, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
  let selected = policy(raw)
  assert a.configureWork(workDispatchPolicy(raw.limits, executionLimits(), guaranteeLimits().duty))
  assert a.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  if remote > 0:
    assert b.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  assert a.beginPeerConnection(keyB, networkEndpoint(loopbackAddress(false), b.localPort)).error == DialError.None
  assert a.beginPeerConnection(keyC, networkEndpoint(loopbackAddress(false), c.localPort)).error == DialError.None
  probe.open(a.localPort, sa.nodeProtocol & "/builder", "work-exchange-builder/cert.pem", "work-exchange-builder/key.pem")
  let deadline = getMonoTime()+initDuration(seconds = 25)
  while not probe.authenticated or a.peerCount < 3:
    assert getMonoTime() < deadline, "repeated-key native setup"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  let flow = probe.issue(packet(fixture, raw))
  while a.workExchangePhase != WorkExchangePhase.Ready:
    assert getMonoTime() < deadline, "repeated-key collection phase " & $a.workExchangePhase
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  assert probe.flows[flow].receivedFin and not probe.flows[flow].reset
  let token = a.completedWork
  let info = sa.workExchangeInfo(token)
  assert info.targets == remote and info.credentials == 3, "physical targets and original credential positions are different counts"
  verify(sa.workGuaranteePayload(token), 3)
  assert b.receivedWorkContributions == uint64(remote) and c.receivedWorkContributions == 0, "one actual remote response per distinct key"
  assert not sc.workSigningConfigured
  if remote == 0: assert not sb.workSigningConfigured
  assert a.releaseWork()
  while a.workExchangePhase != WorkExchangePhase.Idle:
    assert getMonoTime() < deadline, "repeated-key retirement"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
proc main() {.raises.} =
  ## Only public identity leaves the temporary signer scopes; private production setup subsequently imports its own independent owner from paths.
  var diagnostic = ""
  assert ensureIdentity("work-exchange-c", diagnostic)
  assert ensureIdentity("work-exchange-builder", diagnostic)
  var keyA, keyB, keyC = default(StateEdKey)
  block:
    let a = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")).value
    let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
    let c = loadWorkSigner("work-exchange-c/cert.pem", "work-exchange-c/key.pem").value
    keyA = a.signerIdentity.value
    keyB = b.signerIdentity.value
    keyC = c.signerIdentity.value
  let fixture = guaranteeFixture(keyA, keyB, keyC)
  for variant in Variant.Three..Variant.DeliveryCloseForeign:
    scenario(variant, fixture, keyB, keyC)
    echo "runtime ", variant, " passed"
  scenario(Variant.Segments, guaranteeFixture(keyA, keyB, keyC, exported = true), keyB, keyC)
  echo "runtime Segments passed"
  scenario(Variant.Startup, fixture, keyB, keyC)
  echo "runtime Startup passed"
  let otherCore = StateValidator(ed25519: keyA)
  repeatedRuntime(guaranteeFixture(keyA, keyA, keyA, otherCore), keyB, keyC, 0)
  echo "runtime AllLocal passed"
  repeatedRuntime(guaranteeFixture(keyA, keyA, keyB, otherCore), keyB, keyC, 1)
  echo "runtime TwoLocal passed"
  repeatedRuntime(guaranteeFixture(keyA, keyB, keyB), keyB, keyC, 1)
  echo "runtime RepeatedPeer passed"
  echo "jamnp work exchange runtime tests passed"
try:
  main()
except:
  quit 2 # Fixture/setup failures cannot substitute for actual peer execution and credential collection.
