# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual TLS CE135 framing stays optional and validator-only; complete opaque bodies and exact bare FIN precede any semantic authority.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/startup
import ../../../src/jamnp-s/[node, connections, read_stream, read_client]
import ../../../src/quic/address
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/state/safrole
import ../../../src/chain/[provider, genesis]
import ../../support/[jamnp_topology_fixture, jamnp_node_probe]
proc publicKey(name: string): StateEdKey {.raises.} =
  ## Fixture files provide only the authenticated public identity; the native TLS backend alone imports private keys.
  let raw = readFile(getEnv(name))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  StateEdKey(bytes)
proc source(a, b: StateEdKey): ChainView =
  ## This structural trusted complete fixture supplies transport roles only; no report, execution or block-admission certificate is invented.
  var current = topologyRecords(0, 6)
  current[1].ed25519 = a
  current[2].ed25519 = b
  let saved = topologyCaptured([topologyRecords(0, 6), current, topologyRecords(1, 6)], cores = 2, atSlot = 20)
  assert saved.error == GenesisError.None
  let selected = genesisView(saved).finalizeView(saved.value.blockHash)
  assert selected.error == ViewFinalizeError.None
  selected.value
proc config(second = false): ConnectionConfig =
  ## Each stable owner has a different genuine certificate and the same fixed test-only protocol domain.
  initConnectionConfig(getEnv(if second: "RAGNAROK_TEST_CERT_B" else: "RAGNAROK_TEST_CERT"), getEnv(
      if second: "RAGNAROK_TEST_KEY_B" else: "RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", streams = 512)
proc reject(view: ChainView, enabled, guest: bool) {.raises.} =
  ## Default-disabled or non-validator peers cannot allocate a variable guarantee body or receive an acknowledgment.
  var server = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    server.close()
  assert server.open(config(), view, topologyLimits(2)) == NodeError.None
  if enabled: assert server.enableDistributionStreams()
  if guest:
    probe.open(server.localPort, "jamnp-s/1/00000000/builder", "distribution-guest/cert.pem", "distribution-guest/key.pem")
  else:
    probe.open(server.localPort, "jamnp-s/1/00000000")
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated or server.peerCount == 0:
    assert getMonoTime() < deadline, "distribution role TLS"
    assert server.poll(getMonoTime(), 0)
    probe.poll()
  let flow = probe.issue(@[135'u8, 1, 0, 0, 0, 7])
  while not probe.flows[flow].reset:
    assert getMonoTime() < deadline and not probe.flows[flow].receivedFin, "distribution role reset"
    assert server.poll(getMonoTime(), 0)
    probe.poll()
  assert server.takeRead().error == NodeError.Unavailable
proc inputBoundaries(view: ChainView) {.raises.} =
  ## Exact E4/body/FIN completion is required independently of any report decoder or canonical graph.
  var server = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    server.close()
  assert server.open(config(), view, topologyLimits(2)) == NodeError.None
  assert server.enableDistributionStreams()
  probe.open(server.localPort, "jamnp-s/1/00000000")
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated or server.peerCount == 0:
    assert getMonoTime() < deadline
    assert server.poll(getMonoTime(), 0)
    probe.poll()
  let malformed = [@[135'u8, 0, 0, 0, 0], @[135'u8, 1, 0],
    @[135'u8, 2, 0, 0, 0, 1], @[135'u8, 1, 0, 0, 0, 1, 2],
    @[135'u8, 255, 255, 255, 255], @[135'u8, 1, 0, 128, 0]]
  for packet in malformed:
    # Empty, short prefix/body, trailing bytes and oversized declarations reset before host admission.
    let flow = probe.issue(packet)
    while not probe.flows[flow].reset:
      assert getMonoTime() < deadline and not probe.flows[flow].receivedFin
      assert server.poll(getMonoTime(), 0)
      probe.poll()
      assert server.takeRead().error == NodeError.Unavailable
  let held = probe.issue(@[135'u8, 1, 0, 0, 0, 7], persistent = true)
  for turn in 0..<100:
    # A complete body with withheld FIN remains opaque and cannot be claimed by a managed consumer.
    assert server.poll(getMonoTime(), 0)
    probe.poll()
    assert server.takeRead().error == NodeError.Unavailable
  assert probe.flows[held].opened and not probe.flows[held].reset
  probe.enable(held, finish = true)
  while true:
    let task = server.takeRead()
    if task.error == NodeError.None:
      assert task.value.request.kind == ReadKind.Guarantee
      assert task.value.request.payload == @[7'u8]
      assert server.reject(task.value.ticket) # Framing grants no semantic right to acknowledge this deliberately invalid report.
      break
    assert task.error == NodeError.Unavailable and getMonoTime() < deadline
    assert server.poll(getMonoTime(), 0)
    probe.poll()
proc pump(a, b: var NodeService) =
  ## Only the ordinary bounded native loops drive stream opens, body transfers, FIN and retirement.
  assert a.poll(getMonoTime(), 0)
  assert b.poll(getMonoTime(), 0)
proc transfer(view: ChainView, keyB: StateEdKey) =
  ## One maximal opaque request holds both copies until collection; another cannot overrun the shared output budget.
  var a, b = default(NodeService)
  defer:
    b.close()
    a.close()
  assert a.open(config(), view, topologyLimits(2)) == NodeError.None
  assert b.open(config(true), view, topologyLimits(2)) == NodeError.None
  assert b.enableDistributionStreams()
  assert a.beginPeerConnection(keyB, networkEndpoint(loopbackAddress(false), b.localPort)).error == DialError.None
  let deadline = getMonoTime()+initDuration(seconds = 25)
  while a.peerCount == 0 or b.peerCount == 0:
    assert getMonoTime() < deadline, "distribution peer TLS"
    pump(a, b)
  let peer = a.peerForIdentity(keyB).value
  var body = newSeq[byte](MaxReadReplyBytes)
  body[0] = 9
  body[body.high] = 17
  let request = decodeReadRequest(ReadKind.Guarantee, body)
  assert request.error == ReadError.None
  assert a.request(peer, request.value, ByteLimit(0)).error == NodeError.Unavailable
  assert a.enableDistributionStreams()
  var started = default(NodeResult[NodeRequestTicket])
  while true:
    started = a.request(peer, request.value, ByteLimit(0))
    if started.error == NodeError.None: break
    assert started.error == NodeError.Unavailable and getMonoTime() < deadline
    pump(a, b)
  var pressure = default(NodeResult[NodeRequestTicket])
  while true:
    pressure = a.request(peer, request.value, ByteLimit(0))
    if pressure.error != NodeError.Unavailable: break
    assert getMonoTime() < deadline
    pump(a, b)
  assert pressure.error == NodeError.LimitExceeded, "outgoing request copies reserve byte credit before allocation"
  var task = default(NodeResult[NodeReadTask])
  while true:
    task = b.takeRead()
    if task.error == NodeError.None: break
    assert task.error == NodeError.Unavailable and getMonoTime() < deadline
    pump(a, b)
  assert task.value.request.kind == ReadKind.Guarantee
  assert task.value.request.payload == body
  assert a.takeReply(started.value).error == ReadError.Unavailable
  assert b.respond(task.value.ticket, captureReadReply(task.value.request, []).value) == ReadError.None
  while true:
    let reply = a.takeReply(started.value)
    if reply.error == ReadError.None:
      assert reply.value.bytes.len == 0
      break
    assert reply.error == ReadError.Unavailable and getMonoTime() < deadline
    pump(a, b)
  var renewed = default(NodeResult[NodeRequestTicket])
  while true:
    renewed = a.request(peer, request.value, ByteLimit(0))
    if renewed.error == NodeError.None: break
    assert renewed.error in [NodeError.Unavailable, NodeError.LimitExceeded]
    assert getMonoTime() < deadline, "output credit after native retirement"
    pump(a, b)
  assert a.cancelRequest(renewed.value)
  assert not a.cancelRequest(renewed.value)
  assert a.takeReply(renewed.value).error == ReadError.InvalidStream
  body.add(0)
  assert decodeReadRequest(ReadKind.Guarantee, body).error == ReadError.LimitExceeded
proc main() {.raises.} =
  ## Frame completion is deliberately opaque here; only the separate managed qualification pipeline may accept actual report credentials.
  var diagnostic = ""
  assert ensureIdentity("distribution-guest", diagnostic)
  let keyA = publicKey("RAGNAROK_TEST_PEER_A")
  let keyB = publicKey("RAGNAROK_TEST_PEER_B")
  let view = source(keyA, keyB)
  reject(view, false, false)
  reject(view, true, true)
  inputBoundaries(view)
  transfer(view, keyB)
  echo "JAMNP-S distribution framing passed"
try:
  main()
except:
  quit 2 # Native setup failures cannot satisfy role, byte-budget or complete-FIN evidence.
