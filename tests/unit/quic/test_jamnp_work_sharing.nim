# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_work_sharing_arc_release"}

## Actual CE134 TLS/FIN, independent Services worker leases and genuine same-input signatures preserve waiting builder contexts.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, work_submission as jobs]
import ../../../src/jamnp-s/[node, connections, sharing_wire, work_sharing, work_signer,
  work_submission, read_stream, availability_read, availability_merkle]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/bounded
import ../../../src/codec/work/package
import ../../../src/codec/state/safrole
import ../../../src/state/computed/guarantee
import ../../../src/state/computed/report
import ../../../src/crypto/primitives
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_topology_fixture, jamnp_node_probe, pvm_input_refinement, arc_evidence]

type Variant {.pure.} = enum ## Each case changes one real wire, assignment, worker or lifecycle obligation.
  Success, Disabled, UnknownPeer, WithheldFin, Suffix, Truncated, InvalidShards,
    WrongCore, InvalidMappings, CorruptProof, CancelDone, RetirePrimary
proc limits(): WorkSharingLimits =
  ## Local policy is explicit; consensus gas/profile remains derived from the actual canonical source.
  let raw = workFixture()
  WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes), bundleBytes: ByteLimit(MaxBundleBytes),
    submission: raw.limits, execution: executionLimits(), report: workReportLimits(),
        eligibility: guaranteeLimits(), retention: guarantorLimits())
proc frame(bytes: openArray[byte]): seq[byte] =
  ## Independent literal E4 framing detects wrong message grouping and response shape.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(bytes.len) shr (8*index)) and 255))
  for octet in bytes: result.add(octet)
proc first(raw: WorkFixture, variant: Variant): seq[byte] =
  ## CE134 inserts E2 shards between core and mappings; this is not the CE146 first message.
  result = @[byte(if variant == Variant.WrongCore: 1 else: 0), 0, byte(if variant ==
      Variant.InvalidShards: 9 else: 6), 0]
  if variant == Variant.InvalidMappings:
    result.add(9) # Nine mappings refuse before any refinement or signature.
  else:
    for index in 2..<raw.first.len: result.add(raw.first[index])
proc bundle(fixture: GuaranteeFixture, raw: WorkFixture, corrupt = false): seq[byte] =
  ## Whole bundle includes exact original package, extrinsics, imported segments and canonical justifications.
  result = @[]
  for octet in fixture.package: result.add(octet)
  for octet in raw.extrinsics: result.add(octet)
  for octet in raw.segments: result.add(octet)
  var proofs = raw.proofs
  if corrupt: proofs[1] = proofs[1] xor 1
  for octet in proofs: result.add(octet)
proc pump(server: var NodeService, probe: var NodeProbe, milliseconds = 1) =
  ## Native callbacks process bounded raw bytes while all canonical/private-key aliases remain exclusively worker-owned.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert server.poll(getMonoTime(), 0)
    probe.poll()
proc waitDone(services: var Services, server: var NodeService, probe: var NodeProbe) =
  ## Observe only synchronized scalar phase until exact collection; native transport stays live throughout.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "sharing CPU deadline"
    pump(server, probe)
proc waitTask(server: var NodeService, probe: var NodeProbe): NodeSharingTask =
  ## Only two complete messages and exact request FIN create an authenticated native task.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while true:
    let task = server.takeSharingRequest()
    if task.error == NodeError.None: return task.value
    assert getMonoTime() < deadline, "sharing request deadline"
    pump(server, probe)
proc waitReset(server: var NodeService, probe: var NodeProbe, flow: int) =
  ## Refusals cannot masquerade as successful response FIN or return any hash/signature prefix.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.flows[flow].reset and not probe.flows[flow].closed:
    assert getMonoTime() < deadline, "sharing reset deadline"
    pump(server, probe)
  assert not probe.flows[flow].receivedFin
  assert probe.bytes(flow).len == 0
proc live(variant: Variant, local, remoteKey: StateEdKey) {.raises.} =
  ## Real TLS packets reach the actual private Services signer through its separate managed sharing namespace.
  let fixture = guaranteeFixture(local, if variant == Variant.UnknownPeer: default(
      StateEdKey) else: remoteKey)
  let raw = workFixture()
  let head = fixture.view.bestBlock.value
  let parent = fixture.view.parentOf(head.blockHash)
  assert parent.error == GenesisError.None
  writeFile("work-sharing-chain.json", workChainText(parent.value))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "work-sharing-chain.json"], settings)
  var services = default(Services)
  var server = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    services.close() # Join private source/key users before any enclosing retained transport context retires.
    probe.close()
    server.close()
  assert services.start(settings, "work sharing")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      protocol, streams = 512)
  assert server.open(config, services.chainView, topologyLimits(2)) == NodeError.None
  let configured = services.configureWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv(
      "RAGNAROK_TEST_KEY"), server.localIdentity, guarantorStorageLimits())
  assert configured.error == WorkSigningSetupError.None
  if variant != Variant.Disabled: assert server.enableSharingStreams()
  # A real primary builder authorization remains retained while sharing uses the otherwise idle CPU.
  let primary = services.beginWorkSubmission(fixture.original, raw.limits, executionLimits())
  assert primary.error == StateProofAdmissionError.None
  let primaryToken = primary.value
  probe.open(server.localPort, protocol)
  let connected = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated or server.peerCount == 0:
    assert getMonoTime() < connected, "sharing validator TLS admission"
    pump(server, probe)
  services.waitDone(server, probe)
  var packet = @[134'u8]
  for octet in frame(first(raw, variant)): packet.add(octet)
  for octet in frame(bundle(fixture, raw, variant == Variant.CorruptProof)): packet.add(octet)
  if variant == Variant.Suffix: packet.add(0)
  if variant == Variant.Truncated: packet.setLen(packet.len-1)
  let flow = probe.issue(packet, persistent = variant == Variant.WithheldFin)
  if variant in [Variant.Disabled, Variant.UnknownPeer, Variant.Suffix, Variant.Truncated]:
    # Incomplete/unauthorized requests never reach the private key or semantic worker.
    waitReset(server, probe, flow)
    assert server.takeSharingRequest().error == NodeError.Unavailable
    assert services.collectWorkSubmission(primaryToken) == WorkSessionPhase.Authorized
    assert services.retireWorkSubmission(primaryToken)
    return
  if variant == Variant.WithheldFin:
    pump(server, probe, 30)
    assert server.takeSharingRequest().error == NodeError.Unavailable
    probe.enable(flow, finish = true)
  var ticket = default(NodeSharingTicket)
  var admitted = default(WorkSharingStart)
  block:
    # Destruction of this native task after submission cannot race the independently copied CPU input's ARC counters.
    let task = waitTask(server, probe)
    ticket = task.ticket
    let actualPeer: StateEdKey = task.peerIdentity
    let actualBytes = array[32, byte](actualPeer)
    let expectedBytes = array[32, byte](remoteKey)
    assert actualBytes == expectedBytes
    let busy = services.beginWorkSharing(task.request, server.localIdentity, task.peerIdentity,
        StateTime(20), limits())
    assert busy.error == StateProofAdmissionError.Busy # Primary Done still reserves its exact slot.
    assert services.collectWorkSharing(default(WorkSharingToken)).kind ==
        WorkSharingCompletionKind.Uninitialized
    assert services.collectWorkSubmission(primaryToken) == WorkSessionPhase.Authorized
    admitted = services.beginWorkSharing(task.request, server.localIdentity, task.peerIdentity,
        StateTime(20), limits())
    assert admitted.error == StateProofAdmissionError.None
  let token = admitted.value
  assert services.collectWorkSubmission(primaryToken) == WorkSessionPhase.Authorized
  if variant == Variant.RetirePrimary: assert services.retireWorkSubmission(primaryToken)
  services.waitDone(server, probe)
  assert not services.stateProofAvailable
  assert services.collectWorkSharing(default(WorkSharingToken)).kind ==
      WorkSharingCompletionKind.Uninitialized
  if variant == Variant.CancelDone:
    assert services.cancelWorkSharing(token)
  let completed = services.collectWorkSharing(token)
  if variant == Variant.CancelDone:
    assert completed.kind == WorkSharingCompletionKind.Cancelled
    discard server.rejectSharing(ticket)
    waitReset(server, probe, flow)
    return
  if variant in [Variant.InvalidShards, Variant.WrongCore, Variant.InvalidMappings,
      Variant.CorruptProof]:
    assert completed.kind == WorkSharingCompletionKind.Refused
    let refused = completed.sharingError
    case variant
    of Variant.InvalidShards: assert refused.error == WorkSharingError.InvalidShards
    of Variant.WrongCore:
      assert refused.error == WorkSharingError.DutyFailure
      assert refused.side == SharingDutySide.Peer
    of Variant.InvalidMappings: assert refused.error == WorkSharingError.HeaderFailure
    else: assert refused.error == WorkSharingError.BodyFailure # A changed proof cannot reach refinement/signing.
    discard server.rejectSharing(ticket)
    waitReset(server, probe, flow)
    return
  assert completed.kind == WorkSharingCompletionKind.Completed
  let response = completed.response
  let expected = array[45, byte](fixture.transcript.computedGuaranteeMessage.value)
  var signature = default(array[64, byte])
  for index in 0..<32: assert response[index] == expected[13+index]
  for index in 0..<64: signature[index] = response[32+index]
  assert verify(EdPublicKey(array[32, byte](local)), EdSignature(signature), expected)
  assert server.respondSharing(ticket, response) == ReadError.None
  let duplicate = server.respondSharing(ticket, response)
  assert duplicate == ReadError.InvalidStream
  let finished = getMonoTime()+initDuration(seconds = 8)
  while not probe.flows[flow].receivedFin:
    assert getMonoTime() < finished, "sharing response FIN"
    pump(server, probe)
  assert probe.bytes(flow) == frame(response)
  if variant == Variant.RetirePrimary:
    assert services.reapWorkSubmission()
  else:
    # The incoming contribution did not overwrite or retire the primary builder's actual context.
    assert services.workSessionPhase(primaryToken) == WorkSessionPhase.Authorized
    let body = services.beginWorkBundle(primaryToken, raw.extrinsics, raw.segments, raw.proofs)
    assert body.error == StateProofAdmissionError.None
    services.waitDone(server, probe)
    assert services.collectWorkSubmission(primaryToken) == WorkSessionPhase.Complete
    assert services.workSubmissionOutcome(primaryToken).kind == WorkJobResultKind.Refined
    assert services.retireWorkSubmission(primaryToken)
  # Receiving a share retains its original bundle independently of the retired primary session.
  let readPolicy = AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(
      64000000),
    hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)), wireBytes: ByteLimit(16000000))
  assert services.configureAvailabilityReads(readPolicy)
  let reportInfo = fixture.transcript.computedGuaranteeReport.value.computedReportInfo.value
  let request = decodeReadRequest(ReadKind.Bundle, reportInfo.header.erasureRoot.bytes).value
  let reading = services.beginNetworkRead(request)
  assert reading.error == StateProofAdmissionError.None
  services.waitDone(server, probe)
  let reply = services.collectStateProof(reading.value)
  assert reply.kind == ProofWorkerCompletionKind.ReadCompleted
  assert reply.readValue.error == ReadError.None
  assert reply.readValue.value.bytes == frame(bundle(fixture, raw))
proc cycle(request: SharedWorkRequest, fixture: GuaranteeFixture, peer: StateEdKey,
    signer: WorkSigner, bad: bool) =
  ## Full receive/refine/report/sign success and early proof refusal release every decoded/executed temporary owner.
  let received = receiveSharedWork(request, fixture.view, fixture.local, peer, StateTime(21),
      signer, limits())
  if bad:
    assert received.error == WorkSharingError.BodyFailure
  else:
    assert received.error == WorkSharingError.None, "sharing computation: " & $received.error
    let encoded = received.value.sharingResponse
    assert encoded.error == WorkSharingError.None
proc main() {.raises.} =
  ## Real fixture keys and original PVM sources remain untouched while any actual worker owns their aliases.
  let signer = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  let other = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  assert signer.error == WorkSignerError.None and other.error == WorkSignerError.None
  let local = signer.value.signerIdentity.value
  let peer = other.value.signerIdentity.value
  for variant in low(Variant)..high(Variant): live(variant, local, peer)
  let fixture = guaranteeFixture(local, peer)
  let raw = workFixture()
  let good = captureSharedWork(first(raw, Variant.Success), bundle(fixture, raw)).value
  let bad = captureSharedWork(first(raw, Variant.Success), bundle(fixture, raw, true)).value
  cycle(good, fixture, peer, signer.value, false)
  cycle(bad, fixture, peer, signer.value, true)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    if iteration mod 2 == 0: cycle(good, fixture, peer, signer.value, false)
    else: cycle(bad, fixture, peer, signer.value, true)
  let after = getOccupiedMem()
  assert before == after, "whole-bundle sharing releases computation and failure prefixes"
  recordArcRelease("jamnp_work_sharing", 1000, before, after)
  echo "JAMNP-S same-core work sharing passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Setup/transport exceptions cannot stand in for a genuine signed response or source-lifetime verdict.
