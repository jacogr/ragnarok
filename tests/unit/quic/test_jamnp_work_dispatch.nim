# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ApplicationNode bundle dispatch verifies PVM execution and exact source/worker retirement over authenticated TLS.
import std/[assertions, envvars, syncio, monotimes, times, strutils]
import ../../../src/app/[node as application_node, services, options, work_dispatch, work_policy]
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/jamnp-s/[node as node_streams, connections, work_duty, work_report, read_stream,
    availability_read, availability_proof, availability_store]
import ../../../src/codec/bounded
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/layout
import ../../../src/state/bundle_erasure
import ../../../src/state/auditable_bundle
import "../../../src/state/export/erasure" as export_erasure
import ../../../src/state/computed/[report as computed_report, guarantee]
import ../../../src/crypto/primitives
import ../../../src/codec/state/safrole
import ../../../src/chain/[genesis, provider]
import ../../support/[jamnp_work_fixture, jamnp_topology_fixture, jamnp_node_probe,
  jamnp_read_validation_context, pvm_input_refinement, jamnp_work_report_fixture,
  jamnp_segment_batch_fixture, pvm_import_vectors]

type Variant {.pure.} = enum ## Each case has a real positive source and changes one host/network boundary.
  Success, Disabled, WrongCore, CorruptProof, WithheldFin, Rotation, Deadline,
    ResetDone, CloseDone, ForeignDone, ForeignClose, ReadyForeign, LowBudget, Report, ReportFailure,
      ReportCancelDone, ReportCloseDone, ReportStaleTime, ReportForeignDone, Package, Availability,
        AvailabilityDisabled, AvailabilityLimit,
      AvailabilityResetDone, AvailabilityCloseDone, AvailabilityRetireDone, AvailabilityWrongRoot,
        AvailabilityBadIndex, AvailabilityTruncated, AssurerAudit, AssurerResetDone,
          AssurerCloseDone, AssurerMissing, Batch, BatchResetDone, BatchCloseDone, BatchForeignDone,
            BatchUnknownRoot, BatchTruncated, BatchOverCount, PackageFetch, PackageEmpty,
              PackageBadProof, PackageReadLimit, PackageTimeout, PackageReset, PackageClose,
                PackageForeign, PackageGridRead
proc publicKey(name = "RAGNAROK_TEST_PEER_A"): StateEdKey {.raises.} =
  ## Only the server certificate's public identity enters the complete canonical fixture.
  let raw = readFile(getEnv(name))
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
  result = @[if variant == Variant.Package or variant in
      Variant.PackageFetch..Variant.PackageGridRead: 133'u8 else: 146'u8]
  if variant == Variant.Package or variant in Variant.PackageFetch..Variant.PackageGridRead:
    var first = @[0'u8, 0]
    for octet in f.package: first.add(octet)
    for octet in frame(first): result.add(octet)
  else:
    var first = f.first
    if variant == Variant.WrongCore: first[0] = 1
    for octet in frame(first): result.add(octet)
    for octet in frame(f.package): result.add(octet)
  for octet in frame(f.extrinsics): result.add(octet)
  if variant != Variant.Package and variant notin Variant.PackageFetch..Variant.PackageGridRead:
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
    phase: WorkDispatchPhase, label = "") {.raises.} =
  ## Bounded waits observe scalar host state without borrowing any selected graph owner.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while host.workPhase != phase:
    assert getMonoTime() < deadline, "work dispatch phase " & $phase & ", actual " &
        $host.workPhase & " case " & label
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
proc availabilityLimits(): AvailabilityReadLimits =
  ## Explicit separate serving policy has no implied relationship to authorization/refinement ceilings.
  AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(64000000),
    hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)), wireBytes: ByteLimit(16000000))
proc originalBundle(services: Services, token: WorkSessionToken): seq[byte] =
  ## Return only copied original bytes; every source-bearing alias retires before network CPU admission.
  let report = services.workSubmissionOutcome(token).reportTranscript.computedGuaranteeReport.value
  report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleBytes.value
proc responseMessages(wire: seq[byte]): seq[seq[byte]] =
  ## Independent literal E4 parsing checks complete response framing before cryptographic verification.
  result = @[]
  var offset = 0
  while offset < wire.len:
    assert wire.len-offset >= 4
    var length = 0'u64
    for index in 0..<4: length = length or (uint64(wire[offset+index]) shl (8*index))
    offset += 4
    assert length <= uint64(wire.len-offset)
    var message = newSeq[byte](int(length))
    for index in 0..<message.len: message[index] = wire[offset+index]
    result.add(message)
    offset += message.len
proc batchScenario(variant: Variant, host: var ApplicationNode, services: var Services,
    probe: var NodeProbe, expected: AvailabilitySpecifier, token: WorkSessionToken,
    distribution: seq[seq[byte]], hash: BlockHash) {.raises.} =
  ## One real original exported segment reaches148, then retained137 data alone serves139/140 after report release.
  let limits = availabilityLimits()
  assert uint16(expected.segmentCount) == 1
  assert services.configureAvailabilityStorage(AvailabilityStoreLimits(entries: ElementLimit(2),
      bytes: ByteLimit(16000000)))
  block:
    let selected = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
        root: expected.erasureRoot)
    let verified = verifyAvailabilityTransfer(expected, selected, distribution[0], distribution[1],
      distribution[2], limits.computation).value
    assert services.rememberAvailability(verified) == AvailabilityStoreError.None
  var originalWire = @[148'u8]
  for octet in frame(segmentGroup(ReadKind.Segments, expected.segmentRoot.bytes, 0, [0'u16,
      0])): originalWire.add(octet)
  let original = probe.issue(originalWire)
  let fetched = getMonoTime()+initDuration(seconds = 8)
  while not probe.flows[original].receivedFin:
    assert getMonoTime() < fetched and not probe.flows[original].reset, "original segment batch"
    pump(host, services, probe)
  verifyOriginalSegments(expected, [0'u16, 0], responseMessages(probe.bytes(original)))
  assert host.releaseWork() and services.workSessionPhase(token) == WorkSessionPhase.Empty
  let rows = [1'u16, 0, 1]
  var rawWire = @[139'u8]
  for octet in frame(segmentGroup(ReadKind.SegmentShards, expected.erasureRoot.bytes, 0,
      rows)): rawWire.add(octet)
  let raw = probe.issue(rawWire)
  let rawReturned = getMonoTime()+initDuration(seconds = 8)
  while not probe.flows[raw].receivedFin:
    assert getMonoTime() < rawReturned and not probe.flows[raw].reset, "raw segment shard batch"
    pump(host, services, probe)
  let rawMessages = responseMessages(probe.bytes(raw))
  assert rawMessages.len == 1 and rawMessages[0].len == rows.len*1368
  var payload = segmentGroup(ReadKind.ProvenSegmentShards, expected.erasureRoot.bytes, 0, rows)
  if variant == Variant.BatchUnknownRoot: payload[0] = payload[0] xor 1
  if variant == Variant.BatchTruncated: payload.setLen(payload.len-1)
  if variant == Variant.BatchOverCount:
    payload.setLen(34)
    payload.add(152)
    payload.add(1) # Canonical6145 exceeds the complete-stream shard limit before any body allocation.
  var other = default(ProofWorkerTicket)
  if variant == Variant.BatchForeignDone:
    let admitted = services.beginNetworkRead(readStateRequest(hash))
    assert admitted.error == StateProofAdmissionError.None
    other = admitted.value
    services.waitDone()
  var wire = @[140'u8]
  for octet in frame(payload): wire.add(octet)
  let request = probe.issue(wire)
  if variant in [Variant.BatchUnknownRoot, Variant.BatchTruncated, Variant.BatchOverCount]:
    waitReset(host, services, probe, request)
    return
  if variant == Variant.BatchForeignDone:
    pump(host, services, probe, 20)
    assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
    assert not probe.flows[request].receivedFin
    assert services.collectStateProof(other).kind == ProofWorkerCompletionKind.ReadCompleted
  let admitting = getMonoTime()+initDuration(seconds = 8)
  while not services.stateProofActive:
    assert getMonoTime() < admitting
    assert host.poll(getMonoTime(), StateTime(20), 0)
    probe.poll()
  services.waitDone()
  assert services.rpc.chainPaused
  if variant == Variant.BatchCloseDone:
    host.close()
    assert not services.stateProofActive and not services.rpc.chainPaused
    return
  if variant == Variant.BatchResetDone: probe.abort(request)
  let completed = getMonoTime()+initDuration(seconds = 8)
  while true:
    let pending = if variant == Variant.BatchResetDone: not probe.flows[request].closed
      else: not probe.flows[request].receivedFin and not probe.flows[request].reset
    if not services.stateProofActive and not pending: break
    assert getMonoTime() < completed, "authenticated batch retirement"
    pump(host, services, probe)
  assert not services.rpc.chainPaused
  if variant == Variant.BatchResetDone:
    assert probe.flows[request].closed and not probe.flows[request].receivedFin
    return
  let parts = responseMessages(probe.bytes(request))
  assert parts.len == 4 and parts[0] == rawMessages[0]
  for ordinal, row in rows:
    let selected = AvailabilityRequest(kind: AvailabilityTransferKind.Segment,
      root: expected.erasureRoot,
      row: export_erasure.ExportErasureIndex(uint64(row)))
    assert verifyAvailabilityTransfer(expected, selected, [], parts[0].toOpenArray(ordinal*1368, (
        ordinal+1)*1368-1),
      parts[ordinal+1], limits.computation).error == AvailabilityTransferError.None
proc scenario(variant: Variant) {.raises.} =
  ## Every case starts from actual Tiny PVM code, committed imports, a complete source and matching server identity.
  let fixture = workFixture(external = variant != Variant.PackageEmpty, exported = variant in
      Variant.Batch..Variant.BatchOverCount)
  let saved = if variant in Variant.PackageFetch..Variant.PackageGridRead:
    fixture.workSnapshot(publicKey(), publicKey("RAGNAROK_TEST_PEER_B"), neighbour = variant ==
        Variant.PackageGridRead)
  else: fixture.workSnapshot(publicKey())
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
  if variant in Variant.PackageFetch..Variant.PackageGridRead:
    # Optional fetch policy has explicit independent attempt, deadline and retained-reply ceilings.
    assert not host.configureWorkAcquisition(default(WorkAcquisitionPolicy))
    let cap = ByteLimit(if variant == Variant.PackageReadLimit: 1024 else: 16*1024*1024)
    let acquisition = workAcquisitionPolicy(1, 1000, cap)
    assert host.configureWorkAcquisition(acquisition)
    assert not host.configureWorkAcquisition(acquisition)
    if variant != Variant.PackageEmpty:
      var requestPayload: seq[byte] = @[]
      for index in 0..<2:
        # Frozen fixture roots and indices independently specify the complete original occurrence request.
        for octet in ThreeRoot: requestPayload.add(octet)
        requestPayload.add(1)
        requestPayload.add(byte(index))
        requestPayload.add(0)
      var requestWire = @[148'u8]
      for octet in frame(requestPayload): requestWire.add(octet)
      var replyWire = frame(fixture.segments)
      for octet in frame(fixture.proofs): replyWire.add(octet)
      if variant == Variant.PackageBadProof: replyWire[4] = replyWire[4] xor 1
      probe.expectRead(requestWire, replyWire, holdFin = variant in [Variant.PackageTimeout,
        Variant.PackageReset, Variant.PackageClose, Variant.PackageForeign])
  probe.open(host.localPort, selectedAlpn & "/builder")
  let connected = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated or host.peerCount == 0:
    assert getMonoTime() < connected
    pump(host, services, probe)
  let flow = probe.issue(wire(fixture, variant), persistent = variant in {
    Variant.WithheldFin, Variant.Rotation, Variant.Deadline, Variant.ForeignDone,
    Variant.ForeignClose})
  if variant in [Variant.Disabled, Variant.WrongCore, Variant.LowBudget, Variant.Package,
      Variant.PackageBadProof, Variant.PackageReadLimit]:
    # Disabled acquisition, genuine wrong-core duty, resource refusal and invalid fetched proofs never receive success FIN.
    waitReset(host, services, probe, flow)
    assert host.acceptedWork == 0
    return
  if variant in [Variant.PackageTimeout, Variant.PackageReset, Variant.PackageClose,
      Variant.PackageForeign]:
    # Hold a real outbound CE148 reply before FIN, then exercise exact acquisition cancellation under native and CPU lifetimes.
    waitPhase(host, services, probe, WorkDispatchPhase.Acquiring)
    let deadline = getMonoTime()+initDuration(seconds = 8)
    while probe.served == 0:
      assert getMonoTime() < deadline
      pump(host, services, probe)
    assert not services.stateProofActive and host.acceptedWork == 0
    if variant == Variant.PackageTimeout:
      pump(host, services, probe, 20, clockOffsetMs = 2000)
      waitReset(host, services, probe, flow, clockOffsetMs = 2000)
    elif variant == Variant.PackageClose:
      host.close()
      assert not services.stateProofActive
    else:
      let other = if variant == Variant.PackageForeign:
        services.beginNetworkRead(readStateRequest(hash))
      else: default(NetworkReadStart)
      if variant == Variant.PackageForeign:
        assert other.error == StateProofAdmissionError.None
        services.waitDone()
      probe.abort(flow)
      while host.workPhase != WorkDispatchPhase.Idle:
        assert getMonoTime() < deadline
        pump(host, services, probe)
      if variant == Variant.PackageForeign:
        assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
        assert services.collectStateProof(other.value).kind ==
            ProofWorkerCompletionKind.ReadCompleted
        assert services.reapWorkSubmission()
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
  waitPhase(host, services, probe, WorkDispatchPhase.Ready, $variant)
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
  if variant in [Variant.Report, Variant.ReportFailure, Variant.ReportCancelDone,
      Variant.ReportCloseDone, Variant.ReportStaleTime, Variant.ReportForeignDone] or
      variant in Variant.Availability..Variant.BatchOverCount:
    # Downstream work addresses the retained session, never a replacement execution or caller-selected shard count.
    var limits = workReportLimits()
    if variant == Variant.ReportStaleTime:
      let refused = services.beginWorkReport(token, limits, StateTime(24))
      assert refused.error == StateProofAdmissionError.QueryFailure
      assert services.workSessionPhase(token) == WorkSessionPhase.Complete and
          not services.stateProofActive
      assert host.releaseWork()
      return
    if variant == Variant.ReportFailure: limits.bundleBytes = ByteLimit(0)
    let reporting = services.beginWorkReport(token, limits, StateTime(20))
    assert reporting.error == StateProofAdmissionError.None
    assert services.beginWorkReport(token, limits, StateTime(20)).error ==
        StateProofAdmissionError.Busy
    assert services.workSessionPhase(token) == WorkSessionPhase.Reporting
    services.waitDone()
    assert services.rpc.chainPaused
    if variant == Variant.ReportCloseDone:
      host.close()
      assert not services.stateProofActive and not services.rpc.chainPaused
      assert services.workSessionPhase(token) == WorkSessionPhase.Empty
      return
    if variant == Variant.ReportCancelDone:
      assert host.releaseWork() and not host.releaseWork()
      assert host.workPhase == WorkDispatchPhase.Retiring
      assert services.stateProofActive and services.rpc.chainPaused
      let retired = getMonoTime()+initDuration(seconds = 8)
      while host.workPhase != WorkDispatchPhase.Idle:
        assert getMonoTime() < retired
        pump(host, services, probe)
      assert not services.stateProofActive and not services.rpc.chainPaused
      assert services.workSessionPhase(token) == WorkSessionPhase.Empty
      return
    let collected = services.collectWorkSubmission(token)
    if variant == Variant.ReportFailure:
      assert collected == WorkSessionPhase.Failed
      block:
        let failed = services.workSubmissionOutcome(token)
        assert failed.kind == WorkJobResultKind.ReportFailure
        assert failed.reportPreparationError.error == WorkReportError.BundleFailure
      assert host.releaseWork()
      return
    assert collected == WorkSessionPhase.ReportReady
    let metadata = services.workSubmissionReportInfo(token)
    assert uint16(metadata.header.erasureShards) == 6 and uint64(metadata.core) == 0
    assert metadata.header.erasureRoot.bytes != default(array[32, byte])
    block:
      # These genuine source-bearing transcript aliases retire before any subsequent worker can borrow the graph.
      let reported = services.workSubmissionOutcome(token)
      assert reported.kind == WorkJobResultKind.Reported
      let report = reported.reportTranscript.computedGuaranteeReport.value
      assert report.computedReportInfo.value.header.packageHash.bytes ==
          metadata.header.packageHash.bytes
      let bytes = report.computedReportBytes.value
      let digest = blake2b256(bytes)
      assert digest.error == CryptoError.None
      let message = array[45, byte](reported.reportTranscript.computedGuaranteeMessage.value)
      for index in 0..<32: assert message[13+index] == array[32, byte](digest.value)[index]
    if variant in Variant.Availability..Variant.BatchOverCount:
      # Actual TLS reads consume the retained original report via the ordinary ApplicationNode read dispatcher.
      let original = originalBundle(services, token)
      var policy = availabilityLimits()
      if variant == Variant.AvailabilityLimit: policy.computation.hashes = ElementLimit(1)
      assert not services.configureAvailabilityReads(default(AvailabilityReadLimits))
      if variant != Variant.AvailabilityDisabled:
        assert services.configureAvailabilityReads(policy)
        assert not services.configureAvailabilityReads(policy)
      var payload: seq[byte] = @[]
      for octet in metadata.header.erasureRoot.bytes: payload.add(octet)
      if variant == Variant.AvailabilityWrongRoot: payload[0] = payload[0] xor 1
      payload.add(if variant == Variant.AvailabilityBadIndex: 255'u8 else: 0'u8)
      payload.add(if variant == Variant.AvailabilityBadIndex: 255'u8 else: 0'u8)
      var requestWire = @[137'u8]
      for octet in frame(payload): requestWire.add(octet)
      if variant == Variant.AvailabilityTruncated: requestWire.setLen(requestWire.len-1)
      let request = probe.issue(requestWire)
      if variant in [Variant.AvailabilityDisabled, Variant.AvailabilityLimit,
          Variant.AvailabilityWrongRoot, Variant.AvailabilityBadIndex,
          Variant.AvailabilityTruncated]:
        waitReset(host, services, probe, request)
      else:
        let admitted = getMonoTime()+initDuration(seconds = 8)
        while not services.stateProofActive:
          assert getMonoTime() < admitted
          assert host.poll(getMonoTime(), StateTime(20), 0)
          probe.poll()
        services.waitDone()
        assert services.rpc.chainPaused
        assert services.beginNetworkRead(readStateRequest(hash)).error ==
            StateProofAdmissionError.Busy
        if variant == Variant.AvailabilityCloseDone:
          host.close()
          assert not services.stateProofActive and not services.rpc.chainPaused
          return
        if variant == Variant.AvailabilityRetireDone:
          assert host.releaseWork()
          assert services.workSessionPhase(token) == WorkSessionPhase.Retired
          assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
        if variant == Variant.AvailabilityResetDone: probe.abort(request)
        let completed = getMonoTime()+initDuration(seconds = 8)
        while true:
          # Local cancellation observes close; ordinary replies observe FIN or a peer refusal.
          let pending = if variant == Variant.AvailabilityResetDone: not probe.flows[request].closed
            else: not probe.flows[request].receivedFin and not probe.flows[request].reset
          if not services.stateProofActive and not pending: break
          assert getMonoTime() < completed, "availability read retirement " & $variant
          pump(host, services, probe)
        assert not services.rpc.chainPaused
        if variant == Variant.AvailabilityRetireDone:
          assert services.reapWorkSubmission(), "retired report reaps only after read collection"
          return
        if variant == Variant.AvailabilityResetDone:
          assert probe.flows[request].closed and not probe.flows[request].receivedFin,
            "locally aborted availability read closes without success FIN"
        else:
          let messages = responseMessages(probe.bytes(request))
          assert messages.len == 3
          let expected = AvailabilitySpecifier(packageHash: metadata.header.packageHash,
            bundleLength: metadata.header.bundleLength, erasureRoot: metadata.header.erasureRoot,
            erasureShards: metadata.header.erasureShards, segmentRoot: metadata.header.segmentRoot,
            segmentCount: metadata.header.segmentCount)
          let selected = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
            root: expected.erasureRoot)
          assert verifyAvailabilityTransfer(expected, selected, messages[0], messages[1], messages[
              2],
            policy.computation).error == AvailabilityTransferError.None
          if variant in Variant.Batch..Variant.BatchOverCount:
            batchScenario(variant, host, services, probe, expected, token, messages, hash)
            return
          if variant in Variant.AssurerAudit..Variant.AssurerMissing:
            # The private store deep-copies sealed distributions; every external verified alias retires before the audit lease.
            assert services.configureAvailabilityStorage(AvailabilityStoreLimits(
              entries: ElementLimit(2), bytes: ByteLimit(16000000)))
            var external = verifyAvailabilityTransfer(expected, selected, messages[0], messages[1],
              messages[2], policy.computation).value
            assert services.rememberAvailability(external) == AvailabilityStoreError.None
            assert host.releaseWork() and services.workSessionPhase(token) == WorkSessionPhase.Empty
            var auditPayload: seq[byte] = @[]
            for octet in expected.erasureRoot.bytes: auditPayload.add(octet)
            auditPayload.add(if variant == Variant.AssurerMissing: 1'u8 else: 0'u8)
            auditPayload.add(0)
            var auditWire = @[138'u8]
            for octet in frame(auditPayload): auditWire.add(octet)
            let auditRequest = probe.issue(auditWire)
            if variant == Variant.AssurerMissing:
              waitReset(host, services, probe, auditRequest)
              return
            let auditing = getMonoTime()+initDuration(seconds = 8)
            while not services.stateProofActive:
              assert getMonoTime() < auditing
              assert host.poll(getMonoTime(), StateTime(20), 0)
              probe.poll()
            services.waitDone()
            external = default(VerifiedAvailabilityTransfer) # The cache/worker owns an independent clone, so this external owner may retire even at Done.
            assert services.rpc.chainPaused
            assert services.rememberAvailability(default(VerifiedAvailabilityTransfer)) ==
                AvailabilityStoreError.Busy
            assert not services.configureAvailabilityStorage(AvailabilityStoreLimits(
              entries: ElementLimit(1), bytes: ByteLimit(1)))
            if variant == Variant.AssurerCloseDone:
              host.close()
              assert not services.stateProofActive and not services.rpc.chainPaused
              return
            if variant == Variant.AssurerResetDone: probe.abort(auditRequest)
            let audited = getMonoTime()+initDuration(seconds = 8)
            while true:
              let pending = if variant == Variant.AssurerResetDone: not probe.flows[
                  auditRequest].closed
                else: not probe.flows[auditRequest].receivedFin and not probe.flows[
                    auditRequest].reset
              if not services.stateProofActive and not pending: break
              assert getMonoTime() < audited, "retained assurer read retirement"
              pump(host, services, probe)
            assert not services.rpc.chainPaused
            if variant == Variant.AssurerResetDone:
              assert not probe.flows[auditRequest].receivedFin and probe.flows[auditRequest].closed
            else:
              let auditMessages = responseMessages(probe.bytes(auditRequest))
              assert auditMessages.len == 2
              var auditSelection = selected
              auditSelection.kind = AvailabilityTransferKind.Audit
              assert verifyAvailabilityTransfer(expected, auditSelection, auditMessages[0], [],
                auditMessages[1], policy.computation).error == AvailabilityTransferError.None
            return
          var bundleWire = @[147'u8]
          for octet in frame(metadata.header.erasureRoot.bytes): bundleWire.add(octet)
          let bundleRequest = probe.issue(bundleWire)
          let returned = getMonoTime()+initDuration(seconds = 8)
          while not probe.flows[bundleRequest].receivedFin:
            assert getMonoTime() < returned and not probe.flows[bundleRequest].reset
            pump(host, services, probe)
          let bundles = responseMessages(probe.bytes(bundleRequest))
          assert bundles.len == 1 and bundles[0] == original
    if variant == Variant.ReportForeignDone:
      let other = services.beginNetworkRead(readStateRequest(hash))
      assert other.error == StateProofAdmissionError.None
      services.waitDone()
      assert services.workSubmissionReportInfo(token).header.erasureRoot.bytes ==
          metadata.header.erasureRoot.bytes
      assert host.releaseWork()
      assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
      assert services.workSessionPhase(token) == WorkSessionPhase.Retired
      assert services.collectStateProof(other.value).kind == ProofWorkerCompletionKind.ReadCompleted
      assert services.reapWorkSubmission()
      return
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
  for variant in Variant.Success..Variant.PackageGridRead:
    scenario(variant)
  echo "JAMNP-S application work dispatch passed"
try:
  main()
except:
  quit 2 # Setup or execution exceptions cannot substitute for the complete native transcript.
