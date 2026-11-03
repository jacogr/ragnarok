# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_node_service_arc_release"}

## Stable full-state node owner: explicit finality, native factory failure and retirement lifetimes.
import std/[assertions, syncio, envvars, monotimes, times]
import ../../support/[jamnp_topology_fixture, arc_evidence, jamnp_node_probe, jamnp_connection_pair]
import ../../../src/jamnp-s/[node, connections, read_stream, identity, admission]
import ../../../src/chain/[genesis, provider]
import ../../../src/quic/[transport, address]
import ../../../src/codec/state/safrole
import ../../../src/app/proof/[worker, network_read]

proc source(): ChainView =
  ## A trusted local fixture explicitly selects finality; its best head never implies it automatically.
  let saved = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  assert saved.error == GenesisError.None
  let initialized = genesisView(saved)
  let finalized = initialized.finalizeView(saved.value.blockHash)
  assert finalized.error == ViewFinalizeError.None
  finalized.value
proc config(missing = false): ConnectionConfig =
  ## Startup input remains owned by the caller; no private-key bytes are read by the Nim identity helper.
  initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"),
    (if missing: "missing-node-key.pem" else: getEnv("RAGNAROK_TEST_KEY")),
    "jamnp-s/1/00000000", streams = 512)
proc lifetime(view: ChainView, failed: bool) =
  ## Only explicit native retirement precedes destruction of this stable callback aggregate.
  var service = default(NodeService)
  defer: service.close()
  let outcome = service.open(config(failed), view, topologyLimits())
  if failed:
    assert outcome == NodeError.BackendFailure and not service.isOpen
  else:
    assert outcome == NodeError.None and service.isOpen and service.localPort > 0
    assert service.poll(getMonoTime(), 0)
  service.close()
  assert service.peerCount == 0 and not service.isOpen
proc pump(service: var NodeService, probe: var NodeProbe, milliseconds: int) =
  ## Real bounded polling services native callbacks without acquiring a canonical alias.
  let until = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < until:
    assert service.poll(getMonoTime(), 0)
    probe.poll()
proc handshake(view: ChainView): seq[byte] =
  ## Literal E4 and empty leaf count are independent of the production announcement encoder.
  result = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](view.bestBlock.value.blockHash): result.add(octet)
  for index in 0..<4: result.add(byte((uint32(view.bestBlock.value.slot) shr (index*8)) and 255))
  result.add(0)
proc emptyBlocks(view: ChainView): seq[byte] =
  ## CE128 descending known anchor with zero maximum has exactly one empty E4 response.
  result = @[128'u8, 37, 0, 0, 0]
  for octet in array[32, byte](view.bestBlock.value.blockHash): result.add(octet)
  result.add(1)
  for index in 0..<4: result.add(0)
proc transcript(view: ChainView) {.raises.} =
  ## A real authenticated peer exercises delayed lower UP0, read saturation, worker reply and cancellation.
  var service = default(NodeService)
  var probe = default(NodeProbe)
  var cpu = default(StateProofWorker)
  defer:
    cpu.close() # No canonical owner may retire before a queued/running worker joins.
    probe.close()
    service.close()
  let hello = handshake(view)
  let request = emptyBlocks(view)
  assert service.open(config(), view, topologyLimits()) == NodeError.None
  probe.open(service.localPort)
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while not probe.authenticated and getMonoTime() < deadline: pump(service, probe, 1)
  assert probe.authenticated, "client TLS authentication"
  pump(service, probe, 20)
  assert service.peerCount == 1, "node peer admission"
  let peer = service.peerAt(0).value
  let original = probe.issue(hello, persistent = true)
  pump(service, probe, 30)
  assert service.source(peer).error == NodeError.None, "usable UP0 handshake"
  var expectedHello: seq[byte] = @[]
  for index in 1..<hello.len: expectedHello.add(hello[index])
  assert probe.bytes(original) == expectedHello, "literal UP0 handshake reply"
  assert not probe.flows[original].receivedFin
  let delayed = probe.issue(hello, persistent = true, enabled = false)
  pump(service, probe, 10)
  let newer = probe.issue(hello, persistent = true)
  pump(service, probe, 30)
  assert uint64(service.source(peer).value.stream) == uint64(probe.flows[newer].number)
  assert probe.flows[original].reset, "higher UP0 resets old source"
  probe.enable(delayed)
  pump(service, probe, 30)
  assert probe.flows[delayed].reset, "delayed lower UP0 is refused"
  assert uint64(service.source(peer).value.stream) == uint64(probe.flows[newer].number)
  let heldA = probe.issue(@[128'u8], persistent = true)
  pump(service, probe, 20)
  let heldB = probe.issue(@[128'u8], persistent = true)
  pump(service, probe, 20)
  let refused = probe.issue(request)
  pump(service, probe, 30)
  assert probe.flows[refused].reset and service.takeRead().error == NodeError.Unavailable
  let reserved = probe.issue(hello, persistent = true)
  pump(service, probe, 30)
  assert uint64(service.source(peer).value.stream) == uint64(probe.flows[reserved].number)
  probe.abort(heldA)
  probe.abort(heldB)
  pump(service, probe, 30)
  let reading = probe.issue(request, persistent = true)
  pump(service, probe, 30)
  assert service.takeRead().error == NodeError.Unavailable # Complete payload still grants no job before FIN.
  probe.enable(reading, finish = true)
  pump(service, probe, 30)
  let task = service.takeRead()
  assert task.error == NodeError.None and service.readLive(task.value.ticket), "complete FIN admits one live read"
  assert cpu.start()
  var job = captureNetworkRead(view, task.value.request).value
  let admitted = cpu.submit(job)
  assert admitted.error == ProofWorkerError.None
  while cpu.phase != ProofWorkerPhase.Done: pump(service, probe, 1)
  let completed = cpu.collect(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
  assert completed.readValue.error == ReadError.None, "canonical worker read success"
  assert service.respond(task.value.ticket, completed.readValue.value) == ReadError.None
  pump(service, probe, 30)
  assert probe.flows[reading].receivedFin and not probe.flows[reading].reset
  assert probe.bytes(reading) == @[0'u8, 0, 0, 0]
  pump(service, probe, 20)
  assert not service.readLive(task.value.ticket)
  let cancelled = probe.issue(request)
  pump(service, probe, 30)
  let stale = service.takeRead()
  assert stale.error == NodeError.None
  job = captureNetworkRead(view, stale.value.request).value
  let second = cpu.submit(job)
  assert second.error == ProofWorkerError.None
  while cpu.phase != ProofWorkerPhase.Done: pump(service, probe, 1)
  probe.abort(cancelled)
  pump(service, probe, 30)
  assert not service.readLive(stale.value.ticket)
  assert cpu.cancel(second.value) # Done retains the worker lease until cancellation is collected.
  assert cpu.collect(second.value).kind == ProofWorkerCompletionKind.Cancelled
  assert service.respond(stale.value.ticket, completed.readValue.value) == ReadError.InvalidStream
  let unsupported = probe.issue(@[255'u8])
  pump(service, probe, 30)
  assert probe.flows[unsupported].reset and service.peerCount == 1
  assert service.source(peer).error == NodeError.None, "usable UP0 handshake"
  let withheld = probe.issue(hello, persistent = true, enabled = false)
  pump(service, probe, 10)
  let malformed = probe.issue(@[0'u8, 0, 0, 16, 0], persistent = true)
  pump(service, probe, 30)
  assert probe.flows[malformed].reset # A one-MiB claimed handshake is rejected from its prefix alone.
  assert service.source(peer).error == NodeError.Unavailable
  probe.enable(withheld)
  pump(service, probe, 30)
  assert probe.flows[withheld].reset
  assert service.source(peer).error == NodeError.Unavailable # A failed highest ID must never revive a lower source.
  let recovered = probe.issue(hello, persistent = true)
  pump(service, probe, 30)
  assert uint64(service.source(peer).value.stream) == uint64(probe.flows[recovered].number)
proc paired(ipv6: bool) =
  ## Two production owners automatically establish the preferred connection and UP0 in both directions.
  let left = certificateIdentity(getEnv("RAGNAROK_TEST_CERT")).value
  let right = certificateIdentity(getEnv("RAGNAROK_TEST_CERT_B")).value
  let bindingAddress = loopbackAddress(ipv6)
  let seed = topologyCaptured(connectionRoster(left, right, 0, 0, bindingAddress))
  let trusted = genesisView(seed).finalizeView(seed.value.blockHash).value
  var first, second = default(NodeService)
  defer:
    first.close()
    second.close() # Both stable aggregate addresses outlive every final native callback.
  let firstConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    "jamnp-s/1/00000000", binding = bindingAddress, others = 0, streams = 512)
  let secondConfig = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv(
      "RAGNAROK_TEST_KEY_B"),
    "jamnp-s/1/00000000", binding = bindingAddress, others = 0, streams = 512)
  assert first.open(firstConfig, trusted, topologyLimits()) == NodeError.None
  assert second.open(secondConfig, trusted, topologyLimits()) == NodeError.None
  let advertised = topologyCaptured(connectionRoster(left, right, first.localPort, second.localPort,
    bindingAddress), atSlot = 8, parent = seed)
  let next = advanceView(trusted, advertised).value
  assert first.advance(next, StateTime(8)).error == NodeError.None
  assert second.advance(next, StateTime(8)).error == NodeError.None
  let deadline = getMonoTime()+initDuration(seconds = 3)
  var ready = false
  while getMonoTime() < deadline:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    if first.peerCount != 1 or second.peerCount != 1: continue
    let firstReady = first.peerAt(0)
    let secondReady = second.peerAt(0)
    if firstReady.error != NodeError.None or secondReady.error != NodeError.None: continue
    let a = firstReady.value
    let b = secondReady.value
    if first.source(a).error == NodeError.None and second.source(b).error == NodeError.None:
      assert a.initiated != b.initiated
      ready = true
      break # Both sides must parse a real handshake rather than merely observe authenticated TLS.
  assert ready, "paired node owners establish UP0"
  let firstPeer = first.peerAt(0).value
  let secondPeer = second.peerAt(0).value
  assert first.advance(next, StateTime(8)).error == NodeError.None
  let broadcastDeadline = getMonoTime()+initDuration(seconds = 2)
  var broadcast = false
  while getMonoTime() < broadcastDeadline:
    assert first.poll(getMonoTime(), 0) and second.poll(getMonoTime(), 0)
    let claims = second.source(secondPeer)
    if claims.error == NodeError.None and claims.value.claims.sequence > 1:
      broadcast = true
      break # Independently scheduled host processing receives the subsequent complete header message.
  assert broadcast and first.source(firstPeer).error == NodeError.None, "paired header announcement"
proc main() {.raises.} =
  ## Failed/default inputs cannot grant a socket, ticket or peer source; repeated full lifetimes release ARC owners.
  let view = source()
  var unopened = default(NodeService)
  assert not unopened.isOpen and unopened.localPort == 0 and unopened.peerCount == 0
  assert unopened.takeRead().error == NodeError.Unavailable
  assert not unopened.readLive(default(NodeReadTicket))
  assert unopened.respond(default(NodeReadTicket), default(ReadReply)) == ReadError.InvalidStream
  unopened.close()
  let noFinality = genesisView(view.bestBlock)
  assert unopened.open(config(), noFinality, topologyLimits()) == NodeError.NoFinality
  assert unopened.open(default(ConnectionConfig), view, topologyLimits()) == NodeError.InvalidConfig
  transcript(view)
  let beforeTranscript = getOccupiedMem()
  transcript(view)
  assert getOccupiedMem() == beforeTranscript, "real stream/worker lifetimes release their ARC owners"
  paired(false)
  paired(true)
  lifetime(view, false)
  lifetime(view, true)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    lifetime(view, iteration mod 3 == 0) # Exercise successful and post-allocation failed TLS/native setup.
  let after = getOccupiedMem()
  assert before == after, "complete node protocol ownership must release every factory allocation"
  recordArcRelease("jamnp_node_service", 1000, before, after)
  echo "jamnp node service: startup and stream lifetimes passed"
try:
  main()
except:
  quit 2 # Setup exceptions cannot satisfy a successful authenticated transcript.
