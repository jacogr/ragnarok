# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_work_recovery_arc_release"}

## Real managed Services and TLS CE139/140 progression finish original CE133 packages after preferred replies fail.

import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/app/[node as application_node, services, options, work_dispatch]
import ../../../src/app/proof/[worker, work_submission as work_jobs]
import ../../../src/jamnp-s/[work_submission, work_recovery, node as node_streams, work_duty,
    connections, read_stream]
import ../../../src/codec/[bounded, header]
import ../../../src/codec/state/[layout, trie]
import ../../../src/state/store
import ../../../src/codec/state/safrole
import ../../../src/chain/[genesis, provider]
import ../../../src/state/input_refinement
import "../../../src/state/import/inputs" as import_inputs
import ../../support/[jamnp_work_fixture, jamnp_work_recovery_fixture, jamnp_topology_fixture,
  jamnp_node_probe, pvm_input_refinement, jamnp_read_validation_context, arc_evidence]

type Variant {.pure.} = enum ## One exact source and literal script isolate each protocol trust/lifetime boundary.
  Unproven, ProvenRetry, BadProven, InvalidRoot, Reset, Close, ForeignDone, ResetDone, CloseDone

proc publicKey(name: string): StateEdKey {.raises.} =
  ## Only actual native fixture certificate public identities enter the selected canonical roster.
  let raw = readFile(getEnv(name))
  assert raw.len == 32
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(raw[index])
  StateEdKey(key)

proc pump(host: var ApplicationNode, services: var Services, probe: var NodeProbe) {.raises.} =
  ## Ordinary poll-loop turns own all progress; no test-specific protocol dispatcher enters production internals.
  assert host.poll(getMonoTime(), StateTime(20), 0)
  probe.poll()
  services.tick(uint32(host.peerCount))

proc wrapped(fixture: WorkRecoveryFixture): BlockSnapshotResult =
  ## Recapture the same immutable posterior owner; a new header wrapper must not clone or substitute that map.
  var header = newSeq[byte](fixture.snapshot.header.headerInfo.value.consumed)
  assert fixture.snapshot.header.encodeOwnedHeader(header).error == HeaderError.None
  captureBlockSnapshot(header, fixture.snapshot.stateSnapshot, fixture.work.input.parameters)

proc recoveryCycle(fixture: WorkRecoveryFixture, original: WorkImportPlan,
    grant: AuthorizedWorkSubmission, view: ChainView) =
  ## Immutable packet/import progress releases both completed children and rejected raw prefixes on every complete session.
  var progress = beginWorkRecovery(original, view, recoveryPolicy()).value
  let first = fixture.shardReplyWire(0, 0, false)
  let rejected = acceptRecoveryPacket(progress, 0, StateValidatorIndex(0), first)
  assert rejected.error == WorkRecoveryError.InvalidSource
  for item in 0..<2:
    for shard in [0, 2, 3]:
      let info = progress.recoveryInfo.value
      let accepted = acceptRecoveryPacket(progress, info.version, StateValidatorIndex(shard),
          fixture.shardReplyWire(item, shard, false))
      assert accepted.error == WorkRecoveryError.None
      progress = accepted.value
  let completed = completeRecoveredWork(progress, grant, fixture.work.extrinsics,
      fixture.work.limits)
  assert completed.error == WorkRecoveryError.None
  assert completed.value.importInputsInfo.value.entries == 2

proc sourceChecks(fixture: WorkRecoveryFixture) =
  ## Same sealed headers cannot authorize a different posterior map, and no truncated packet may publish a prefix.
  let grant = authorizeWorkSubmission(fixture.recoveryHeader, fixture.snapshot.stateSnapshot,
    fixture.work.input.parameters, fixture.work.limits).value
  let original = prepareWorkImportPlan(grant, fixture.work.limits).value
  let view = genesisView(wrapped(fixture))
  let initial = beginWorkRecovery(original, view, recoveryPolicy()).value
  let packet = fixture.shardReplyWire(0, 0, false)
  for length in 0..<packet.len:
    let refused = acceptRecoveryPacket(initial, initial.recoveryInfo.value.version,
      StateValidatorIndex(0), packet.toOpenArray(0, length-1))
    assert refused.error != WorkRecoveryError.None
  assert initial.recoveryInfo.value.packets == 0
  var entries: seq[StateEntry] = @[]
  let replaced = chapterKey(StateChapter(7))
  for index in 0..<fixture.snapshot.keyCount:
    # Rebuild a complete independent map rather than extending the exact-sized read-only genesis store.
    let key = fixture.snapshot.keyAt(StateKeyIndex(index))
    let value = if array[31, byte](key) == array[31, byte](replaced): @[254'u8]
      else: fixture.snapshot.lookup(key).value.bytes
    entries.add(StateEntry(key: key, value: value))
  var header = newSeq[byte](fixture.snapshot.header.headerInfo.value.consumed)
  assert fixture.snapshot.header.encodeOwnedHeader(header).error == HeaderError.None
  let changed = captureBlockSnapshot(header, entries, fixture.work.input.parameters)
  assert changed.error == GenesisError.None
  assert array[32, byte](changed.value.blockHash) == array[32, byte](fixture.snapshot.blockHash)
  assert beginWorkRecovery(original, genesisView(changed), recoveryPolicy()).error ==
      WorkRecoveryError.InvalidSource
  recoveryCycle(fixture, original, grant, view)
  let before = getOccupiedMem()
  for iteration in 0..<1000: recoveryCycle(fixture, original, grant, view)
  let after = getOccupiedMem()
  assert before == after, "work recovery progress ARC release"
  recordArcRelease("jamnp_work_recovery", 1000, before, after)

proc scenario(variant: Variant) {.raises.} =
  ## Real TLS failure, immutable proof turns and final genuine refinement share the same private source and worker namespace.
  let fixture = workRecoveryFixture(publicKey("RAGNAROK_TEST_PEER_A"), publicKey(
      "RAGNAROK_TEST_PEER_B"),
    invalidRoot = variant == Variant.InvalidRoot)
  writeFile("work-recovery-chain.json", fixture.snapshot.workChainText)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "work-recovery-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "work recovery")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      protocol, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(20)) == NodeError.None
  assert host.configureWork(workDispatchPolicy(fixture.work.limits, executionLimits(),
    WorkDutyLimits(chapterBytes: ByteLimit(10000), disputeItems: ElementLimit(128))))
  assert host.configureWorkAcquisition(workAcquisitionPolicy(1, 1000, ByteLimit(16000000)))
  assert host.configureWorkRecovery(recoveryPolicy())
  assert not host.configureWorkRecovery(recoveryPolicy())
  var preferredPayload = fixture.work.segments
  preferredPayload[0] = preferredPayload[0] xor 1
  var preferredReply = recoveryFrame(preferredPayload)
  for octet in recoveryFrame(fixture.work.proofs): preferredReply.add(octet)
  var requestPayload: seq[byte] = @[]
  let header = fixture.recoveryHeader
  let granted = authorizeWorkSubmission(header, fixture.snapshot.stateSnapshot,
      fixture.work.input.parameters, fixture.work.limits).value
  let plan = prepareWorkImportPlan(granted, fixture.work.limits).value
  requestPayload = plan.workImportRequest.value
  var preferredRequest = @[148'u8]
  for octet in recoveryFrame(requestPayload): preferredRequest.add(octet)
  var script = @[ProbeRead(request: preferredRequest, reply: preferredReply)]
  for item in 0..<2:
    for shard in [0, 2, 3]:
      var reply = fixture.shardReplyWire(item, shard, false)
      if item == 0 and shard == 0 and variant in [Variant.ProvenRetry, Variant.BadProven,
          Variant.InvalidRoot]: reply[4] = reply[4] xor 1
      script.add(ProbeRead(request: fixture.shardRequestWire(item, shard, false), reply: reply,
        holdFin: item == 0 and shard == 0 and variant in [Variant.Reset, Variant.Close,
            Variant.ForeignDone]))
    if item == 0 and variant in [Variant.ProvenRetry, Variant.BadProven, Variant.InvalidRoot]:
      let shards = if variant == Variant.BadProven: @[0, 2, 3, 4] else: @[0, 2, 3]
      for shard in shards:
        var reply = fixture.shardReplyWire(item, shard, true)
        if shard == 0 and variant == Variant.BadProven: reply[reply.high] = reply[reply.high] xor 1
        script.add(ProbeRead(request: fixture.shardRequestWire(item, shard, true), reply: reply))
    if variant in [Variant.Reset, Variant.Close, Variant.ForeignDone, Variant.InvalidRoot]: break
  probe.expectReads(script)
  probe.open(host.localPort, protocol & "/builder")
  let connected = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated or host.peerCount == 0:
    assert getMonoTime() < connected
    pump(host, services, probe)
  let flow = probe.issue(fixture.recoveryWire)
  let deadline = getMonoTime()+initDuration(seconds = 12)
  if variant in [Variant.ResetDone, Variant.CloseDone]:
    while host.workPhase != WorkDispatchPhase.CheckingRecovery:
      assert getMonoTime() < deadline, "recovery packet admission"
      pump(host, services, probe)
    while services.stateProofPhase != ProofWorkerPhase.Done: assert getMonoTime() < deadline
    if variant == Variant.CloseDone:
      host.close()
      assert not services.stateProofActive
    else:
      probe.abort(flow)
      while host.workPhase != WorkDispatchPhase.Idle:
        assert getMonoTime() < deadline
        pump(host, services, probe)
    assert host.acceptedWork == 0
    return
  if variant in [Variant.Reset, Variant.Close, Variant.ForeignDone]:
    while probe.served < 2:
      assert getMonoTime() < deadline, "first actual fallback request"
      pump(host, services, probe)
    assert host.workPhase == WorkDispatchPhase.Recovering and not services.stateProofActive
    if variant == Variant.Close:
      host.close()
    else:
      let other = if variant == Variant.ForeignDone: services.beginNetworkRead(readStateRequest(
          hash)) else: default(NetworkReadStart)
      if variant == Variant.ForeignDone:
        assert other.error == StateProofAdmissionError.None
        while services.stateProofPhase != ProofWorkerPhase.Done: assert getMonoTime() < deadline
      probe.abort(flow)
      while host.workPhase != WorkDispatchPhase.Idle:
        assert getMonoTime() < deadline
        pump(host, services, probe)
      if variant == Variant.ForeignDone:
        assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
        assert services.collectStateProof(other.value).kind ==
            ProofWorkerCompletionKind.ReadCompleted
        assert services.reapWorkSubmission()
    assert host.acceptedWork == 0
    return
  if variant == Variant.InvalidRoot:
    while not probe.flows[flow].reset:
      assert getMonoTime() < deadline, "invalid proven erasure source must reject"
      assert not probe.flows[flow].receivedFin
      pump(host, services, probe)
    assert host.acceptedWork == 0
    return
  while host.workPhase != WorkDispatchPhase.Ready or not probe.flows[flow].receivedFin:
    assert getMonoTime() < deadline, "fallback refinement " & $variant & " actual " &
        $host.workPhase
    pump(host, services, probe)
  assert host.acceptedWork == 1 and not services.stateProofActive
  assert not probe.flows[flow].reset and probe.bytes(flow).len == 0
  block:
    # Source-bearing execution observations retire before any next managed worker admission.
    let token = host.completedWork
    let outcome = services.workSubmissionOutcome(token)
    assert outcome.kind == WorkJobResultKind.Refined
    assert outcome.execution.inputRefinementSource.value.importInputsInfo.value.entries == 2
  assert host.releaseWork()

proc main() {.raises.} =
  ## Each independent native lifetime case closes its exact owner tree before the next one starts.
  let fixture = workRecoveryFixture(publicKey("RAGNAROK_TEST_PEER_A"), publicKey("RAGNAROK_TEST_PEER_B"))
  sourceChecks(fixture)
  for variant in Variant.Unproven..Variant.CloseDone: scenario(variant)
  echo "JAMNP-S managed work recovery passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Setup/transport exceptions cannot substitute for completed real refinement and lifecycle evidence.
