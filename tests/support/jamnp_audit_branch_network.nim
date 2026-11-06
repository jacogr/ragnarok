# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real UP0 leaves and CE128 bytes feed current STF preparation without adopting the child.
import std/[assertions, envvars, monotimes, times, syncio, posix/posix]
import ../../src/app/[audit_branches, chain, node as application_node, options, services]
import "../../src/app/current/block/input" as current_block_input
import ../../src/chain/[genesis, provider]
import ../../src/codec/[block_codec, bounded, report_owned]
import ../../src/codec/state/[layout, safrole]
import ../../src/crypto/primitives
import ../../src/jamnp-s/[connections, node, read_stream]
import ../../src/quic/address
import ../../src/state/accumulation/current/update
import ../../src/state/store
import ./[accumulation_current_candidate_context, accumulation_current_chain_context,
    assurance_signer_context, current_application_context, jamnp_read_validation_context,
    jamnp_topology_fixture]

proc markerFor(identity: StateEdKey): byte =
  ## Find only one of the independent fixture-owned Ed25519 seeds.
  for marker in 1..32:
    var seed = default(array[32, byte])
    seed[0] = byte(marker)
    if array[32, byte](importSeed(seed).value.publicKey.value) == array[32, byte](identity):
      return byte(marker)
  0
proc branchNetworkChecks*() {.raises.} =
  ## An authenticated peer offers a genuine child. The ordinary node loop retrieves, verifies and retains it as side history.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let fixture = currentChainFixture(decodeOwnedReport(report, 2).value, available = true)
  let parent = fixture.parent.value
  let seed = initApplicationChain(fixture.currentChainSeeded).value
  let update = seed.prepareAccumulation(fixture.source, ByteLimit(100000)).value
  let child = update.currentUpdateChild
  let view = update.currentUpdateView
  let blockBytes = child.blockBody
  let topology = topologyLimits(2, 12)
  let active = decodeStateValidators(parent.lookup(chapterKey(StateChapter(8))).value.bytes,
      topology.validators).value.value
  let local = active.validatorAt(StateValidatorIndex(0)).value.ed25519
  let remote = active.validatorAt(StateValidatorIndex(1)).value.ed25519
  let localMarker = markerFor(local)
  let remoteMarker = markerFor(remote)
  assert localMarker > 0 and remoteMarker > 0
  var keyA = "audit-branch-network-a.pem"
  var certA = "audit-branch-network-a-cert.pem"
  var keyB = "audit-branch-network-b.pem"
  var certB = "audit-branch-network-b-cert.pem"
  var path = "audit-branch-network-chain.json"
  assuranceSignerFiles(keyA, certA, localMarker)
  assuranceSignerFiles(keyB, certB, remoteMarker)
  writeFile(path, currentApplicationText(parent))
  defer:
    discard posix.unlink(keyA.toCString())
    discard posix.unlink(certA.toCString())
    discard posix.unlink(keyB.toCString())
    discard posix.unlink(certB.toCString())
    discard posix.unlink(path.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], settings)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(settings, "branch network regression")
  assert owner.publishFinalized(parent.blockHash) == ViewFinalizeError.None
  var client = default(ApplicationNode)
  var server = default(NodeService)
  defer:
    client.close()
    server.close()
  let alpn = owner.nodeProtocol
  let now = StateTime(uint32(child.slot))
  assert client.open(owner, initConnectionConfig(certA, keyA, alpn), topology, now) == NodeError.None
  assert server.open(initConnectionConfig(certB, keyB, alpn), view, topology) == NodeError.None
  var verification = readVerificationLimits(2, 6, 12)
  verification.blocks = ElementLimit(1)
  let input = CurrentBlockInputLimits(blockBytes: ByteLimit(1000000),
      ancestorBytes: ByteLimit(2000000), ancestors: ElementLimit(8))
  let storage = AuditBranchLimits(branches: ElementLimit(2), bytes: ByteLimit(64000000))
  assert client.configureAuditBranchIngress(auditBranchIngressPolicy(verification, input,
      currentCandidateLimits(), storage))
  assert client.beginPeerConnection(remote, networkEndpoint(loopbackAddress(false),
      server.localPort)).error == DialError.None
  var served = 0
  let deadline = getMonoTime()+initDuration(seconds = 15)
  while owner.auditBranchCount == 0:
    # The server completes only a correctly named descending request for its actual selected leaf.
    let clock = getMonoTime()
    assert clock < deadline, "UP0 leaf triggers CE128 and full side-branch preparation"
    assert client.poll(clock, now, 0)
    assert server.poll(clock, 0)
    let incoming = server.takeRead(ReadKind.Blocks)
    if incoming.error != NodeError.None: continue
    let task = incoming.value
    let query = task.request.payload
    let hash = array[32, byte](child.blockHash)
    for index in 0..<32: assert query[index] == hash[index]
    assert query[32] == 1 and query[33] == 1
    var wire: seq[byte] = @[]
    for index in 0..<4: wire.add(byte((uint32(blockBytes.len) shr (8*index)) and 255))
    for octet in blockBytes: wire.add(octet)
    assert server.respond(task.ticket, captureReadReply(task.request, wire).value) == ReadError.None
    inc served
  assert served == 1
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      parent.blockHash)
  let side = owner.nextAuditBranch(0)
  assert array[32, byte](side.hash) == array[32, byte](child.blockHash)
