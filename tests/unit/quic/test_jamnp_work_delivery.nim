# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A fourth real validator is dialed only from verified metadata; managed acceptance precedes FIN and exact demand ownership retires after delivery.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[services, options, startup, work_distribution as distribution_host]
import ../../../src/app/proof/worker
import ../../../src/jamnp-s/[node, connections, identity, work_signer, work_sharing,
  work_eligibility, sharing_wire, work_stream, read_stream, work_distribution as distribution_rules, report_cache]
import ../../../src/quic/address
import ../../../src/codec/bounded
import ../../../src/codec/work/package
import ../../../src/codec/state/safrole
import ../../../src/chain/[provider, genesis]
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_managed_work_context, jamnp_topology_fixture, jamnp_read_validation_context, pvm_input_refinement]
proc settings(): Options =
  ## Each Services lifetime independently decodes the selected complete file; no canonical map is shared with the structural native role fixture.
  var selected = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "delivery-chain.json"], selected)
  selected
proc startState(services: var Services, name: string) {.raises.} =
  ## Native connectivity uses the explicit trusted finalized selection, independently from the later current-source worker qualification.
  assert services.start(settings(), name), "delivery: services.start(settings(), name)"
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None, "delivery: services.publishFinalized(services.chainView.bestBlock.value.blockHash) =="
proc save(fixture: GuaranteeFixture) {.raises.} =
  ## Fixture authority is explicitly a complete trusted snapshot, never a fabricated block-admission result.
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None, "delivery: parent.error == GenesisError.None"
  writeFile("delivery-chain.json", workChainText(parent.value))
proc sharing(raw: WorkFixture): WorkSharingLimits =
  ## All execution, report and independent bundle-copy bounds are explicit.
  WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes), bundleBytes: ByteLimit(MaxBundleBytes),
    submission: raw.limits, execution: executionLimits(), report: workReportLimits(),
        eligibility: guaranteeLimits())
proc policy(outgoing: bool): WorkDistributionPolicy =
  ## Finish before the nonpreferred topology fallback; the positive real connection must therefore come from this delivery's exact demand dial.
  let limits = WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
  workDistributionPolicy(limits, 4, ByteLimit(80000), timeoutMs = 3000, peerTimeoutMs = 2000,
      parallel = 1, deliver = outgoing)
proc recipient(local, b, c: StateEdKey, prefix = "delivery-recipient-"): tuple[key: StateEdKey,
    directory: string] {.raises.} =
  ## Select a real public identity for which the sender is not the preferred topology initiator; finite generation cannot turn into an unbounded setup loop.
  for attempt in 0..<128:
    let directory = prefix & $attempt
    var diagnostic = ""
    assert ensureIdentity(directory, diagnostic), "delivery: ensureIdentity(directory, diagnostic)"
    let key = loadWorkSigner(directory & "/cert.pem", directory &
        "/key.pem").value.signerIdentity.value
    let unique = array[32, byte](key) != array[32, byte](local) and array[32, byte](key) != array[
        32, byte](b) and array[32, byte](key) != array[32, byte](c)
    if unique and not preferredInitiator(local, key): return (key, directory)
  assert false, "bounded nonpreferred recipient generation"
  (default(StateEdKey), "")
proc guaranteed(services: var Services, fixture: GuaranteeFixture, b,
    c: WorkSigner): WorkSessionToken {.raises.} =
  ## Real TLS header, managed execution/signing and independently recomputed peer signatures yield the original retained primary guarantee.
  let raw = workFixture()
  assert services.configureWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      fixture.local).error == WorkSigningSetupError.None, "delivery: services.configureWorkSigner(getEnv('RAGNAROK_TEST_CERT'), getEnv('RAGNAROK_TEST_KEY'),"
  let header = services.networkHeader(fixture, raw, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  let token = services.reportSession(fixture, raw, header)
  let eligibility = guaranteeLimits()
  let admitted = services.beginWorkContribution(token, fixture.local, StateTime(20), eligibility)
  assert admitted.error == StateProofAdmissionError.None, "delivery: admitted.error == StateProofAdmissionError.None"
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Contributed, "delivery: services.collectWorkSubmission(token) == WorkSessionPhase.Contributed"
  assert services.beginWorkExchange(token, ByteLimit(20000)).error == StateProofAdmissionError.None, "delivery: services.beginWorkExchange(token, ByteLimit(20000)).error == StateProofAdmissionError.None"
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions, "delivery: services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions"
  let request = services.workSharingRequest(token)
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  let view = genesisView(parent)
  for index in 0..<2:
    # Peer computation happens only in test setup; the production sender still verifies each exact response under its managed worker lease.
    let signer = if index == 0: b else: c
    let key = signer.signerIdentity.value
    let response = receiveSharedWork(request, view, key, fixture.local, StateTime(20), signer,
        sharing(raw))
    assert response.error == WorkSharingError.None, "delivery: response.error == WorkSharingError.None"
    assert services.beginWorkPeerResponse(token, index, key,
        response.value.sharingResponse.value).error == StateProofAdmissionError.None, "delivery: services.beginWorkPeerResponse(token, index, key,"
    services.waitDone()
    assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions, "delivery: services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions"
  assert services.beginWorkGuaranteeCollection(token, ByteLimit(20000)).error ==
      StateProofAdmissionError.None, "delivery: services.beginWorkGuaranteeCollection(token, ByteLimit(20000)).error =="
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Guaranteed, "delivery: services.collectWorkSubmission(token) == WorkSessionPhase.Guaranteed"
  token
type DeliveryCase {.pure.} = enum ## Real connections cover successful receipt, held CPU authority and a busy acknowledged connection at its concurrency ceiling.
  Deliver, ReceiverHeld, BusyAfterAck
proc headHash(services: Services): BlockHash =
  ## Retire all temporary canonical aliases before another closed proof job is admitted.
  services.chainView.bestBlock.value.blockHash
proc scenario(aKey: StateEdKey, b, c: WorkSigner,
    target: tuple[key: StateEdKey, directory: string], mode: DeliveryCase) {.raises.} =
  ## Keep the recipient's actual socket bound while rebuilding anchored inputs with its real metadata; never guess or release a port for later reuse.
  var metadata = default(array[128, byte])
  metadata[15] = 1
  metadata[16] = 55
  var record = StateValidator(ed25519: target.key, metadata: StateValidatorMetadata(metadata))
  var extra = default(StateValidator)
  if mode == DeliveryCase.BusyAfterAck:
    let selected = recipient(aKey, b.signerIdentity.value, c.signerIdentity.value, "delivery-extra-")
    assert array[32, byte](selected.key) != array[32, byte](target.key), "distinct busy-case recipient"
    extra = StateValidator(ed25519: selected.key, metadata: StateValidatorMetadata(metadata))
  let seed = guaranteeFixture(aKey, b.signerIdentity.value, c.signerIdentity.value, record, extra)
  save(seed)
  var sourceServices, targetServices = default(Services)
  var sourceNode, targetNode = default(NodeService)
  var sender, receiver = default(WorkDistributionDispatcher)
  var sourceReports, targetReports = default(ReportCache)
  defer:
    sender.close(sourceServices, sourceNode)
    receiver.close(targetServices, targetNode)
    sourceNode.close()
    targetNode.close()
    sourceServices.close()
    targetServices.close()
  startState(targetServices, "recipient socket setup")
  let domain = targetServices.nodeProtocol
  let targetConfig = initConnectionConfig(target.directory & "/cert.pem", target.directory &
      "/key.pem", domain, binding = loopbackAddress(true), streams = 512)
  assert targetNode.open(targetConfig, targetServices.chainView, topologyLimits(2)) ==
      NodeError.None, "actual IPv6 listener"
  metadata[16] = byte(targetNode.localPort and 255)
  metadata[17] = byte(targetNode.localPort shr 8)
  record.metadata = StateValidatorMetadata(metadata)
  let fixture = guaranteeFixture(aKey, b.signerIdentity.value, c.signerIdentity.value, record, extra)
  save(fixture)
  targetServices.close() # Native role data is independent; no controller/Services borrow has been installed yet.
  startState(targetServices, "actual recipient source")
  assert targetServices.nodeProtocol == domain and not targetServices.workSigningConfigured, "stable domain and unsigned receiver"
  startState(sourceServices, "actual delivery source")
  let session = guaranteed(sourceServices, fixture, b, c)
  let original = sourceServices.workGuaranteePayload(session)
  let limits = WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
  let raw = decodeReadRequest(ReadKind.Guarantee, original).value
  let admission = targetServices.beginWorkDistribution(raw, StateTime(20), limits)
  assert admission.error == StateProofAdmissionError.None, "receiver control admission"
  targetServices.waitDone()
  let control = targetServices.collectWorkDistribution(admission.value)
  assert control.kind == WorkDistributionCompletionKind.Completed, "receiver source control"
  let sourceConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      domain, streams = 512)
  assert sourceNode.open(sourceConfig, sourceServices.chainView, topologyLimits(2)) ==
      NodeError.None, "delivery sender listener"
  assert not preferredInitiator(aKey, target.key), "actual dial precedes topology fallback"
  assert sender.configure(sourceNode, policy(true)) and receiver.configure(targetNode, policy(
      false)), "explicit managed controllers"
  assert sourceNode.peerForIdentity(target.key).error == NodeError.Unavailable
  assert sender.beginLocal(sourceServices, session, getMonoTime())
  var foreign = default(ProofWorkerTicket)
  var held = mode != DeliveryCase.Deliver
  if held:
    let admitted = targetServices.beginNetworkRead(readStateRequest(targetServices.headHash))
    assert admitted.error == StateProofAdmissionError.None
    foreign = admitted.value
    targetServices.waitDone()
  var reverse = default(NodeRequestTicket)
  var claimed = default(NodeReadTicket)
  var queuedReverse, claimedReverse, sawPeer, busyAfterAck = false
  let ordinary = decodeReadRequest(ReadKind.Report, default(array[32, byte])).value
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while sender.rounds == 0 or targetNode.peerCount != 0:
    # Both ordinary controllers drive real streams and exact worker collection; a held reverse read must remain charged to the dial owner.
    assert getMonoTime() < deadline, "owned demand delivery/cleanup"
    let clock = getMonoTime()
    sender.beforePoll(sourceServices, sourceNode, StateTime(20))
    receiver.beforePoll(targetServices, targetNode, StateTime(20))
    assert sourceNode.poll(clock, 0) and targetNode.poll(clock, 0), "native delivery poll"
    if targetNode.peerCount > 0: sawPeer = true
    if mode == DeliveryCase.BusyAfterAck:
      if not queuedReverse:
        let peer = targetNode.peerForIdentity(aKey)
        if peer.error == NodeError.None:
          let started = targetNode.request(peer.value, ordinary, ByteLimit(512))
          if started.error == NodeError.None:
            reverse = started.value
            queuedReverse = true
          else:
            assert started.error in [NodeError.Unavailable, NodeError.LimitExceeded], "bounded reverse-read backpressure"
      elif not claimedReverse:
        let task = sourceNode.takeRead(ReadKind.Report)
        if task.error == NodeError.None:
          claimed = task.value.ticket
          claimedReverse = true
          assert sourceNode.peerBusy(target.key)
          assert targetServices.collectStateProof(foreign).kind ==
              ProofWorkerCompletionKind.ReadCompleted
          held = false # The guarantee can now be accepted, but the reverse ordinary read stays deliberately unanswered.
    sender.poll(sourceServices, sourceNode, sourceReports, clock, StateTime(20))
    receiver.poll(targetServices, targetNode, targetReports, clock, StateTime(20))
    if sourceServices.stateProofAvailable: discard sender.submit(sourceServices, sourceNode, clock,
        StateTime(20))
    if targetServices.stateProofAvailable: discard receiver.submit(targetServices, targetNode,
        clock, StateTime(20))
    assert sender.demandConnections <= 1, "owned demand concurrency cap includes busy/closing connections: " &
        $sender.demandConnections
    if mode == DeliveryCase.BusyAfterAck and sender.acknowledged == 1 and sourceNode.readLive(claimed):
      busyAfterAck = true
      assert sender.demandConnections == 1, "acknowledged busy dial remains charged"
    if held: assert targetServices.stateProofPhase == ProofWorkerPhase.Done and
        targetServices.rpc.chainPaused
  let expected = if mode == DeliveryCase.ReceiverHeld: 0'u64 else: 1'u64
  assert sender.rounds == 1 and sender.acknowledged == expected and sender.attempted == 1,
      "actual delivery outcome: " & $sender.rounds & "/" & $sender.acknowledged & "/" &
          $sender.attempted & "/" & $sawPeer
  assert sawPeer and sender.demandConnections == 0 and sender.deliveryPhase ==
      WorkDeliveryPhase.Idle
  assert sender.pendingPayload(0) == original
  assert sourceNode.peerForIdentity(target.key).error == NodeError.Unavailable
  assert not sender.beginLocal(sourceServices, session, getMonoTime())
  if mode == DeliveryCase.ReceiverHeld:
    assert receiver.received == 0 and receiver.pendingCount == 0
    receiver.close(targetServices, targetNode)
    assert targetServices.stateProofPhase == ProofWorkerPhase.Done and
        targetServices.rpc.chainPaused
    assert targetServices.collectStateProof(foreign).kind == ProofWorkerCompletionKind.ReadCompleted
  else:
    assert receiver.received == 1 and receiver.pendingPayload(0) == original and
        targetReports.len == 1
    if mode == DeliveryCase.BusyAfterAck:
      assert queuedReverse and claimedReverse and busyAfterAck, "busy acknowledged connection witness"
      assert not sourceNode.readLive(claimed), "overall deadline retires the held reverse read"
      assert targetNode.takeReply(reverse).error != ReadError.None, "unanswered reverse request has no successful completion"
proc main() {.raises.} =
  ## Maintained keys and finite recipient selection give each scenario genuine identities and independently prepared complete sources.
  let aKey = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv(
      "RAGNAROK_TEST_KEY")).value.signerIdentity.value
  let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
  var diagnostic = ""
  assert ensureIdentity("delivery-third", diagnostic)
  let c = loadWorkSigner("delivery-third/cert.pem", "delivery-third/key.pem").value
  let target = recipient(aKey, b.signerIdentity.value, c.signerIdentity.value)
  for mode in DeliveryCase.Deliver..DeliveryCase.BusyAfterAck:
    scenario(aKey, b, c, target, mode)
    echo "metadata ", mode, " passed"
  echo "JAMNP-S verified metadata delivery and owned dial cleanup passed"
try:
  main()
except:
  quit 2 # Setup or native failures cannot substitute for genuine credential verification, acknowledgment or exact ownership cleanup.
