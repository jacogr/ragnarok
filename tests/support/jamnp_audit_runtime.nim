# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real ordinary application nodes authenticate CE144 against genuinely adopted current blocks; default refusal, duplicate retention, failed proofs and foreign worker retirement preserve exact native and managed ownership.
import std/[assertions, monotimes, times, posix/posix]
import ../../src/app/[services, options, node as application_node, audit_distribution]
import ../../src/app/proof/[worker, work_submission]
import ../../src/jamnp-s/[audit_context, audit_receipt, audit_validation, audits,
  node as node_streams,
  connections, endpoints, read_stream, read_client]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/state/safrole
import ../../src/crypto/primitives
import ../../src/bandersnatch/bandersnatch
import ../../src/quic/address
import ./[assurance_signer_context, jamnp_topology_fixture]
proc marker(context: AuditContext, skip: int): int =
  ## Find actual private test seeds in the original roster; never modify that roster to suit TLS.
  for candidate in 1..32:
    if candidate == skip: continue
    var seed = default(array[32, byte])
    seed[0] = byte(candidate)
    let owned = importSeed(seed).value
    let key = owned.publicKey.value
    for ordinal in 0..<context.contextInfo.value.auditors:
      if array[32, byte](key) == array[32, byte](context.auditorAt(ordinal).value.ed25519):
        return candidate
  return -1
proc pump(a, b: var ApplicationNode, now: StateTime) {.raises.} =
  ## Production foreground polling alone selects, verifies, collects, retains and acknowledges an upload.
  assert a.poll(getMonoTime(), now, 0), "audit sender loop"
  assert b.poll(getMonoTime(), now, 0), "audit receiver loop"
proc exchange(a, b: var ApplicationNode, target: NodePeer, wire: seq[byte], now: StateTime,
    success: bool) {.raises.} =
  ## Physical stream retirement precedes slot reuse; only the exact live request's bare response FIN grants transport completion.
  let request = decodeReadRequest(ReadKind.AuditAnnouncement, wire).value
  let deadline = getMonoTime()+initDuration(seconds = 10)
  var ticket = default(NodeRequestTicket)
  while true:
    let admitted = a.request(target, request, ByteLimit(0))
    if admitted.error == NodeError.None:
      ticket = admitted.value
      break
    assert admitted.error in [NodeError.Unavailable, NodeError.LimitExceeded], "bounded audit upload admission"
    assert getMonoTime() < deadline, "audit physical admission deadline"
    pump(a, b, now)
  while true:
    pump(a, b, now)
    let reply = a.takeReply(ticket)
    if reply.error != ReadError.Unavailable:
      if success: assert reply.error == ReadError.None and reply.value.bytes.len == 0, "CE144 exact bare FIN acknowledgment"
      else: assert reply.error != ReadError.None, "refused audit proof cannot acknowledge"
      return
    assert getMonoTime() < deadline, "audit response FIN deadline"
proc auditReceiptRuntime*(receiver: var Services, settings: Options, context: AuditContext,
    contextLimits: AuditContextLimits) {.raises.} =
  ## Complete current publication supplies the receiver's real body/history; a separately decoded complete parent supplies only the sender's genuine TLS role.
  let info = context.contextInfo.value
  let first = context.marker(-1)
  let second = context.marker(first)
  assert first > 0 and second > 0, "two original roster identities have test-owned private keys"
  var keyA = "audit-runtime-a-key.pem"
  var certA = "audit-runtime-a-cert.pem"
  var keyB = "audit-runtime-b-key.pem"
  var certB = "audit-runtime-b-cert.pem"
  assuranceSignerFiles(keyA, certA, byte(first))
  assuranceSignerFiles(keyB, certB, byte(second))
  defer:
    discard posix.unlink(keyA.toCString())
    discard posix.unlink(certA.toCString())
    discard posix.unlink(keyB.toCString())
    discard posix.unlink(certB.toCString())
  var sender = default(Services)
  defer: sender.close()
  assert sender.start(settings, "audit native sender"), "independent complete sender seed"
  assert receiver.publishFinalized(receiver.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  assert sender.publishFinalized(sender.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let geometry = topologyLimits(int(uint64(info.maximumCores)), int(info.epochSlots))
  let now = info.slot
  var a = default(ApplicationNode)
  var b = default(ApplicationNode)
  defer:
    b.close()
    a.close() # Both callback owners retire before either borrowed Services instance.
  assert a.open(sender, initConnectionConfig(certA, keyA, sender.nodeProtocol, streams = 512),
      geometry, now) == NodeError.None
  assert b.open(receiver, initConnectionConfig(certB, keyB, receiver.nodeProtocol, streams = 512),
      geometry, now) == NodeError.None
  let limits = AuditReceiptLimits(message: AuditLimits(validators: ValidatorCount(uint64(
      info.auditors)),
    cores: info.maximumCores, bytes: ByteLimit(133), records: ElementLimit(1)),
        context: contextLimits,
    proof: AuditProofLimits(proofs: ElementLimit(1), hashes: ElementLimit(2), bytes: ByteLimit(
        4096), hashBytes: ByteLimit(72)),
    retainedBytes: ByteLimit(uint64(contextLimits.outputBytes)+1024))
  let policy = auditReceiptPolicy(limits, 1, ByteLimit(info.retainedBytes+1024), timeoutMs = 5000)
  assert not a.configureAuditReceipt(default(AuditReceiptPolicy)), "default audit policy disabled"
  assert a.configureAuditReceipt(policy), "explicit outgoing audit selector"
  var identitySeed = default(array[32, byte])
  identitySeed[0] = byte(second)
  let identity = StateEdKey(array[32, byte](importSeed(identitySeed).value.publicKey.value))
  assert a.beginPeerConnection(identity, networkEndpoint(loopbackAddress(false),
      b.localPort)).error == DialError.None
  let connected = getMonoTime()+initDuration(seconds = 10)
  while a.peerCount == 0 or b.peerCount == 0:
    assert getMonoTime() < connected, "real audit TLS connection"
    pump(a, b, now)
  let target = a.peerAt(0).value
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let signing = importScalar(scalar).value
  defer: signing.close()
  let public = signing.publicKey.value
  var ordinal = -1
  for index in 0..<info.auditors:
    if array[32, byte](context.auditorAt(index).value.bandersnatch) == array[32, byte](
        public): ordinal = index
  assert ordinal >= 0, "actual prior auditor owns the test Thin key"
  var transcript: seq[byte] = @[106'u8, 97, 109, 95, 97, 117, 100, 105, 116]
  for octet in info.entropy: transcript.add(octet)
  let proof = sign(signing, transcript, []).value
  var wire: seq[byte] = @[]
  for octet in array[32, byte](info.blockHash): wire.add(octet)
  wire.add(byte(ordinal and 255))
  wire.add(byte((ordinal shr 8) and 255))
  wire.add(0)
  for octet in array[96, byte](proof): wire.add(octet)
  exchange(a, b, target, wire, now, false)
  assert b.pendingAuditAnnouncements == 0, "omitted receiver policy never retains a declaration"
  assert b.configureAuditReceipt(policy) and not b.configureAuditReceipt(policy), "explicit once-only managed audit activation"
  exchange(a, b, target, wire, now, true)
  assert b.receivedAuditAnnouncements == 1 and b.pendingAuditAnnouncements == 1, "actual current body and original VRF proof qualify before FIN"
  let retained = b.pendingAuditAnnouncement(0)
  assert retained.announcementInfo.value.selected == 0, "genuine empty children invent no report obligations"
  exchange(a, b, target, wire, now, true)
  assert b.receivedAuditAnnouncements == 2 and b.pendingAuditAnnouncements == 1, "authenticated retransmission does not multiply intent"
  var damaged = wire
  damaged[damaged.len-1] = damaged[damaged.len-1] xor 1
  exchange(a, b, target, damaged, now, false)
  assert b.receivedAuditAnnouncements == 2 and b.pendingAuditAnnouncements == 1, "late proof failure retains no accepted prefix or acknowledgment"
  let foreign = receiver.beginAuditPlanning(info.blockHash, contextLimits)
  assert foreign.error == StateProofAdmissionError.None, "independent actual-source worker lease"
  let done = getMonoTime()+initDuration(seconds = 10)
  while receiver.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < done, "foreign audit completion deadline"
    pump(a, b, now)
  b.close()
  assert not receiver.stateProofAvailable, "dispatcher close cannot retire a foreign Done lease"
  let completed = receiver.collectStateProof(foreign.value)
  assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted and receiver.stateProofAvailable, "only exact foreign collection resumes its canonical lease"
