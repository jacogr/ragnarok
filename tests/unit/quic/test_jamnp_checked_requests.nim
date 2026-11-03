# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_checked_requests_arc_release"}

## Real TLS checked acquisition retains exact worker leases through cancellation, buffering and shutdown.
import std/[assertions, envvars, syncio, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/proof/worker
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, read_validation, canonical_read]
import ../../../src/chain/[genesis, parameters, provider]
import ../../../src/codec/[header, bounded]
import ../../../src/codec/state/safrole
import ../../../src/state/[store, range_proof]
import ../../../src/rpc/server
import ../../../src/lib/json/writer as json_writer
import ../../support/[jamnp_topology_fixture, jamnp_node_probe, jamnp_read_validation_context, arc_evidence]
proc hex(input: openArray[byte]): string =
  ## Independent canonical chainspec encoding does not use a production configuration serializer.
  result = ""
  for octet in input: result.add(toHex(int(octet), 2).toLowerAscii())
proc chainText(saved: BlockSnapshot): string =
  ## Retain the complete fixture's original opaque chapters and exact header/profile.
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(saved.header, wire).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<saved.keyCount:
    let key = saved.keyAt(StateKeyIndex(index))
    entries.add(hex(array[31, byte](key)), json(hex(saved.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hex(topologySettings().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])
proc step(host: var ApplicationNode, services: var Services, probe: var NodeProbe) {.raises.} =
  ## One bounded actor turn keeps unrelated sockets responsive while Services owns a CPU lease.
  assert host.poll(getMonoTime(), StateTime(7), 0)
  probe.poll()
  services.tick(uint32(host.peerCount))
proc until(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    ticket: CheckedRequestTicket, phase: CheckedRequestPhase) {.raises.} =
  ## Phase observations are scalar and do not touch any worker-owned input/result graph.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while host.checkedPhase(ticket) != phase:
    assert getMonoTime() < deadline, "checked lifecycle reaches its bounded expected phase"
    step(host, services, probe)
proc done(services: var Services, probe: var NodeProbe) =
  ## Withhold host collection deliberately so Done must retain the canonical/RPC lease.
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    probe.poll()
proc connect(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    protocol: string, hash: BlockHash) {.raises.} =
  ## Repeated connections use fresh peer/native generations and an independent literal UP0 handshake.
  probe.open(host.localPort, protocol)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    step(host, services, probe)
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  let persistent = probe.issue(hello, persistent = true)
  while true:
    assert getMonoTime() < deadline
    step(host, services, probe)
    if probe.bytes(persistent).len > 0 and host.peerCount > 0:
      let peer = host.peerAt(0)
      if peer.error == NodeError.None and host.source(peer.value).error == NodeError.None:
        break # TLS completion and first response bytes alone do not prove host-side UP0 readiness.
proc cancellationRound(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    peer: NodePeer, request: ReadRequest, policy: ReadVerificationLimits) {.raises.} =
  ## Immediate cancellation removes the queued native intent before any raw peer stream can open.
  let started = host.requestChecked(peer, request, policy)
  assert started.error == NodeError.None
  assert host.cancelChecked(started.value)
  assert host.takeChecked(started.value).kind == CheckedCompletionKind.Cancelled
  assert not host.checkedLive(started.value)
  step(host, services, probe) # Drain bounded queue tombstones before admitting the next generation.
proc main() {.raises.} =
  ## Full Services source and literal remote replies exercise complete acquisition-to-verification ownership.
  let saved = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  writeFile("checked-requests-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", "checked-requests-chain.json",
      "--with-state"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var foreignHost = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    foreignHost.close()
    host.close()
    services.close() # Every callback and exact worker ticket retires before its borrowed Services address.
  assert services.start(options, "checked requests")
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      protocol, streams = 512)
  let selected = services.chainView.bestBlock.value
  let hash = selected.blockHash
  let expectedRoot = array[32, byte](selected.stateRoot)
  let expectedKeys = selected.keyCount
  let policy = readVerificationLimits()
  let request = readStateRequest(hash)
  let wire = serveCanonicalRead(services.chainView, request).value.bytes
  var requestWire = @[129'u8, 98, 0, 0, 0]
  for octet in request.payload: requestWire.add(octet)
  var blockWire = @[128'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): blockWire.add(octet)
  blockWire.add(1)
  for index in 0..<4: blockWire.add(0)
  let blockRequest = decodeReadRequest(ReadKind.Blocks, blockWire.toOpenArray(5,
      blockWire.len-1)).value
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  assert foreignHost.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, protocol, hash)
  let peer = host.peerAt(0).value
  probe.expectRead(requestWire, wire)
  let emptyTicket = default(CheckedRequestTicket)
  assert host.takeChecked(emptyTicket).kind == CheckedCompletionKind.Uninitialized
  assert not host.cancelChecked(emptyTicket)
  var invalidLimits = policy
  invalidLimits.wireBytes = ByteLimit(MaxReadReplyBytes+1)
  assert host.requestChecked(peer, request, invalidLimits).error == NodeError.InvalidConfig
  invalidLimits.wireBytes = ByteLimit(7)
  assert host.requestChecked(peer, request, invalidLimits).error == NodeError.InvalidConfig
  let foreign = services.beginNetworkRead(blockRequest)
  assert foreign.error == StateProofAdmissionError.None
  let buffered = host.requestChecked(peer, request, policy)
  assert buffered.error == NodeError.None
  assert host.takeChecked(buffered.value).kind == CheckedCompletionKind.Pending
  assert host.requestChecked(peer, request, policy).error == NodeError.Unavailable
  assert not foreignHost.cancelChecked(buffered.value)
  assert foreignHost.takeChecked(buffered.value).kind == CheckedCompletionKind.Uninitialized
  until(host, services, probe, buffered.value, CheckedRequestPhase.Waiting)
  done(services, probe)
  assert services.stateProofActive and services.rpc.chainPaused
  assert host.cancelChecked(buffered.value)
  assert host.takeChecked(buffered.value).kind == CheckedCompletionKind.Cancelled
  assert services.stateProofActive and services.rpc.chainPaused, "buffered cancellation leaves foreign Done leased"
  let cancelled = host.requestChecked(peer, request, policy)
  assert cancelled.error == NodeError.None
  until(host, services, probe, cancelled.value, CheckedRequestPhase.Waiting)
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  until(host, services, probe, cancelled.value, CheckedRequestPhase.Verifying)
  done(services, probe)
  assert host.cancelChecked(cancelled.value)
  assert services.stateProofActive and services.rpc.chainPaused, "cancel after Done cannot retire an admitted exact lease"
  assert host.takeChecked(cancelled.value).kind == CheckedCompletionKind.Pending
  until(host, services, probe, cancelled.value, CheckedRequestPhase.Done)
  assert host.takeChecked(cancelled.value).kind == CheckedCompletionKind.Cancelled
  assert not services.stateProofActive and not services.rpc.chainPaused
  let barrier = services.beginNetworkRead(blockRequest)
  assert barrier.error == StateProofAdmissionError.None
  let successful = host.requestChecked(peer, request, policy)
  assert successful.error == NodeError.None
  until(host, services, probe, successful.value, CheckedRequestPhase.Waiting)
  let inbound = probe.issue(blockWire)
  for iteration in 0..<20: step(host, services, probe) # Receive the independent inbound read while the foreign gate remains held.
  done(services, probe)
  discard services.collectStateProof(barrier.value)
  step(host, services, probe)
  assert host.checkedPhase(successful.value) == CheckedRequestPhase.Waiting,
    "an inbound responder gets the first turn after the previous checked verification"
  done(services, probe)
  until(host, services, probe, successful.value, CheckedRequestPhase.Verifying)
  until(host, services, probe, successful.value, CheckedRequestPhase.Done)
  let checked = host.takeChecked(successful.value)
  assert checked.kind == CheckedCompletionKind.Completed
  assert checked.value.error == ReadVerificationError.None
  assert checked.value.value.statePage.complete and checked.value.value.statePage.len == expectedKeys
  assert array[32, byte](checked.value.value.statePage.root) == expectedRoot
  assert host.takeChecked(successful.value).kind == CheckedCompletionKind.Uninitialized
  let finishInbound = getMonoTime()+initDuration(seconds = 5)
  while not probe.flows[inbound].receivedFin:
    assert getMonoTime() < finishInbound
    step(host, services, probe)
  assert probe.bytes(inbound) == @[0'u8, 0, 0, 0]
  var corrupt: seq[byte] = @[]
  for octet in wire: corrupt.add(octet)
  corrupt[corrupt.len-1] = corrupt[corrupt.len-1] xor 1
  probe.expectRead(requestWire, corrupt)
  let invalid = host.requestChecked(peer, request, policy)
  assert invalid.error == NodeError.None
  until(host, services, probe, invalid.value, CheckedRequestPhase.Done)
  let refused = host.takeChecked(invalid.value)
  assert refused.kind == CheckedCompletionKind.Completed
  assert refused.value.error == ReadVerificationError.StateFailure
  assert not services.stateProofActive and not services.rpc.chainPaused
  let unknown = readStateRequest(default(BlockHash))
  var unknownWire = @[129'u8, 98, 0, 0, 0]
  for octet in unknown.payload: unknownWire.add(octet)
  probe.expectRead(unknownWire, wire)
  let unavailable = host.requestChecked(peer, unknown, policy)
  assert unavailable.error == NodeError.None
  until(host, services, probe, unavailable.value, CheckedRequestPhase.Done)
  let absent = host.takeChecked(unavailable.value)
  assert absent.kind == CheckedCompletionKind.AdmissionFailure
  assert absent.admissionError == ReadVerificationError.NoSource
  probe.expectRead(requestWire, @[0'u8, 0, 0, 0, 0, 0, 0, 0, 1])
  let malformed = host.requestChecked(peer, request, policy)
  assert malformed.error == NodeError.None
  until(host, services, probe, malformed.value, CheckedRequestPhase.Done)
  let failed = host.takeChecked(malformed.value)
  assert failed.kind == CheckedCompletionKind.NetworkFailure and failed.networkError != ReadError.None
  probe.expectRead(requestWire, wire)
  for iteration in 0..<5: cancellationRound(host, services, probe, peer, request, policy)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cancellationRound(host, services, probe, peer, request, policy)
  let after = getOccupiedMem()
  assert before == after, "checked ticket/result/buffer owners retire after each cancelled generation"
  recordArcRelease("jamnp_checked_requests", 1000, before, after)
  assert not host.cancelChecked(successful.value), "collected generations cannot cancel later work"
  let interrupted = host.requestChecked(peer, request, policy)
  assert interrupted.error == NodeError.None
  until(host, services, probe, interrupted.value, CheckedRequestPhase.Verifying)
  services.stopStateProofs() # An external joined stop invalidates the exact checked worker generation.
  let replacement = services.beginNetworkRead(blockRequest)
  assert replacement.error == StateProofAdmissionError.None
  done(services, probe)
  step(host, services, probe)
  assert host.takeChecked(interrupted.value).kind == CheckedCompletionKind.Interrupted
  assert services.stateProofActive and services.rpc.chainPaused,
    "an interrupted checked ticket cannot retire the replacement foreign Done lease"
  assert services.collectStateProof(replacement.value).kind ==
      ProofWorkerCompletionKind.ReadCompleted
  let joining = host.requestChecked(peer, request, policy)
  assert joining.error == NodeError.None
  until(host, services, probe, joining.value, CheckedRequestPhase.Verifying)
  done(services, probe)
  host.close()
  assert not services.stateProofActive and not services.rpc.chainPaused
  assert services.stateProofPhase == ProofWorkerPhase.Idle
  probe.close()
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  assert not host.checkedLive(joining.value), "reopening the same address creates a fresh ticket namespace"
  connect(host, services, probe, protocol, hash)
  let nextPeer = host.peerAt(0).value
  probe.expectRead(requestWire, wire)
  let foreignClose = services.beginNetworkRead(blockRequest)
  assert foreignClose.error == StateProofAdmissionError.None
  let waiting = host.requestChecked(nextPeer, request, policy)
  assert waiting.error == NodeError.None
  until(host, services, probe, waiting.value, CheckedRequestPhase.Waiting)
  host.close()
  assert services.stateProofActive and services.rpc.chainPaused, "buffered host shutdown cannot join a foreign worker"
  done(services, probe)
  discard services.collectStateProof(foreignClose.value)
  probe.close()
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, protocol, hash)
  probe.expectRead(requestWire, wire)
  let foreignTimeout = services.beginNetworkRead(blockRequest)
  assert foreignTimeout.error == StateProofAdmissionError.None
  let expiring = host.requestChecked(host.peerAt(0).value, request, policy)
  assert expiring.error == NodeError.None
  until(host, services, probe, expiring.value, CheckedRequestPhase.Waiting)
  assert host.poll(getMonoTime()+initDuration(seconds = 121), StateTime(7), 0)
  assert host.takeChecked(expiring.value).kind == CheckedCompletionKind.TimedOut
  assert services.stateProofActive and services.rpc.chainPaused, "deadline expiry leaves foreign work leased"
  host.close()
  done(services, probe)
  discard services.collectStateProof(foreignTimeout.value)
  assert checked.value.value.statePage.len == expectedKeys, "collected immutable proof evidence outlives joined host shutdown"
  echo "jamnp checked requests: bounded TLS acquisition and exact verification lifetime passed"
try:
  main()
except:
  quit 2 # Native/setup exceptions cannot substitute for checked-response and cleanup evidence.
