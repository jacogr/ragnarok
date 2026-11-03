# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual Services graph gates, worker cancellation and joined application-node shutdown over authenticated TLS.
import std/[assertions, envvars, syncio, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/proof/worker
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream]
import ../../../src/chain/[genesis, parameters, provider]
import ../../../src/codec/header
import ../../../src/codec/state/safrole
import ../../../src/state/store
import ../../../src/rpc/server
import ../../../src/lib/json/writer as json_writer
import ../../support/[jamnp_topology_fixture, jamnp_node_probe]
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
proc pump(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    milliseconds: int, now = StateTime(7)) {.raises.} =
  ## Actor polling precedes ordinary Services ticks; all canonical CPU work stays outside native callbacks.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert host.poll(getMonoTime(), now, 0)
    probe.poll()
    services.tick(uint32(host.peerCount))
proc main() {.raises.} =
  ## Missing finality, real read replies, cancellation and foreign worker ownership remain independent gates.
  let saved = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  let path = "application-node-chain.json"
  writeFile(path, chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", path, "--with-state"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close() # Services storage and every joined worker outlive the borrowing node host.
  assert services.start(options, "application node")
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    protocol, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.NoFinality
  let selected = services.chainView.bestBlock.value
  let hash = selected.blockHash
  assert services.publishFinalized(default(BlockHash)) == ViewFinalizeError.UnknownBlock
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  probe.open(host.localPort, protocol)
  let deadline = getMonoTime()+initDuration(seconds = 3)
  while not probe.authenticated and getMonoTime() < deadline: pump(host, services, probe, 1)
  assert probe.authenticated, "real application peer authenticates configured genesis ALPN"
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0) # Slot is E4, followed by canonical zero-leaf natural.
  let persistent = probe.issue(hello, persistent = true)
  pump(host, services, probe, 30)
  let peer = host.peerAt(0).value
  assert host.source(peer).error == NodeError.None
  var request = @[128'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): request.add(octet)
  request.add(1)
  for index in 0..<4: request.add(0)
  let reading = probe.issue(request, persistent = true)
  pump(host, services, probe, 30)
  assert not services.stateProofActive and probe.bytes(reading).len == 0, "application read awaits FIN"
  probe.enable(reading, finish = true)
  pump(host, services, probe, 80)
  assert probe.flows[reading].receivedFin and not probe.flows[reading].reset
  assert probe.bytes(reading) == @[0'u8, 0, 0, 0]
  assert not services.stateProofActive and not services.rpc.chainPaused
  let cancelled = probe.issue(request)
  let start = getMonoTime()
  while not services.stateProofActive and getMonoTime()-start < initDuration(seconds = 3):
    assert host.poll(getMonoTime(), StateTime(7), 0)
    probe.poll()
  assert services.stateProofActive, "application host owns the admitted worker lease"
  assert services.publishFinalized(hash) == ViewFinalizeError.Uninitialized, "busy finality never reads the borrowed graph"
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime()-start < initDuration(seconds = 3)
    probe.poll() # Deliberately keep Done uncollected while the peer reset is queued.
  probe.abort(cancelled)
  probe.poll()
  pump(host, services, probe, 50)
  assert not services.stateProofActive and not services.rpc.chainPaused
  assert not probe.flows[cancelled].receivedFin, "cancelled application job emits no successful FIN"
  let beforeClock = probe.bytes(persistent)
  pump(host, services, probe, 30, StateTime(8))
  assert probe.bytes(persistent) == beforeClock, "local clock ticks never rebroadcast the unchanged canonical header"
  discard probe.issue(request)
  let shutdownStart = getMonoTime()
  while not services.stateProofActive and getMonoTime()-shutdownStart < initDuration(seconds = 3):
    assert host.poll(getMonoTime(), StateTime(8), 0)
    probe.poll()
  assert services.stateProofActive, "shutdown begins with this host's actual admitted read"
  host.close()
  assert not services.stateProofActive and not services.rpc.chainPaused
  assert services.stateProofPhase == ProofWorkerPhase.Idle, "owned read is joined before canonical retirement"
  assert host.localPort == 0 and not host.isOpen
  assert host.open(services, config, topologyLimits(), StateTime(8)) == NodeError.None
  let decoded = decodeReadRequest(ReadKind.Blocks, request.toOpenArray(5, request.len-1))
  let foreign = services.beginNetworkRead(decoded.value)
  assert foreign.error == StateProofAdmissionError.None
  host.close()
  assert services.stateProofActive and services.rpc.chainPaused, "closing an idle host leaves a foreign worker lease intact"
  services.stopStateProofs()
  assert not services.stateProofActive and not services.rpc.chainPaused
  echo "jamnp application node: managed TLS reads and exact lease shutdown passed"
try:
  main()
except:
  quit 2 # Setup failures cannot stand in for a successful production host transcript.
