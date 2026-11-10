# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two ordinary authenticated application loops exercise actual CE141 FINs, default refusal, shared-worker exclusion, retention and joined/foreign shutdown using a genuinely computed complete parent.

import std/[assertions, monotimes, times, posix/posix]
import ../../src/app/[services, options, node as application_node, assurance_distribution]
import ../../src/app/proof/[worker, work_submission]
import ../../src/jamnp-s/[node as node_streams, connections, endpoints, read_stream, read_client,
  assurance_distribution as receipt_rules, assurance_duty, work_signer]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/state/safrole
import ../../src/chain/[genesis, provider]
import ../../src/quic/address
import ./[jamnp_assurance_fixture, assurance_signer_context, jamnp_topology_fixture]

proc pump(a, b: var ApplicationNode, now: StateTime) {.raises.} =
  ## Only production polling may admit or collect the receiver's own native/managed work.
  assert a.poll(getMonoTime(), now, 0), "CE141 sender foreground loop"
  assert b.poll(getMonoTime(), now, 0), "CE141 receiver foreground loop"

proc admission(a, b: var ApplicationNode, target: NodePeer, request: ReadRequest,
    now: StateTime): NodeRequestTicket {.raises.} =
  ## Finished/closing streams keep physical charges until native retirement; bounded retries preserve exact request ownership.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while true:
    let started = a.request(target, request, ByteLimit(0))
    if started.error == NodeError.None: return started.value
    assert started.error in [NodeError.Unavailable, NodeError.LimitExceeded], "CE141 request admission"
    assert getMonoTime() < deadline, "CE141 physical admission deadline"
    pump(a, b, now)

proc reply(a, b: var ApplicationNode, ticket: NodeRequestTicket, now: StateTime,
    success: bool) {.raises.} =
  ## Exact two-way FIN grants an empty transport acknowledgment only after managed fresh retention; resets never grant success.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while true:
    pump(a, b, now)
    let taken = a.takeReply(ticket)
    if taken.error != ReadError.Unavailable:
      if success: assert taken.error == ReadError.None and taken.value.bytes.len == 0, "CE141 bare FIN acknowledgment"
      else: assert taken.error != ReadError.None, "refused CE141 cannot acknowledge"
      return
    assert getMonoTime() < deadline, "CE141 response FIN deadline"

proc assuranceReceiptRuntime*(sender: var Services, settings: Options,
    signed: SignedAssurance, fixture: AssuranceAcquisitionFixture,
    certificate, privateKey, suffix: string, limits: AssuranceDutyLimits,
        ownClose = false) {.raises.} =
  ## Actual locally collected stored-possession signing feeds another ordinary application node, not a raw synthetic responder or manually computed receiver result.
  let now = captureAssuranceDuty(fixture.source, fixture.local, limits).value.dutyInfo.value.slot
  var otherKey = "assurance-receipt-key-" & suffix & ".pem"
  var otherCert = "assurance-receipt-cert-" & suffix & ".pem"
  assuranceSignerFiles(otherKey, otherCert, 13)
  defer:
    discard posix.unlink(otherKey.toCString())
    discard posix.unlink(otherCert.toCString())
  assert array[32, byte](loadWorkSigner(otherCert, otherKey).value.signerIdentity.value) == array[
      32, byte](fixture.other), "actual second parent-roster TLS identity"
  var receiver = default(Services)
  defer: receiver.close()
  assert receiver.start(settings, "CE141 native receiver"), "independently decoded complete receiver source"
  let senderFinality = sender.publishFinalized(sender.chainView.bestBlock.value.blockHash)
  let receiverFinality = receiver.publishFinalized(receiver.chainView.bestBlock.value.blockHash)
  assert senderFinality == ViewFinalizeError.None, "sender actual trusted finality: " & $senderFinality
  assert receiverFinality == ViewFinalizeError.None, "receiver actual trusted finality: " & $receiverFinality
  var a = default(ApplicationNode)
  var b = default(ApplicationNode)
  defer:
    b.close()
    a.close() # Both native callback owners retire before either borrowed Services instance.
  let geometry = topologyLimits(3, int(uint64(fixture.source.value.epochSlots)))
  let senderOpen = a.open(sender, initConnectionConfig(certificate, privateKey, sender.nodeProtocol,
      streams = 512), geometry, now)
  let receiverOpen = b.open(receiver, initConnectionConfig(otherCert, otherKey,
      receiver.nodeProtocol, streams = 512), geometry, now)
  assert senderOpen == NodeError.None, "sender source-bound native open: " & $senderOpen
  assert receiverOpen == NodeError.None, "receiver source-bound native open: " & $receiverOpen
  let policyLimits = AssuranceDistributionLimits(duty: limits, wireBytes: ByteLimit(139))
  let policy = assuranceReceiptPolicy(policyLimits, 1, 1, timeoutMs = 3000)
  let wire = sender.currentAssuranceBytes(signed, ByteLimit(139)).value
  let request = decodeReadRequest(ReadKind.Assurance, wire).value
  assert not a.configureAssuranceReceipt(default(AssuranceReceiptPolicy)), "default receipt disabled"
  assert a.configureAssuranceReceipt(policy), "explicit sender selector"
  let dial = a.beginPeerConnection(fixture.other, networkEndpoint(loopbackAddress(false), b.localPort))
  assert dial.error == DialError.None, "authenticated native dial: " & $dial.error
  let connected = getMonoTime()+initDuration(seconds = 5)
  while a.peerCount == 0 or b.peerCount == 0:
    assert getMonoTime() < connected, "actual CE141 TLS connection"
    pump(a, b, now)
  var target = default(NodePeer)
  for index in 0..<a.peerCount:
    # Locate only the actual authenticated generation, never a peer-created source claim.
    let candidate = a.peerAt(index).value
    if array[32, byte](candidate.identity) == array[32, byte](fixture.other): target = candidate
  assert array[32, byte](target.identity) == array[32, byte](fixture.other), "authenticated receiver generation"
  let disabled = admission(a, b, target, request, now)
  reply(a, b, disabled, now, false)
  assert b.receivedAssurances == 0 and b.pendingAssurances == 0, "default native route refuses CE141"
  assert b.configureAssuranceReceipt(policy) and not b.configureAssuranceReceipt(policy), "explicit once-only receiver activation"
  let foreign = receiver.beginAssuranceDistribution(request, fixture.local, policyLimits).value
  let pending = admission(a, b, target, request, now)
  let held = getMonoTime()+initDuration(seconds = 5)
  while receiver.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < held, "foreign CPU completion deadline"
    pump(a, b, now)
  for turn in 0..<8:
    # Uncollected Done keeps the full canonical/RPC lease while authenticated UDP progress continues.
    pump(a, b, now)
  assert receiver.stateProofActive(foreign) and b.receivedAssurances == 0, "foreign Done cannot be stolen by live receipt"
  assert receiver.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized, "foreign generation cannot release held receipt lease"
  assert receiver.collectStateProof(foreign).workSubmissionValue.kind ==
      WorkJobResultKind.AssuranceQualified
  reply(a, b, pending, now, true)
  assert b.receivedAssurances == 1 and b.pendingAssurances == 1, "retained fresh candidate precedes native acknowledgment"
  assert b.pendingAssurance(0).validator == ValidatorIndex(1), "receiver preserves original parent-roster ordinal"
  if ownClose:
    # Stop polling the receiver after its real actor submits; Done must remain uncollected until close joins this exact lease.
    let closing = admission(a, b, target, request, now)
    let deadline = getMonoTime()+initDuration(seconds = 5)
    while not receiver.stateProofActive:
      assert getMonoTime() < deadline, "owned native receipt admission deadline"
      pump(a, b, now)
    while receiver.stateProofPhase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline, "owned receipt Done witness"
      assert a.poll(getMonoTime(), now, 0), "sender progress while receiver Done remains uncollected"
    assert not receiver.stateProofAvailable and b.receivedAssurances == 1, "Done still freezes the source without acknowledging incoming candidate"
    b.close()
    assert receiver.stateProofAvailable and not receiver.stateProofActive and b.pendingAssurances ==
        0, "owned controller close joins and retires its exact Done borrow"
    let expiry = getMonoTime()+initDuration(seconds = 31)
    var retired = false
    for turn in 0..<16:
      # Advance the explicit host clock beyond the real 30-second idle limit and sweep every physical slot; teardown need not be instantly visible to a peer.
      assert a.poll(expiry+initDuration(milliseconds = turn), now, 0), "sender continues through bounded route expiry"
      let closed = a.takeReply(closing)
      assert closed.error != ReadError.None, "uncollected verification cannot acknowledge during close or expiry"
      if closed.error != ReadError.Unavailable:
        retired = true
        break
    assert retired, "owned receiver shutdown retains no indefinitely collectable sender route"
    return
  let duplicate = admission(a, b, target, request, now)
  reply(a, b, duplicate, now, true)
  assert b.receivedAssurances == 2 and b.pendingAssurances == 1, "bounded same-key duplicate replaces rather than appends"
  var damaged = wire
  damaged[damaged.high] = damaged[damaged.high] xor 1
  let corrupt = admission(a, b, target, decodeReadRequest(ReadKind.Assurance, damaged).value, now)
  reply(a, b, corrupt, now, false)
  assert b.receivedAssurances == 2 and b.pendingAssurances == 1, "real bad signature cannot overwrite retained candidate"
  let heldForeign = receiver.beginAssuranceDistribution(request, fixture.local, policyLimits).value
  b.close()
  assert receiver.stateProofActive(heldForeign), "receiver close cannot cancel/join another controller's exact job"
  receiver.stopStateProofs()
  assert not receiver.stateProofActive(heldForeign) and receiver.stateProofAvailable, "explicit foreign owner joins before Services retirement"
