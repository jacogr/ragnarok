# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine nonempty available reports cross real original-identity TLS peers through direct retrieval and authenticated threshold fallback. No caller-created proof or evaluation capability substitutes actual verification.
import std/[assertions, monotimes, times, syncio, posix/posix]
import ../../src/app/[audit_acquisition, audit_state, services, options, node as application_node]
import ../../src/app/proof/worker
import ../../src/jamnp-s/[audit_origin, audit_context, audit_fetch, audit_registry,
  audit_evaluation, audit_recovery, availability_proof, node, connections,
  read_stream, endpoints]
import ../../src/codec/[bounded, report_owned]
import ../../src/codec/state/safrole
import ../../src/state/erasure/words
import ../../src/chain/[genesis, provider]
import ../../src/quic/address
import ../../src/crypto/primitives
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_topology_fixture,
  current_application_context, assurance_signer_context]
proc acquisitionLimits*(): AuditAcquisitionLimits =
  ## Whole round credit covers every possible original target's proof work before any peer request.
  AuditAcquisitionLimits(fetch: fetchLimits(), evaluation: evaluationLimits(),
    recovery: AuditRecoveryLimits(bytes: ByteLimit(16000000), products: FieldProductLimit(
        100000000)),
    transfer: AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(1000),
      hashBytes: ByteLimit(1000000)), bytes: ByteLimit(64000000),
    hashes: ElementLimit(20000), hashBytes: ByteLimit(20000000), requests: ElementLimit(12),
    timeoutMs: 10000, peerTimeoutMs: 500)
proc keyMarker(identity: StateEdKey): int =
  ## Independently match only test-owned original roster keys; never alter canonical state to make a TLS identity eligible.
  for marker in 1..32:
    var seed = default(array[32, byte])
    seed[0] = byte(marker)
    let actual = importSeed(seed).value.publicKey.value
    if array[32, byte](actual) == array[32, byte](identity): return marker
  return -1
proc appendMessage(wire: var seq[byte], bytes: openArray[byte]) =
  ## Test-owned actual prepared payloads fit the independently bounded E4 response layout.
  for index in 0..<4: wire.add(byte((uint32(bytes.len) shr (index*8)) and 255))
  for octet in bytes: wire.add(octet)
proc originalBundle(fixture: AuditContextFixture, target: AuditReportOrigin): OriginalAuditBundle =
  ## Select the actual computation's original prepared proof set by the complete report identity.
  for bundle in fixture.bundles:
    if array[32, byte](bundle.reportHash) == array[32, byte](
        target.originReportHash.value): return bundle
  assert false, "genuine original availability source"
  return default(OriginalAuditBundle)
proc auditAcquisitionChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Managed private evaluation is driven by real FIN-complete native responses, including four distinct authenticated original coordinates for N=9.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let target = origin.reportAt(1).value
  let bundle = fixture.originalBundle(target)
  let plan = captureAuditFetch(target, fetchLimits()).value
  let context = origin.originContext.value
  var file = "audit-acquisition-services.json"
  writeFile(file, currentApplicationText(fixture.view.bestBlock.value))
  defer: discard posix.unlink(file.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", file], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "genuine nonempty acquisition")
  assert services.configureAudits(registryLimits())
  let id = services.retainAuditOrigin(origin).value
  let direct = plan.targetAt(false, 0).value.identity
  var identities: seq[StateEdKey] = @[]
  for ordinal in 0..<5:
    # Actual prior roster positions zero through four own five different rotated shard coordinates for core one.
    identities.add(plan.targetAt(true, ordinal).value.identity)
  var duplicate = false
  for identity in identities:
    if array[32, byte](identity) == array[32, byte](direct): duplicate = true
  if not duplicate: identities.add(direct)
  var local = default(StateEdKey)
  for ordinal in 5..<context.contextInfo.value.auditors:
    # The client owns an actual original validator key distinct from every server identity.
    let candidate = context.auditorAt(ordinal).value.ed25519
    var used = false
    for identity in identities:
      if array[32, byte](candidate) == array[32, byte](identity): used = true
    if not used:
      local = candidate
      break
  assert local.keyMarker > 0 and identities.len <= 6
  var keys, certificates: seq[string] = @[]
  for index in 0..identities.len:
    # Real certificate imports use existing bounded key generation, never a private scalar injected into production state.
    let identity = if index == identities.len: local else: identities[index]
    let marker = identity.keyMarker
    assert marker > 0
    let key = "audit-acquisition-key-" & $index & ".pem"
    let certificate = "audit-acquisition-cert-" & $index & ".pem"
    assuranceSignerFiles(key, certificate, byte(marker))
    keys.add(key)
    certificates.add(certificate)
  defer:
    for index in 0..<keys.len:
      var key = keys[index]
      var certificate = certificates[index]
      discard posix.unlink(key.toCString())
      discard posix.unlink(certificate.toCString())
  let finalized = fixture.view.finalizeView(fixture.blockHash)
  assert finalized.error == ViewFinalizeError.None
  let view = finalized.value
  let geometry = topologyLimits(3, int(context.contextInfo.value.epochSlots))
  var client = default(ApplicationNode)
  var servers = default(array[6, NodeService])
  defer:
    client.close()
    for index in 0..<identities.len: servers[index].close()
  let protocol = services.nodeProtocol
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let now = context.contextInfo.value.slot
  assert client.open(services, initConnectionConfig(certificates[^1], keys[^1], protocol,
    streams = 512), geometry, now) == NodeError.None
  for index in 0..<identities.len:
    # Each physical server is pinned to its own actual roster identity, independently of the announced report.
    assert servers[index].open(initConnectionConfig(certificates[index], keys[index], protocol,
      streams = 512), view, geometry) == NodeError.None
    assert client.beginPeerConnection(identities[index], networkEndpoint(loopbackAddress(false),
      servers[index].localPort)).error == DialError.None
  let connected = getMonoTime()+initDuration(seconds = 10)
  while client.peerCount < identities.len:
    assert getMonoTime() < connected, "all original-identity audit TLS connections"
    assert client.poll(getMonoTime(), now, 0)
    for index in 0..<identities.len: assert servers[index].poll(getMonoTime(), 0)
  var offset = initDuration(milliseconds = 0)
  for scenario in 0..3:
    # Each original source remains privately retained while the source-free native controller collects direct or proven evidence.
    var limits = acquisitionLimits()
    if scenario == 1:
      # A legal maximum CE147 cap exceeds CE138's separate native ceiling; fallback must select the latter without changing the original report.
      limits.fetch.replyBytes = ByteLimit(16*1024*1024)
      limits.bytes = ByteLimit(128000000)
    assert client.beginAuditAcquisition(auditAcquisitionPolicy(limits), id, 1, getMonoTime()+offset)
    let deadline = getMonoTime()+initDuration(seconds = 10)
    var skipped = false
    var directRequests = 0
    var shardRequests = 0
    while client.auditAcquisitionBusy:
      assert getMonoTime() < deadline, "bounded genuine audit acquisition"
      let clock = getMonoTime()+offset
      assert client.poll(clock, now, 0)
      for index in 0..<identities.len:
        # Servers return only exact framed original computation bytes/proofs; the client worker independently authenticates them.
        assert servers[index].poll(clock, 0)
        let pending = servers[index].takeRead()
        if pending.error != NodeError.None: continue
        let task = pending.value
        let request = task.request
        var wire: seq[byte] = @[]
        if request.kind == ReadKind.Bundle:
          inc directRequests
          var candidate = bundle.wire
          if scenario > 0: candidate[0] = candidate[0] xor 1
          appendMessage(wire, candidate)
        else:
          assert request.kind == ReadKind.Audit
          inc shardRequests
          let payload = request.payload
          let shard = int(payload[32])+int(payload[33])*256
          let prepared = bundle.auditShards[shard]
          assert uint64(prepared.request.shard) == uint64(shard)
          if scenario == 3 and not skipped:
            # A deterministic wall-clock advance expires this exact genuinely opened request; the server withholds its FIN and no packet is accepted.
            skipped = true
            offset = initDuration(milliseconds = 600)
            continue
          var shardBytes = prepared.bundleShard
          if scenario == 2 and not skipped:
            # Damaged raw evidence is never a forged VerifiedAvailabilityTransfer; independent verification refuses it and requests the next original coordinate.
            skipped = true
            shardBytes[0] = shardBytes[0] xor 1
          appendMessage(wire, shardBytes)
          appendMessage(wire, prepared.justification)
        let reply = captureReadReply(request, wire)
        assert reply.error == ReadError.None
        assert servers[index].respond(task.ticket, reply.value) == ReadError.None
    assert client.auditAcquisitionPhase == AuditAcquisitionPhase.Complete
    assert client.acquiredAuditInfo.positive, "actual full private reproduction follows authenticated native retrieval"
    assert directRequests == 1
    if scenario == 0:
      assert shardRequests == 0, "a genuinely reproduced direct bundle needs no shard requests"
    elif scenario == 1:
      assert shardRequests == 4, "four original rotated coordinates reconstruct the real bundle"
    else:
      assert skipped and shardRequests == 5, "a damaged or timed-out peer cannot invalidate the report or strand the next original coordinate"
  assert client.beginAuditAcquisition(auditAcquisitionPolicy(acquisitionLimits()), id, 1,
      getMonoTime())
  assert client.poll(getMonoTime()+offset, now, 0), "actual private intrinsic-source probe"
  client.cancelAuditAcquisition()
  let cancelled = getMonoTime()+initDuration(seconds = 10)
  while client.auditAcquisitionBusy:
    assert getMonoTime() < cancelled
    assert client.poll(getMonoTime()+offset, now, 0)
  assert client.auditAcquisitionPhase == AuditAcquisitionPhase.Cancelled, "cancelled worker output cannot complete or sign an audit"
