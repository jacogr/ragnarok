# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real original-identity TLS delivery preserves another auditor's signed negative judgment unchanged. Native bare-FIN acknowledgment and finite source-free retention remain distinct from computation, block inclusion and finality.
import std/[assertions, monotimes, times, posix/posix]
import ../../src/jamnp-s/[judgment_gossip, judgment_claim, judgment_receipt, audit_origin,
  audit_context, audit_participation, audits, node, connections, read_stream, read_client]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, disputes]
import ../../src/crypto/primitives
import ../../src/quic/address
import ./[jamnp_audit_context, jamnp_guarantee_support, jamnp_judgment_support,
  jamnp_judgment_receipt, jamnp_audit_participation, jamnp_topology_fixture, assurance_signer_context]
proc judgmentGossipChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Genuine standalone qualification precedes native relay by a different actual TLS key, and duplicate offers preserve the real receiver's completed acknowledgment.
  let guarantee = unseenGuarantee(supportFixture(fixture))
  let claim = actualNegativeClaim(fixture, guarantee)
  let message = encodeJudgments([claim.judgmentRecord], actualClaimLimits().message).value
  let claims = verifyJudgmentClaims(fixture.view, message, actualClaimLimits()).value
  let inputs = [JudgmentSourceInput(source: fixture.blockHash, report: guarantee.report)]
  let prepared = prepareJudgmentReceipt(fixture.view, claims, inputs, receiptLimits()).value
  let record = prepared.judgmentAt(0).value
  let origin = prepared.negativeOriginAt(0).value.reportAt(0).value
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let local = context.auditorAt(2).value.ed25519
  let plan = captureAuditParticipation(origin, fixture.view.bestBlock, local, participationLimits()).value
  var keyA = "judgment-gossip-relay.pem"
  var certA = "judgment-gossip-relay-cert.pem"
  var keyB = "judgment-gossip-recipient.pem"
  var certB = "judgment-gossip-recipient-cert.pem"
  assuranceSignerFiles(keyA, certA, 13)
  assuranceSignerFiles(keyB, certB, 12)
  defer:
    discard posix.unlink(keyA.toCString())
    discard posix.unlink(certA.toCString())
    discard posix.unlink(keyB.toCString())
    discard posix.unlink(certB.toCString())
  let selectedAlpn = "jamnp-s/1/01020304"
  let view = fixture.view.finalizeView(fixture.blockHash).value
  var relay = default(NodeService)
  var recipient = default(NodeService)
  var gossip = default(JudgmentGossip)
  var refused = default(JudgmentGossip)
  defer:
    gossip.close(relay)
    refused.close(relay)
    relay.close()
    recipient.close()
  assert relay.open(initConnectionConfig(certA, keyA, selectedAlpn), view, topologyLimits(3, 12)) == NodeError.None
  assert recipient.open(initConnectionConfig(certB, keyB, selectedAlpn), view, topologyLimits(3,
      12)) == NodeError.None
  assert relay.enableJudgmentStreams() and recipient.enableJudgmentStreams()
  assert relay.beginPeerConnection(context.auditorAt(1).value.ed25519,
    networkEndpoint(loopbackAddress(false), recipient.localPort)).error == DialError.None
  let connected = getMonoTime()+initDuration(seconds = 10)
  while relay.peerCount != 1 or recipient.peerCount != 1:
    # Both connections authenticate real independently imported source-roster identities.
    assert getMonoTime() < connected
    assert relay.poll(getMonoTime(), 0)
    assert recipient.poll(getMonoTime(), 0)
  let policy = judgmentGossipPolicy(actualClaimLimits().message, 4, ByteLimit(8000000),
    requestsPerRecord = 1, dialsPerRecord = 0, attempts = 1, timeoutMs = 1000, retryMs = 1)
  assert policy.valid and gossip.configure(policy)
  assert not gossip.offer(default(QualifiedJudgment), plan, JudgmentDeliveryMode.Relayed)
  assert not gossip.offer(record, default(AuditParticipationPlan), JudgmentDeliveryMode.Relayed)
  let scarce = judgmentGossipPolicy(actualClaimLimits().message, 1, ByteLimit(1),
    requestsPerRecord = 1, dialsPerRecord = 0)
  assert refused.configure(scarce)
  assert not refused.offer(record, plan, JudgmentDeliveryMode.Relayed)
  assert refused.attempted == 0 and not refused.sending
  assert gossip.offer(record, plan, JudgmentDeliveryMode.Relayed)
  var received = 0
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while gossip.acknowledged == 0:
    # Incremental recipient expansion and exact request/dial retirement are driven separately from raw native callbacks.
    assert getMonoTime() < deadline
    let clock = getMonoTime()
    assert relay.poll(clock, 0)
    assert recipient.poll(clock, 0)
    gossip.poll(relay, clock)
    let incoming = recipient.takeRead()
    if incoming.error == NodeError.None:
      let task = incoming.value
      assert task.request.kind == ReadKind.Judgment
      assert array[32, byte](task.ticket.sourcePeer.identity) == array[32, byte](local), "TLS relay identity differs from the preserved original judge"
      let decoded = decodeJudgments(task.request.payload, actualClaimLimits().message).value
      assert decoded.len == 1
      let forwarded = decoded.judgmentAt(0).value
      assert uint16(forwarded.validator) == uint16(claim.judgmentRecord.validator)
      assert uint32(forwarded.epoch) == uint32(claim.judgmentRecord.epoch) and not forwarded.valid
      assert array[64, byte](forwarded.signature) == array[64, byte](claim.judgmentRecord.signature)
      assert forwarded.credentialCount == claim.judgmentRecord.credentialCount
      for ordinal in 0..<forwarded.credentialCount:
        assert array[64, byte](forwarded.credentials[ordinal].signature) == array[64, byte](
            claim.judgmentRecord.credentials[ordinal].signature)
      var transcript: seq[byte] = @[]
      for character in "jam_invalid": transcript.add(byte(ord(character)))
      for octet in array[32, byte](forwarded.report): transcript.add(octet)
      let key = EdPublicKey(array[32, byte](context.auditorAt(1).value.ed25519))
      assert verify(key, EdSignature(array[64, byte](forwarded.signature)), transcript)
      assert recipient.respond(task.ticket, captureReadReply(task.request, []).value) == ReadError.None
      inc received
  assert received == 1 and gossip.attempted == 1 and gossip.acknowledged == 1
  assert gossip.offer(record, plan, JudgmentDeliveryMode.Relayed)
  for turn in 0..<100:
    # An identical source/record offer cannot erase an acknowledged physical identity and replay its upload.
    let clock = getMonoTime()
    assert relay.poll(clock, 0)
    assert recipient.poll(clock, 0)
    gossip.poll(relay, clock)
  assert gossip.attempted == 1 and gossip.acknowledged == 1
