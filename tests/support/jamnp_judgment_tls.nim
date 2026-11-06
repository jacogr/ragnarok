# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary ApplicationNode receipt and real original-identity TLS peers exercise positive acknowledgment, previously unseen negative-report CE136 acquisition, complete support qualification and late-failure atomicity.
import std/[assertions, monotimes, times, syncio, posix/posix]
import ../../src/app/[services, options, node as application_node, judgment_distribution, audit_state]
import ../../src/jamnp-s/[node, connections, read_stream, judgment_claim, judgment_receipt,
  judgment_store, audit_context, audits]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, owned, disputes, guarantees]
import ../../src/codec/state/safrole
import ../../src/crypto/primitives
import ../../src/quic/address
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_guarantee_support,
  jamnp_judgment_support, jamnp_judgment_receipt, jamnp_read_validation_context,
  jamnp_topology_fixture, current_application_context, assurance_signer_context]
proc reportWire(report: OwnedReport): seq[byte] =
  ## Independently frame complete canonical raw report bytes without forging a checked-read or private source capability.
  let info = report.ownedReportInfo.value
  result = newSeq[byte](info.consumed+4)
  for index in 0..<4: result[index] = byte((uint32(info.consumed) shr (index*8)) and 255)
  assert report.encodeOwnedReport(result.toOpenArray(4, result.len-1)).error == OwnershipError.None
proc positiveRecord(negative: AuditJudgment): AuditJudgment =
  ## A distinct actual Ed25519 transcript makes the original auditor accountable for its opposite signed claims.
  result = negative
  result.valid = true
  result.slot = GuaranteeSlot(0)
  result.credentialCount = 0
  result.credentials = default(array[3, GuaranteeCredential])
  var raw = default(array[32, byte])
  raw[0] = 12
  var message: seq[byte] = @[]
  for character in "jam_valid": message.add(byte(ord(character)))
  for octet in array[32, byte](result.report): message.add(octet)
  result.signature = DisputeSignature(array[64, byte](sign(importSeed(raw).value, message).value))
proc exchange(receiver: var ApplicationNode, sender: var NodeService, peer: NodePeer,
    records: openArray[AuditJudgment], reports: array[2, Guarantee], hashes: array[2, DisputeHash],
    now: StateTime, acknowledged: bool): int {.raises.} =
  ## One real upload retains its incoming FIN while the receiver requests missing reports back from this original live TLS publisher; late rejection never sends a successful bare FIN.
  let wire = encodeJudgments(records, actualClaimLimits().message).value
  let request = decodeReadRequest(ReadKind.Judgment, wire).value
  let deadline = getMonoTime()+initDuration(seconds = 10)
  var started = false
  var ticket = default(NodeRequestTicket)
  var queries = 0
  while true:
    # Real dispatcher/native callbacks and bounded managed worker collection run through the ordinary foreground host.
    assert getMonoTime() < deadline, "bounded judgment request/response FIN"
    let clock = getMonoTime()
    assert receiver.poll(clock, now, 0)
    assert sender.poll(clock, 0)
    if not started:
      let admitted = sender.request(peer, request, ByteLimit(0))
      if admitted.error == NodeError.None:
        ticket = admitted.value
        started = true
      continue
    let incoming = sender.takeRead()
    if incoming.error == NodeError.None:
      # The publisher really possesses each supported full report, and responds under the exact requested hash and physical native ticket.
      let task = incoming.value
      assert task.request.kind == ReadKind.Report
      let payload = task.request.payload
      var selected = -1
      for index in 0..<reports.len:
        var same = payload.len == 32
        for octet in 0..<32:
          if payload[octet] != array[32, byte](hashes[index])[octet]: same = false
        if same: selected = index
      assert selected >= 0, "CE136 requests the original complete judged report identity"
      inc queries
      let reply = captureReadReply(task.request, reportWire(reports[selected].report)).value
      assert sender.respond(task.ticket, reply) == ReadError.None
    let completed = sender.takeReply(ticket)
    if completed.error == ReadError.Unavailable: continue
    if acknowledged:
      assert completed.error == ReadError.None and completed.value.bytes.len == 0, "whole qualified CE145 receipt returns exact bare FIN"
    else:
      assert completed.error != ReadError.None, "late bad supporting guarantee cannot acknowledge an earlier accepted prefix"
    return queries
proc judgmentTlsChecks*(fixture: AuditContextFixture) {.raises.} =
  ## No raw validity flag, fabricated availability assignment or source injection reaches the foreground judgment pipeline.
  let first = unseenGuarantee(supportFixture(fixture))
  let second = unseenGuarantee(supportFixture(fixture), mutation = 2)
  let a = actualNegativeClaim(fixture, first).judgmentRecord
  let b = actualNegativeClaim(fixture, second).judgmentRecord
  let positive = positiveRecord(a)
  var stateFile = "judgment-tls-state.json"
  var keyA = "judgment-tls-publisher.pem"
  var certA = "judgment-tls-publisher-cert.pem"
  var keyB = "judgment-tls-receiver.pem"
  var certB = "judgment-tls-receiver-cert.pem"
  writeFile(stateFile, currentApplicationText(fixture.view.bestBlock.value))
  assuranceSignerFiles(keyA, certA, 12)
  assuranceSignerFiles(keyB, certB, 13)
  defer:
    discard posix.unlink(stateFile.toCString())
    discard posix.unlink(keyA.toCString())
    discard posix.unlink(certA.toCString())
    discard posix.unlink(keyB.toCString())
    discard posix.unlink(certB.toCString())
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", stateFile], options)
  var services = default(Services)
  defer: services.close()
  assert services.start(options, "genuine TLS judgment receipt")
  assert services.configureAudits(registryLimits())
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let now = context.contextInfo.value.slot
  let geometry = topologyLimits(3, int(context.contextInfo.value.epochSlots))
  let finalized = fixture.view.finalizeView(fixture.blockHash).value
  var receiver = default(ApplicationNode)
  var sender = default(NodeService)
  defer:
    receiver.close()
    sender.close()
  assert receiver.open(services, initConnectionConfig(certB, keyB, services.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None
  assert sender.open(initConnectionConfig(certA, keyA, services.nodeProtocol,
    streams = 512), finalized, geometry) == NodeError.None
  assert sender.enableJudgmentStreams()
  assert not receiver.configureJudgmentReceipt(default(JudgmentReceiptPolicy)), "default policy remains inactive"
  var verification = readVerificationLimits(3, 9, int(context.contextInfo.value.epochSlots))
  verification.wireBytes = ByteLimit(65536)
  let policy = judgmentReceiptPolicy(actualClaimLimits(), receiptLimits(), verification,
    JudgmentStoreLimits(records: ElementLimit(16), bytes: ByteLimit(1000000)), ByteLimit(8000000))
  assert policy.valid and receiver.configureJudgmentReceipt(policy)
  let publisher = context.auditorAt(1).value.ed25519
  assert receiver.beginPeerConnection(publisher, networkEndpoint(loopbackAddress(false),
      sender.localPort)).error == DialError.None
  let connected = getMonoTime()+initDuration(seconds = 10)
  while receiver.peerCount != 1 or sender.peerCount != 1:
    # Both real original identities complete actual QUIC/TLS authentication before opening CE145.
    assert getMonoTime() < connected
    assert receiver.poll(getMonoTime(), now, 0)
    assert sender.poll(getMonoTime(), 0)
  let peer = sender.peerAt(0).value
  assert exchange(receiver, sender, peer, [positive], [first, second], [a.report, b.report], now,
      true) == 0
  assert receiver.receivedJudgments == 1 and receiver.retainedJudgmentCount == 1 and
      receiver.pendingForcedAudits == 0
  assert exchange(receiver, sender, peer, [a, a], [first, second], [a.report, b.report], now,
      true) == 1
  assert receiver.receivedJudgments == 2 and receiver.retainedJudgmentCount == 2 and
      receiver.pendingForcedAudits == 1
  assert receiver.pendingForcedAudit(0).originId.valid
  assert not receiver.pendingForcedAudit(0).judgment.judgmentRecord.valid
  var bad = a
  var signature = array[64, byte](bad.credentials[bad.credentialCount-1].signature)
  signature[0] = signature[0] xor 1
  bad.credentials[bad.credentialCount-1].signature = GuaranteeSignature(signature)
  discard exchange(receiver, sender, peer, [b, bad], [first, second], [a.report, b.report], now, false)
  assert receiver.receivedJudgments == 2 and receiver.retainedJudgmentCount == 2 and
      receiver.pendingForcedAudits == 1, "late original support failure publishes no judgment or forced-audit prefix"
  let secondAuditor = actualNegativeClaim(fixture, first, auditor = 2).judgmentRecord
  assert exchange(receiver, sender, peer, [secondAuditor], [first, second],
      [a.report, b.report], now, true) == 0
  assert receiver.retainedJudgmentCount == 3 and receiver.pendingForcedAudits == 2
  assert receiver.pendingForcedAudit(0).originId == receiver.pendingForcedAudit(1).originId,
      "distinct original signatures share one exact private evaluation origin"
  var hash: seq[byte] = @[]
  for octet in array[32, byte](a.report): hash.add(octet)
  let query = decodeReadRequest(ReadKind.Report, hash).value
  var requested = false
  var ticket = default(NodeRequestTicket)
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while true:
    # A received negative publisher retains independent detached CE136 serving bytes after receipt inputs and native upload claims retire.
    assert getMonoTime() < deadline
    assert receiver.poll(getMonoTime(), now, 0)
    assert sender.poll(getMonoTime(), 0)
    if not requested:
      let admitted = sender.request(peer, query, ByteLimit(65536))
      if admitted.error == NodeError.None:
        requested = true
        ticket = admitted.value
      continue
    let completed = sender.takeReply(ticket)
    if completed.error == ReadError.Unavailable: continue
    assert completed.error == ReadError.None and completed.value.bytes == reportWire(first.report)
    break
