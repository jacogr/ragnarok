# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_staged_work_streams_arc_release"}

## Actual authenticated builder streams pause at headers and acknowledge only genuinely collected source-bound work.

import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/app/[services, options, startup]
import ../../../src/app/proof/[worker, work_submission as work_jobs]
import ../../../src/jamnp-s/[node, connections, work_submission, work_stream, read_stream]
import ../../../src/jamnp-s/work_duty
import ../../../src/codec/[bounded]
import ../../../src/codec/work/package as work_package
from ../../../src/codec/work/digest import Gas
import ../../../src/codec/state/safrole
import ../../../src/chain/[genesis, provider]
import ../../support/[jamnp_work_fixture, jamnp_topology_fixture, jamnp_node_probe,
  jamnp_read_validation_context, pvm_input_refinement, pvm_import_inputs, arc_evidence]

type
  Variant {.pure.} = enum Success, Package, Empty, CorruptProof, WithheldFin, Suffix, CancelDone,
    ForeignDone, Oversized, Observer, GlobalQuota, OverGas, Disabled, Truncated, ShortBody,
      HugeProof, WrongCore, UncertainEpoch, LargePackage, LargeBundle
  Detached = object ## Completed source-free transcripts survive all native/Services lifetimes for independent ownership checks.
    header: UntrustedWorkHeader
    body: UntrustedWorkBody

proc publicKey(): StateEdKey {.raises.} =
  ## Only the actual fixture's public TLS identity enters the validator roster; no private bytes escape setup.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  StateEdKey(bytes)

proc frame(payload: openArray[byte]): seq[byte] =
  ## Independent literal E4 framing never calls the production route or message encoder.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(payload.len) shr (index*8)) and 255))
  for octet in payload: result.add(octet)

proc wire(f: WorkFixture, variant: Variant): seq[byte] =
  ## Independently authored selectors and separate payloads exercise header/body boundaries over actual TLS.
  result = @[if variant in [Variant.Package, Variant.LargePackage]: 133'u8 else: 146'u8]
  if variant in [Variant.Package, Variant.LargePackage]:
    var first = @[0'u8, 0]
    for octet in f.package: first.add(octet)
    for octet in frame(first): result.add(octet)
  else:
    var first = f.first
    if variant == Variant.WrongCore: first[0] = 1 # A real validator on core0 is not eligible to authorize core1.
    for octet in frame(first): result.add(octet)
    for octet in frame(f.package): result.add(octet)
  if variant == Variant.ShortBody:
    for octet in [6'u8, 0, 0, 0, 97, 98]: result.add(octet)
    return # The committed six-byte extrinsic message terminates after only two payload bytes.
  for octet in frame(f.extrinsics): result.add(octet)
  if variant notin [Variant.Package, Variant.LargePackage]:
    for octet in frame(f.segments): result.add(octet)
    if variant == Variant.HugeProof:
      for octet in [255'u8, 255, 255, 255]: result.add(octet)
      return # Full-width E4 overflow is rejected before any proof allocation or native-int narrowing.
    var proofs = f.proofs
    if variant == Variant.CorruptProof: proofs[1] = proofs[1] xor 1
    for octet in frame(proofs): result.add(octet)
  if variant == Variant.Suffix: result.add(0) # One trailing octet cannot become an accepted extra message.

proc pump(server: var NodeService, probe: var NodeProbe, milliseconds = 1) =
  ## Native callbacks copy only bounded detached bytes while a Services CPU job owns all canonical aliases.
  let until = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < until:
    assert server.poll(getMonoTime(), 0)
    probe.poll()

proc waitDone(services: var Services, server: var NodeService, probe: var NodeProbe) =
  ## Transport remains nonblocking through Queued, Running and Done; no canonical alias is read during this wait.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "staged work CPU deadline"
    pump(server, probe)

proc waitHeader(server: var NodeService, probe: var NodeProbe): NodeWorkTask =
  ## Only a complete small header creates one exact host claim.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while true:
    let task = server.takeWorkHeader()
    if task.error == NodeError.None: return task.value
    assert getMonoTime() < deadline, "staged work header deadline"
    pump(server, probe)

proc waitBody(server: var NodeService, probe: var NodeProbe,
    ticket: NodeWorkTicket): UntrustedWorkBody =
  ## Exact request FIN and bounded messages precede raw body handoff.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while true:
    let body = server.takeWorkBody(ticket)
    if body.error == NodeError.None: return body.value
    assert getMonoTime() < deadline, "staged work body deadline"
    pump(server, probe)

proc settleReset(server: var NodeService, probe: var NodeProbe, flow: int,
    locallyCancelled = false) =
  ## Observe actual reset and native physical retirement before testing released quota.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while server.workStreamCount != 0 or not (probe.flows[flow].reset or
      (locallyCancelled and probe.flows[flow].closed)):
    assert not probe.flows[flow].receivedFin, "rejection cannot produce successful response FIN"
    assert getMonoTime() < deadline, "staged work reset/retirement deadline: reset=" & $probe.flows[
        flow].reset & ",closed=" & $probe.flows[flow].closed & ",physical=" &
        $server.workStreamCount
    pump(server, probe)

proc live(variant: Variant): Detached {.raises.} =
  ## Actual Services owns grants/refinement; the native owner and simulated dispatcher retain only opaque tokens and raw transcripts.
  result = default(Detached)
  var fixture = workFixture(external = variant != Variant.Empty)
  if variant in [Variant.LargePackage, Variant.LargeBundle]:
    # Valid large package framing is checked independently from guest authorization and body acceptance.
    let package = WorkPackage(items: @[WorkItem(refineGas: Gas(1), accumulateGas: Gas(1),
      payload: newSeq[byte](262144))])
    var encoded = newSeq[byte](270000)
    let written = encodeWorkPackage(package, fullPackageConfig(ByteLimit(MaxBundleBytes)), encoded)
    assert written.error == PackageError.None
    encoded.setLen(written.value)
    fixture.package = encoded
    fixture.first = @[0'u8, 0, 0]
  if variant == Variant.OverGas:
    # Patch only the authored first item's E8 refinement-gas field; the package and authorizer commitments remain otherwise unchanged.
    let selected = fixture.input.package.workItemAt(0).value
    var item = newSeq[byte](selected.workItemInfo.value.consumed)
    assert selected.encodeOwnedWorkItem(item).error == PackageError.None
    var position = -1
    var matches = 0
    for start in 0..fixture.package.len-item.len:
      var same = true
      for index in 0..<item.len:
        if fixture.package[start+index] != item[index]: same = false
      if same:
        position = start
        inc matches
    assert matches == 1 and position >= 0
    for index in 0..<8: fixture.package[position+36+index] = byte((1000000001'u64 shr (index*8)) and 255)
  let saved = fixture.workSnapshot(if variant == Variant.Observer: default(
      StateEdKey) else: publicKey())
  writeFile("staged-work-chain.json", workChainText(saved))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "staged-work-chain.json"], settings)
  var services = default(Services)
  var server = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    server.close()
    services.close() # Every selected-state borrower joins before the retained source owner retires.
  assert services.start(settings, "staged work"), "actual Services startup"
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  let opened = server.open(config, services.chainView, topologyLimits(2))
  assert opened == NodeError.None, "actual node open: " & $opened
  if variant != Variant.Disabled: assert server.enableWorkStreams() # A real host dispatcher explicitly activates task admission.
  let independentRead = readStateRequest(hash)
  probe.open(server.localPort, selectedAlpn & "/builder")
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated or server.peerCount == 0:
    assert getMonoTime() < deadline, "actual builder TLS admission"
    pump(server, probe)
  let packet = if variant == Variant.Oversized: @[146'u8, 4, 2, 0, 0]
    elif variant == Variant.Truncated: @[146'u8, 4, 0]
    else: wire(fixture, variant)
  let flow = probe.issue(packet, persistent = variant == Variant.WithheldFin)
  if variant in [Variant.Oversized, Variant.Observer, Variant.Disabled, Variant.Truncated]:
    # Declared oversized headers and non-validator nodes refuse before any header task or CPU admission exists.
    settleReset(server, probe, flow)
    assert server.takeWorkHeader().error == NodeError.Unavailable
    assert not probe.flows[flow].receivedFin
    if variant == Variant.Truncated:
      # A complete legal E4 prefix followed by an incomplete header body also refuses without a task.
      let short = probe.issue(@[146'u8, 3, 0, 0, 0, 0])
      settleReset(server, probe, short)
      assert server.takeWorkHeader().error == NodeError.Unavailable
      assert not probe.flows[short].receivedFin
    return
  let task = waitHeader(server, probe)
  if variant in [Variant.LargePackage, Variant.LargeBundle]:
    # Actual TLS selectors133 and146 both preserve the entire legal package beyond the previous200KiB ceiling.
    let header = task.header
    let kind = if variant == Variant.LargePackage: WorkSubmissionKind.Package else: WorkSubmissionKind.Bundle
    let decoded = decodeWorkSubmission(kind, header.firstMessage, header.packageMessage,
      fullPackageConfig(ByteLimit(MaxBundleBytes)))
    assert decoded.error == WorkSubmissionError.None
    assert decoded.value.submissionInfo.value.packageBytes == fixture.package.len
    assert fixture.package.len > 204800
    assert server.rejectWork(task.ticket)
    settleReset(server, probe, flow)
    return
  let ticket = task.ticket
  let headerBytes = if variant in [Variant.Package, Variant.LargePackage]: uint64(
      4+2+fixture.package.len)
    else: uint64(8+fixture.first.len+fixture.package.len)
  pump(server, probe, 30)
  assert server.workInputBytes(ticket) == headerBytes, "no body prefix may be consumed while authorization is paused"
  assert server.takeWorkBody(ticket).error == NodeError.Unavailable
  assert not probe.flows[flow].receivedFin
  assert server.takeWorkHeader().error == NodeError.Unavailable, "one exact header claim only"
  # Per-peer physical work quota refuses a second simultaneous upload without consuming the first grant.
  let excess = probe.issue(wire(fixture, variant))
  let quotaDeadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.flows[excess].reset:
    assert getMonoTime() < quotaDeadline
    pump(server, probe)
  assert server.workLive(ticket) and server.workStreamCount == 1
  if variant == Variant.GlobalQuota:
    # Three distinct authenticated builders exercise the global two-stream quota and actual native-close release.
    var diagnostic = ""
    assert ensureIdentity("staged-peer-c", diagnostic) and ensureIdentity("staged-peer-d", diagnostic)
    var second, third = default(NodeProbe)
    defer: third.close()
    defer: second.close()
    second.open(server.localPort, selectedAlpn & "/builder", "staged-peer-c/cert.pem", "staged-peer-c/key.pem")
    third.open(server.localPort, selectedAlpn & "/builder", "staged-peer-d/cert.pem", "staged-peer-d/key.pem")
    let connected = getMonoTime()+initDuration(seconds = 5)
    while not second.authenticated or not third.authenticated or server.peerCount < 3:
      assert getMonoTime() < connected
      pump(server, probe)
      second.poll()
      third.poll()
    let held = second.issue(wire(fixture, variant))
    let waiting = getMonoTime()+initDuration(seconds = 5)
    var other = server.takeWorkHeader()
    while other.error != NodeError.None:
      assert getMonoTime() < waiting
      pump(server, probe)
      second.poll()
      third.poll()
      other = server.takeWorkHeader()
    assert server.workStreamCount == 2
    let refused = third.issue(wire(fixture, variant))
    while not third.flows[refused].reset:
      assert getMonoTime() < waiting
      pump(server, probe)
      second.poll()
      third.poll()
    assert server.workStreamCount == 2 and server.workLive(ticket) and server.workLive(
        other.value.ticket)
    assert server.rejectWork(ticket)
    while server.workStreamCount != 1 or not probe.flows[flow].reset:
      assert getMonoTime() < waiting
      pump(server, probe)
      second.poll()
      third.poll()
    let admitted = third.issue(wire(fixture, variant))
    var replacement = server.takeWorkHeader()
    while replacement.error != NodeError.None:
      assert getMonoTime() < waiting
      pump(server, probe)
      second.poll()
      third.poll()
      replacement = server.takeWorkHeader()
    assert server.workStreamCount == 2
    assert server.rejectWork(other.value.ticket) and server.rejectWork(replacement.value.ticket)
    while server.workStreamCount != 0 or not second.flows[held].reset or not third.flows[
        admitted].reset:
      assert getMonoTime() < waiting
      pump(server, probe)
      second.poll()
      third.poll()
    assert not probe.flows[flow].receivedFin and not second.flows[held].receivedFin and
        not third.flows[admitted].receivedFin
    return
  let observed = if variant == Variant.UncertainEpoch: StateTime(24) else: StateTime(20)
  let recipient = workRecipient(publicKey(), observed)
  let dutyLimits = WorkDutyLimits(chapterBytes: ByteLimit(10000), disputeItems: ElementLimit(128))
  if variant == Variant.OverGas:
    # Actual Tiny gas bounds reject before CPU admission or any unauthorized large-body read.
    let refused = services.beginWorkSubmission(task.header, fixture.limits, executionLimits(),
      recipient, dutyLimits)
    assert refused.error == StateProofAdmissionError.QueryFailure
    assert refused.captureError == WorkJobError.InvalidInput and services.stateProofAvailable
    assert services.stateProofPhase == ProofWorkerPhase.Idle
    assert server.workInputBytes(ticket) == headerBytes
    assert server.rejectWork(ticket)
    settleReset(server, probe, flow)
    return
  let started = services.beginWorkSubmission(task.header, fixture.limits, executionLimits(),
      recipient, dutyLimits)
  assert started.error == StateProofAdmissionError.None
  let token = started.value
  waitDone(services, server, probe)
  assert server.workInputBytes(ticket) == headerBytes and not probe.flows[flow].receivedFin
  if variant in [Variant.WrongCore, Variant.UncertainEpoch]:
    # Exact CPU collection preserves actual duty refusal before any body permission or authorizer grant can escape.
    assert services.collectWorkSubmission(token) == WorkSessionPhase.Failed
    block:
      let outcome = services.workSubmissionOutcome(token)
      assert outcome.kind == WorkJobResultKind.DutyFailure
      let expected = if variant == Variant.WrongCore: WorkDutyError.NotAssigned else: WorkDutyError.UncertainEpoch
      assert outcome.dutyError.error == expected
    assert server.workInputBytes(ticket) == headerBytes
    assert server.rejectWork(ticket)
    settleReset(server, probe, flow)
    assert services.retireWorkSubmission(token)
    return
  if variant == Variant.CancelDone:
    # Reset reaches the native owner before exact Done collection; no canceled proof can emit success FIN.
    probe.abort(flow)
    settleReset(server, probe, flow, locallyCancelled = true)
    assert services.retireWorkSubmission(token)
    assert services.collectWorkSubmission(token) == WorkSessionPhase.Retired
    assert services.reapWorkSubmission()
    assert server.acknowledgeWork(ticket) == ReadError.InvalidStream
    assert not probe.flows[flow].receivedFin
    return
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Authorized
  let duty = services.workSubmissionDuty(token)
  assert duty.valid and uint64(duty.core) == 0 and uint32(duty.observedTime) == 20
  assert array[32, byte](duty.sourceRoot) == array[32, byte](saved.stateRoot)
  assert server.permitWorkBody(ticket, services.workSubmissionInfo(token)) == ReadError.None
  if variant in [Variant.Suffix, Variant.ShortBody, Variant.HugeProof]:
    settleReset(server, probe, flow)
    assert services.retireWorkSubmission(token)
    assert not probe.flows[flow].receivedFin
    return
  if variant == Variant.WithheldFin:
    pump(server, probe, 30)
    assert server.takeWorkBody(ticket).error == NodeError.Unavailable
    assert not probe.flows[flow].receivedFin
    probe.enable(flow, finish = true)
  let body = waitBody(server, probe, ticket)
  assert server.takeWorkBody(ticket).error == NodeError.Unavailable
  assert not probe.flows[flow].receivedFin, "request FIN is not a successful response"
  if variant == Variant.ForeignDone:
    # Source-free native close may retire frames while an unrelated exact worker result still occupies the canonical graph lease.
    let foreign = services.beginNetworkRead(independentRead)
    assert foreign.error == StateProofAdmissionError.None
    waitDone(services, server, probe)
    assert server.rejectWork(ticket)
    settleReset(server, probe, flow)
    assert services.retireWorkSubmission(token)
    assert not services.reapWorkSubmission()
    assert services.stateProofPhase == ProofWorkerPhase.Done
    assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
    assert services.reapWorkSubmission()
    return
  let completed = if variant in [Variant.Package, Variant.LargePackage]:
    services.beginWorkPackage(token, body.extrinsics, [@[inputProof(0)], @[inputProof(1)]], [
        inputPair(1)])
  else: services.beginWorkBundle(token, body.extrinsics, body.segments, body.proofs)
  assert completed.error == StateProofAdmissionError.None
  waitDone(services, server, probe)
  assert not probe.flows[flow].receivedFin, "Done is not host acceptance"
  let phase = services.collectWorkSubmission(token)
  if variant == Variant.CorruptProof:
    assert phase == WorkSessionPhase.Failed
    block:
      # Genuine child refusal aliases retire before source/session cleanup.
      let outcome = services.workSubmissionOutcome(token)
      assert outcome.kind == WorkJobResultKind.BodyFailure
      assert outcome.bodyError.error == WorkSubmissionError.ImportFailure
    assert server.rejectWork(ticket)
    settleReset(server, probe, flow)
    assert services.retireWorkSubmission(token)
    return
  assert phase == WorkSessionPhase.Complete
  assert server.acknowledgeWork(ticket) == ReadError.None
  assert services.retireWorkSubmission(token)
  let finDeadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.flows[flow].receivedFin or server.workStreamCount != 0:
    assert getMonoTime() < finDeadline, "bare acknowledgment and actual close"
    pump(server, probe)
  assert probe.bytes(flow).len == 0, "no fabricated E4 acknowledgment payload"
  assert not server.workLive(ticket)
  assert server.permitWorkBody(ticket, WorkSubmissionInfo()) != ReadError.None
  # A later complete header can reserve the same physical quota only after actual native retirement.
  let again = probe.issue(wire(fixture, variant))
  let next = waitHeader(server, probe)
  assert not server.workLive(ticket) and server.workLive(next.ticket)
  assert server.rejectWork(next.ticket)
  settleReset(server, probe, again)
  result = Detached(header: task.header, body: body)
var retained = default(Detached)
for variant in low(Variant)..high(Variant):
  try:
    # Every case exercises real TLS and genuine CPU work independently of other native executables.
    let completed = live(variant)
    if variant == Variant.Success: retained = completed
  except:
    assert false, "staged work fixture setup: " & $variant

proc releaseCycle(f: Detached) =
  ## Copy/release genuine complete transcripts and detached byte outputs after every native/Services owner has closed.
  let header = f.header
  let body = f.body
  assert header.valid and body.valid
  var first = header.firstMessage
  let original = first[0]
  first[0] = first[0] xor 1
  assert header.firstMessage[0] == original, "returned header bytes cannot mutate retained input"
  assert header.packageMessage.len > 0
  assert body.extrinsics.len == 6 and body.segments.len == 8208 and body.proofs.len > 0
releaseCycle(retained)
let before = getOccupiedMem()
for iteration in 0..<1000: releaseCycle(retained) # Genuine source-free owners and independent byte copies must retire completely.
let after = getOccupiedMem()
assert before == after
recordArcRelease("jamnp_staged_work_streams", 1000, before, after)
echo "JAMNP-S staged work streams passed"
echo "ARC_RELEASE cycles=1000 unchanged"
