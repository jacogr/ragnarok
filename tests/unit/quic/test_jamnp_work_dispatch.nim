# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ApplicationNode bundle dispatch verifies PVM execution and exact source/worker retirement over authenticated TLS.
import std/[assertions, envvars, syncio, monotimes, times, strutils]
import ../../../src/app/[node as application_node, services, options, work_dispatch, work_policy]
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/jamnp-s/[node as node_streams, connections, work_duty, read_stream]
import ../../../src/codec/bounded
import ../../../src/codec/state/safrole
import ../../../src/chain/[genesis, provider]
import ../../support/[jamnp_work_fixture, jamnp_topology_fixture, jamnp_node_probe,
  jamnp_read_validation_context, pvm_input_refinement]

type Variant {.pure.} = enum ## Each case has a real positive source and changes one host/network boundary.
  Success, Disabled, WrongCore, CorruptProof, WithheldFin, Rotation, Deadline,
    ResetDone, CloseDone, ForeignDone, ForeignClose, ReadyForeign, LowBudget, Package
proc publicKey(): StateEdKey {.raises.} =
  ## Only the server certificate's public identity enters the complete canonical fixture.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  StateEdKey(bytes)
proc frame(payload: openArray[byte]): seq[byte] =
  ## Independent literal E4 encoding avoids the production route encoder.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(payload.len) shr (index*8)) and 255))
  for octet in payload: result.add(octet)
proc wire(f: WorkFixture, variant: Variant): seq[byte] =
  ## Literal messages include original committed inputs and a real imported-segment proof.
  result = @[if variant == Variant.Package: 133'u8 else: 146'u8]
  if variant == Variant.Package:
    var first = @[0'u8, 0]
    for octet in f.package: first.add(octet)
    for octet in frame(first): result.add(octet)
  else:
    var first = f.first
    if variant == Variant.WrongCore: first[0] = 1
    for octet in frame(first): result.add(octet)
    for octet in frame(f.package): result.add(octet)
  for octet in frame(f.extrinsics): result.add(octet)
  if variant != Variant.Package:
    for octet in frame(f.segments): result.add(octet)
    var proofs = f.proofs
    if variant == Variant.CorruptProof: proofs[1] = proofs[1] xor 1
    for octet in frame(proofs): result.add(octet)
proc pump(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    milliseconds = 1, now = StateTime(20), clockOffsetMs = 0) {.raises.} =
  ## Ordinary host polling, not a hand-written work dispatcher, drives every network and CPU transition.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert host.poll(getMonoTime()+initDuration(milliseconds = clockOffsetMs), now, 0)
    probe.poll()
    services.tick(uint32(host.peerCount))
proc waitPhase(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    phase: WorkDispatchPhase) {.raises.} =
  ## Bounded waits observe scalar host state without borrowing any selected graph owner.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while host.workPhase != phase:
    assert getMonoTime() < deadline, "work dispatch phase " & $phase & ", actual " & $host.workPhase
    assert host.poll(getMonoTime(), StateTime(20), 0)
    probe.poll()
    services.tick(uint32(host.peerCount)) # Exactly one host turn keeps transient admitted phases observable without scheduler timing assumptions.
proc waitDone(services: var Services) =
  ## Hold the host at a deterministic uncollected Done boundary; this loop touches only native worker scalar status.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "work dispatch CPU completion"
proc waitReset(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    flow: int, now = StateTime(20), clockOffsetMs = 0) {.raises.} =
  ## A refused stream may never acquire response FIN; actual native reset precedes the verdict.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.flows[flow].reset:
    assert getMonoTime() < deadline, "work dispatch reset"
    assert not probe.flows[flow].receivedFin
    pump(host, services, probe, now = now, clockOffsetMs = clockOffsetMs)
  assert not probe.flows[flow].receivedFin
proc scenario(variant: Variant) {.raises.} =
  ## Every case starts from actual Tiny PVM code, committed imports, a complete source and matching server identity.
  let fixture = workFixture()
  let saved = fixture.workSnapshot(publicKey())
  writeFile("work-dispatch-chain.json", workChainText(saved))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "work-dispatch-chain.json"], settings)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close() # Joined source retirement follows the borrowing host's explicit close.
  assert services.start(settings, "work dispatch"), "Services startup"
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(20)) == NodeError.None
  assert not host.configureWork(default(WorkDispatchPolicy)), "default policy refused"
  let timeout = range[1..120000](if variant == Variant.Deadline: 1000 else: 120000)
  var text = encodeWorkPolicy(fixture.limits, executionLimits(),
    WorkDutyLimits(chapterBytes: ByteLimit(10000), disputeItems: ElementLimit(128)),
        timeoutMs = timeout)
  if variant == Variant.LowBudget:
    assert text.contains("admission.authorization.steps=64\n")
    text = text.replace("admission.authorization.steps=64\n", "admission.authorization.steps=0\n")
  let decoded = decodeWorkPolicy(text)
  assert decoded.error == WorkPolicyError.None
  let policy = decoded.value
  assert policy.valid
  if variant != Variant.Disabled:
    assert host.configureWork(policy)
    assert not host.configureWork(policy) # A live controller's policy cannot be rebound underneath an admitted source.
  probe.open(host.localPort, selectedAlpn & "/builder")
  let connected = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated or host.peerCount == 0:
    assert getMonoTime() < connected
    pump(host, services, probe)
  let flow = probe.issue(wire(fixture, variant), persistent = variant in {
    Variant.WithheldFin, Variant.Rotation, Variant.Deadline, Variant.ForeignDone,
    Variant.ForeignClose})
  if variant in [Variant.Disabled, Variant.WrongCore, Variant.LowBudget, Variant.Package]:
    # Disabled methods, unimplemented availability acquisition and genuine wrong-core duty all refuse without success FIN.
    waitReset(host, services, probe, flow)
    assert host.acceptedWork == 0
    return
  if variant in [Variant.ResetDone, Variant.CloseDone]:
    # Poll exactly until admission, then hold the actual CPU result at uncollected Done.
    waitPhase(host, services, probe, WorkDispatchPhase.Authorizing)
    services.waitDone()
    assert services.rpc.chainPaused
    if variant == Variant.CloseDone:
      host.close()
      assert not services.stateProofActive and not services.rpc.chainPaused
      return
    probe.abort(flow)
    let deadline = getMonoTime()+initDuration(seconds = 8)
    while host.workPhase != WorkDispatchPhase.Idle:
      assert getMonoTime() < deadline
      pump(host, services, probe)
    assert host.acceptedWork == 0 and not services.stateProofActive
    assert not probe.flows[flow].receivedFin
    return
  if variant in [Variant.WithheldFin, Variant.Rotation, Variant.Deadline,
      Variant.ForeignDone, Variant.ForeignClose]:
    # Receiving bodies reserve one session but leave the canonical proof worker available to unrelated work.
    waitPhase(host, services, probe, WorkDispatchPhase.Receiving)
    pump(host, services, probe, 20)
    assert not services.stateProofActive and not probe.flows[flow].receivedFin
    if variant == Variant.Rotation:
      pump(host, services, probe, 5, StateTime(24))
      waitReset(host, services, probe, flow, StateTime(24))
      assert host.acceptedWork == 0
      return
    if variant == Variant.Deadline:
      assert host.poll(getMonoTime()+initDuration(milliseconds = 1001), StateTime(20), 0)
      waitReset(host, services, probe, flow, clockOffsetMs = 1001) # Continue the same monotonic timeline after injection.
      assert host.acceptedWork == 0
      return
    if variant in [Variant.ForeignDone, Variant.ForeignClose]:
      let other = services.beginNetworkRead(readStateRequest(hash))
      assert other.error == StateProofAdmissionError.None
      services.waitDone()
      if variant == Variant.ForeignClose:
        host.close()
        assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
      else:
        probe.abort(flow)
        let deadline = getMonoTime()+initDuration(seconds = 8)
        while host.workPhase != WorkDispatchPhase.Idle:
          assert getMonoTime() < deadline
          pump(host, services, probe)
        assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
      assert services.collectStateProof(other.value).kind == ProofWorkerCompletionKind.ReadCompleted
      assert not services.stateProofActive and not services.rpc.chainPaused
      assert host.acceptedWork == 0
      return
    pump(host, services, probe, 20)
    assert host.workPhase == WorkDispatchPhase.Receiving and not services.stateProofActive
    probe.enable(flow, finish = true)
  if variant == Variant.CorruptProof:
    waitReset(host, services, probe, flow)
    assert host.acceptedWork == 0
    return
  waitPhase(host, services, probe, WorkDispatchPhase.Ready)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.flows[flow].receivedFin:
    assert getMonoTime() < deadline
    pump(host, services, probe)
  assert not probe.flows[flow].reset and probe.bytes(flow).len == 0
  assert host.acceptedWork == 1 and not services.stateProofActive
  let token = host.completedWork
  block:
    # Real completed refinement remains inside Services until downstream processing explicitly releases this generation.
    assert services.workSessionPhase(token) == WorkSessionPhase.Complete
    assert services.workSubmissionOutcome(token).kind == WorkJobResultKind.Refined
  if variant == Variant.ReadyForeign:
    # Releasing a completed source while another worker borrows it must defer private graph destruction until exact collection.
    let other = services.beginNetworkRead(readStateRequest(hash))
    assert other.error == StateProofAdmissionError.None
    services.waitDone()
    assert host.releaseWork() and not host.releaseWork()
    assert services.workSessionPhase(token) == WorkSessionPhase.Retired
    assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
    assert services.collectStateProof(other.value).kind == ProofWorkerCompletionKind.ReadCompleted
    assert services.reapWorkSubmission()
  else:
    assert host.releaseWork() and not host.releaseWork()
  assert services.workSessionPhase(token) == WorkSessionPhase.Empty
  assert host.workPhase == WorkDispatchPhase.Idle
proc main() {.raises.} =
  ## Run live lifecycle witnesses serially so native sockets, workers and bridge libraries never share mutable ownership.
  for variant in Variant.Success..Variant.Package:
    scenario(variant)
  echo "JAMNP-S application work dispatch passed"
try:
  main()
except:
  quit 2 # Setup or execution exceptions cannot substitute for the complete native transcript.
