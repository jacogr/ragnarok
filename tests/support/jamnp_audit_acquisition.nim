# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine nonempty available reports cross real original-identity TLS peers through direct retrieval and authenticated threshold fallback. No caller-created proof or evaluation capability substitutes actual verification.
import std/[assertions, monotimes, times, syncio, posix/posix]
import ../../src/app/[audit_acquisition, audit_state, services, options, node as application_node,
    forced_audit, judgment_distribution, initial_audit, audit_distribution]
import ../../src/app/proof/ticket_production
import ../../src/jamnp-s/audit_validation
import ./jamnp_audit_validation
import ../../src/app/proof/worker
import ../../src/app/chain as application_chain
import ../../src/app/disk/chain as disk_chain
import ../../src/chain/parameters
import ../../src/state/disk_store
import ../../src/storage/[record_codec, database_identity]
import ../../src/storage/file/repository
import ../../src/storage/node/repository as node_repository
import ../../src/storage/node/records
import ../../src/codec/state/trie
import ../../src/jamnp-s/[audit_origin, audit_context, audit_fetch, audit_registry,
  audit_evaluation, audit_recovery, availability_proof, node, connections,
  read_stream, endpoints, audits, judgment_claim, judgment_receipt, judgment_store,
  judgment_gossip, audit_publication]
import ../../src/codec/[bounded, report_owned, owned, disputes]
import ../../src/codec/state/safrole
import ../../src/state/erasure/words
import ../../src/chain/[genesis, provider]
import ../../src/quic/address
import ../../src/crypto/primitives
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_topology_fixture,
  current_application_context, assurance_signer_context, jamnp_judgment_support,
  jamnp_judgment_receipt, jamnp_audit_participation, jamnp_read_validation_context]
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
  let initialPolicy = initialAuditPolicy(auditLimits(), AuditProofLimits(
      proofs: ElementLimit(2), hashes: ElementLimit(2), bytes: ByteLimit(4096),
      hashBytes: ByteLimit(72)), origin = auditOriginLimits())
  assert not client.configureInitialAudits(initialPolicy), "CE144 starts disabled"
  let incomingPolicy = auditReceiptPolicy(jamnp_audit_validation.receiptLimits(auditLimits()),
      8, ByteLimit(32000000))
  assert client.configureAuditReceipt(incomingPolicy)
  assert not client.configureInitialAudits(initialPolicy), "CE144 receipt grants no local signer"
  assert services.configureTicketSignerSeed(default(array[32, byte])).error ==
      TicketSignerError.None
  assert not client.configureInitialAudits(initialPolicy), "local declarations require a judgment pipeline"
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
  assert client.initialAuditDeclarationCount == 0,
      "checkpoint without an authenticated body cannot declare local work"
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

  # A genuine negative claim for the actual valid report now drives the ordinary node loop.
  let guarantee = target.originGuarantee.value
  let claim = actualNegativeClaim(fixture, guarantee).judgmentRecord
  let message = actualClaimLimits().message
  let uploadWire = encodeJudgments([claim], message).value
  let upload = decodeReadRequest(ReadKind.Judgment, uploadWire).value
  var report = newSeq[byte](guarantee.report.ownedReportInfo.value.consumed)
  assert guarantee.report.encodeOwnedReport(report).error == OwnershipError.None
  assert services.configureAuditSigner(certificates[^1], keys[^1], local).error ==
      WorkSigningSetupError.None
  var verification = readVerificationLimits(3, 9, int(context.contextInfo.value.epochSlots))
  verification.wireBytes = ByteLimit(65536)
  let store = JudgmentStoreLimits(records: ElementLimit(16), bytes: ByteLimit(1000000))
  let receipt = judgmentReceiptPolicy(actualClaimLimits(), receiptLimits(), verification,
      store, ByteLimit(8000000))
  assert client.configureJudgmentReceipt(receipt)
  var forcedLimits = acquisitionLimits()
  forcedLimits.requests = ElementLimit(64)
  forcedLimits.hashes = ElementLimit(64000)
  forcedLimits.hashBytes = ByteLimit(64000000)
  let gossip = judgmentGossipPolicy(message, 4, ByteLimit(8000000), dialsPerRecord = 0)
  let publication = AuditPublicationLimits(wireBytes: ByteLimit(65536),
      workspaceBytes: ByteLimit(1000000))
  let forced = forcedAuditPolicy(auditAcquisitionPolicy(forcedLimits), participationLimits(),
      publication, gossip)
  assert client.configureForcedAudits(forced)
  assert client.configureInitialAudits(initialPolicy) and not client.configureInitialAudits(initialPolicy)
  for index in 0..<identities.len:
    assert servers[index].enableJudgmentStreams()
  var sent = false
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while client.retainedJudgmentCount < 2:
    assert getMonoTime() < deadline, "negative receipt drives acquisition and original-key publication"
    let clock = getMonoTime()+offset
    assert client.poll(clock, now, 0)
    for index in 0..<identities.len:
      assert servers[index].poll(clock, 0)
      if index == 0 and not sent:
        let admitted = servers[index].request(servers[index].peerAt(0).value, upload, ByteLimit(0))
        sent = admitted.error == NodeError.None
      let incoming = servers[index].takeRead()
      if incoming.error != NodeError.None: continue
      let task = incoming.value
      var response: seq[byte] = @[]
      case task.request.kind
      of ReadKind.Report:
        appendMessage(response, report)
      of ReadKind.Bundle:
        appendMessage(response, bundle.wire)
      of ReadKind.Judgment:
        discard # Judgment acknowledgment is a bare FIN.
      else:
        assert false, "valid direct bundle requires no recovery request"
      let framed = captureReadReply(task.request, response)
      assert framed.error == ReadError.None
      assert servers[index].respond(task.ticket, framed.value) == ReadError.None
  let produced = client.retainedJudgmentAt(1).judgmentRecord
  assert produced.valid and uint32(produced.epoch) == uint32(claim.epoch)
  assert array[32, byte](produced.report) == array[32, byte](claim.report)
  let member = context.auditorAt(int(uint16(produced.validator))).value
  assert array[32, byte](member.ed25519) == array[32, byte](local)
  var transcript: seq[byte] = @[]
  for character in "jam_valid": transcript.add(byte(ord(character)))
  for octet in array[32, byte](produced.report): transcript.add(octet)
  assert verify(EdPublicKey(array[32, byte](local)),
      EdSignature(array[64, byte](produced.signature)), transcript)

proc initializeAuditDisk(view: ChainView, database: string) =
  ## Restore real retained maps and body through the same startup path as a deployed disk-backed node.
  let first = view.retainedBlockAt(RetainedBlockIndex(0)).value
  var identity: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": identity.add(byte(character))
  for octet in array[32, byte](first.blockHash): identity.add(octet)
  for octet in array[32, byte](first.stateRoot): identity.add(octet)
  for octet in first.chainParameters.encodeParameters: identity.add(octet)
  let digest = blake2b256(identity).value
  let policy = genesisStoreLimits()
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(1000000), valueBytes: ByteLimit(4000000)),
    encoded: ByteLimit(32000000)), records: ElementLimit(2000000),
    valueBytes: ByteLimit(64000000)), bytes: ByteLimit(128000000),
    contextBytes: ByteLimit(4000000))
  var disk = default(DiskStateStore)
  let initialized = initializeDiskChain(disk, database,
      StorageChainId(array[32, byte](digest)), initApplicationChain(view).value, limits)
  assert initialized.error == DiskChainError.None
  discard disk.close()
proc declaredAuditChecks*(fixture: AuditContextFixture) {.raises.} =
  ## A normal validator tick discovers the matching key, declares, recovers the two selected reports and publishes exact original-position judgments.
  let view = fixture.view.finalizeView(fixture.blockHash).value
  let origin = captureAuditOrigin(view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let context = origin.originContext.value
  let local = context.auditorAt(8).value.ed25519
  let file = "declared-audit-chain.json"
  var database = "declared-audit-state.db"
  var chainPath = file
  writeFile(file, currentApplicationText(view.retainedBlockAt(RetainedBlockIndex(0)).value))
  defer:
    discard posix.unlink(chainPath.toCString())
    discard posix.unlink(database.toCString())
  initializeAuditDisk(view, database)
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", file,
      "--state-storage", "disk", "--state-db", database], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "declared audit from retained body")
  assert services.chainView.bestBlock.value.hasBlockBody
  assert services.configureAudits(registryLimits())
  let geometry = topologyLimits(3, 12)
  let now = context.contextInfo.value.slot
  var keys, certificates: seq[string] = @[]
  for ordinal in 0..<9:
    # All eight other original positions use independent real TLS certificates.
    let key = "declared-audit-key-" & $ordinal & ".pem"
    let certificate = "declared-audit-cert-" & $ordinal & ".pem"
    let marker = context.auditorAt(ordinal).value.ed25519.keyMarker
    assert marker > 0
    assuranceSignerFiles(key, certificate, byte(marker))
    keys.add(key)
    certificates.add(certificate)
  defer:
    for ordinal in 0..<keys.len:
      var key = keys[ordinal]
      var certificate = certificates[ordinal]
      discard posix.unlink(key.toCString())
      discard posix.unlink(certificate.toCString())
  var client = default(ApplicationNode)
  var peers = default(array[8, NodeService])
  defer:
    client.close()
    for index in 0..<peers.len: peers[index].close()
  let selectedAlpn = services.nodeProtocol
  assert client.open(services, initConnectionConfig(certificates[8], keys[8], selectedAlpn,
      streams = 512), geometry, now) == NodeError.None
  for ordinal in 0..<peers.len:
    # Pin each dial to the actual original recipient identity.
    let identity = context.auditorAt(ordinal).value.ed25519
    assert peers[ordinal].open(initConnectionConfig(certificates[ordinal], keys[ordinal],
        selectedAlpn, streams = 512), view, geometry) == NodeError.None
    assert peers[ordinal].enableAuditStreams() and peers[ordinal].enableJudgmentStreams()
    assert client.beginPeerConnection(identity, networkEndpoint(loopbackAddress(false),
        peers[ordinal].localPort)).error == DialError.None
  let connected = getMonoTime()+initDuration(seconds = 10)
  while client.peerCount < peers.len:
    # Establish all physical connections before enabling the declaration policy.
    let clock = getMonoTime()
    assert clock < connected and client.poll(clock, now, 0)
    for ordinal in 0..<peers.len: assert peers[ordinal].poll(clock, 0)
  assert services.configureTicketSignerSeed(default(array[32, byte])).error ==
      TicketSignerError.None
  assert services.configureAuditSigner(certificates[8], keys[8], local).error ==
      WorkSigningSetupError.None
  let message = actualClaimLimits().message
  var verification = readVerificationLimits(3, 9, 12)
  verification.wireBytes = ByteLimit(65536)
  let receipt = judgmentReceiptPolicy(actualClaimLimits(), receiptLimits(), verification,
      JudgmentStoreLimits(records: ElementLimit(16), bytes: ByteLimit(1000000)), ByteLimit(8000000))
  assert client.configureJudgmentReceipt(receipt)
  let gossip = judgmentGossipPolicy(message, 4, ByteLimit(8000000), dialsPerRecord = 0)
  let publication = AuditPublicationLimits(wireBytes: ByteLimit(65536),
      workspaceBytes: ByteLimit(1000000))
  assert client.configureForcedAudits(forcedAuditPolicy(auditAcquisitionPolicy(acquisitionLimits()),
      participationLimits(), publication, gossip))
  assert client.configureAuditReceipt(auditReceiptPolicy(
      jamnp_audit_validation.receiptLimits(auditLimits()), 8, ByteLimit(32000000)))
  let proof = AuditProofLimits(proofs: ElementLimit(2), hashes: ElementLimit(2),
      bytes: ByteLimit(4096), hashBytes: ByteLimit(72))
  assert client.configureInitialAudits(initialAuditPolicy(auditLimits(), proof, auditOriginLimits()))
  var announced = default(array[8, bool])
  var fetched = 0
  let deadline = getMonoTime()+initDuration(seconds = 15)
  while client.retainedJudgmentCount < 2:
    # Transport peers return only genuine bundle bytes addressed by the original erasure commitment.
    let clock = getMonoTime()
    assert clock < deadline, "declaration produces two managed judgments"
    assert client.poll(clock, now, 0)
    for ordinal in 0..<peers.len:
      assert peers[ordinal].poll(clock, 0)
      let incoming = peers[ordinal].takeRead()
      if incoming.error != NodeError.None: continue
      let task = incoming.value
      var wire: seq[byte] = @[]
      case task.request.kind
      of ReadKind.AuditAnnouncement:
        assert not announced[ordinal]
        let batch = decodeAnnouncements(task.request.payload, message).value
        let checked = qualifyInitialAudit(context, batch.announcementAt(0).value, proof).value
        assert checked.announcementInfo.value.selected == 2 and
            uint16(checked.announcementInfo.value.validator) == 8
        announced[ordinal] = true
      of ReadKind.Bundle:
        for didReceive in announced: assert didReceive, "declaration precedes execution"
        var found = false
        let request = task.request.payload
        for index in 0..<2:
          # Identify the original committed erasure root before selecting any bundle bytes.
          let target = origin.reportAt(index).value
          let original = fixture.originalBundle(target)
          let root = original.auditShards[0].request.root.bytes
          if request == @root:
            appendMessage(wire, original.wire)
            found = true
        assert found
        inc fetched
      of ReadKind.Judgment:
        discard # A judgment upload has the same bare acknowledgment framing.
      else:
        assert false, "the connected valid bundle servers need no fallback"
      assert peers[ordinal].respond(task.ticket, captureReadReply(task.request, wire).value) ==
          ReadError.None
  assert client.initialAuditDeclarationCount == 1 and fetched == 2
  for ordinal in 0..<2:
    # Independent original Ed25519 transcripts verify both report judgments at the declared position.
    let judgment = client.retainedJudgmentAt(ordinal).judgmentRecord
    assert judgment.valid and uint16(judgment.validator) == 8
    assert array[32, byte](judgment.report) == array[32, byte](context.auditReportHash(ordinal).value)
    var transcript: seq[byte] = @[]
    for octet in "jam_valid": transcript.add(byte(octet))
    for octet in array[32, byte](judgment.report): transcript.add(octet)
    assert verify(EdPublicKey(array[32, byte](local)),
        EdSignature(array[64, byte](judgment.signature)), transcript)
