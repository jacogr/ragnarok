# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real ordinary application nodes serve bounded assurance reads from the caller's durable namespace through managed proof work and both native FINs, without a guarantor session or private signer.

import std/[assertions, monotimes, times, posix/posix]
import ../../src/app/[services, options, node as application_node]
import ../../src/jamnp-s/[node as node_streams, connections, endpoints, read_stream]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/state/safrole
import ../../src/quic/address
import ./[jamnp_assurance_fixture, jamnp_topology_fixture, assurance_signer_context]

proc assuranceReadRuntime*(server: var Services, settings: Options,
    fixture: AssuranceAcquisitionFixture, request: ReadRequest, expected: seq[byte],
    suffix: string, records = 1'u64) {.raises.} =
  ## Each Services instance independently decodes the explicit complete trusted seed; only the server owns the already configured archive/read policy.
  var serverKey = "assurance-audit-server-key-" & suffix & ".pem"
  var serverCert = "assurance-audit-server-cert-" & suffix & ".pem"
  var clientKey = "assurance-audit-client-key-" & suffix & ".pem"
  var clientCert = "assurance-audit-client-cert-" & suffix & ".pem"
  assuranceSignerFiles(serverKey, serverCert, 12)
  assuranceSignerFiles(clientKey, clientCert, 13)
  defer:
    discard posix.unlink(serverKey.toCString())
    discard posix.unlink(serverCert.toCString())
    discard posix.unlink(clientKey.toCString())
    discard posix.unlink(clientCert.toCString())
  var receiver = default(Services)
  defer: receiver.close()
  assert receiver.start(settings, "native durable audit client"), "independent actual audit client state"
  assert server.publishFinalized(server.chainView.bestBlock.value.blockHash) ==
    ViewFinalizeError.None, "server explicit complete trusted finality"
  assert receiver.publishFinalized(receiver.chainView.bestBlock.value.blockHash) ==
    ViewFinalizeError.None, "client explicit complete trusted finality"
  var a = default(ApplicationNode)
  var b = default(ApplicationNode)
  defer:
    b.close()
    a.close() # Both native callback owners retire before their independently owned Services instances.
  let geometry = topologyLimits(3, int(uint64(fixture.source.value.epochSlots)))
  let now = StateTime(uint32(fixture.source.value.slot))
  assert a.open(server, initConnectionConfig(serverCert, serverKey, server.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "ordinary durable server host"
  assert b.open(receiver, initConnectionConfig(clientCert, clientKey, receiver.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "ordinary authenticated audit client"
  assert b.beginPeerConnection(fixture.local, networkEndpoint(loopbackAddress(false),
    a.localPort)).error == DialError.None, "actual canonical TLS server pin"
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while a.peerCount == 0 or b.peerCount == 0:
    # Only ordinary application polling progresses native handshakes and work; no responder or verification callback is replaced.
    assert getMonoTime() < deadline, "real durable-audit handshake deadline"
    assert a.poll(getMonoTime(), now, 0), "server native handshake"
    assert b.poll(getMonoTime(), now, 0), "client native handshake"
  var peer = default(NodePeer)
  for ordinal in 0..<b.peerCount:
    # Select the authenticated actual generation, never a request-supplied source identity.
    let candidate = b.peerAt(ordinal).value
    if array[32, byte](candidate.identity) == array[32, byte](fixture.local): peer = candidate
  assert array[32, byte](peer.identity) == array[32, byte](fixture.local), "actual durable server identity"
  var ticket = default(NodeRequestTicket)
  var admitted = false
  while not admitted:
    # Native open-intent/frame capacity may briefly remain charged; admission is finite and preserves the exact eventual token.
    let started = b.request(peer, request, ByteLimit(8000000))
    if started.error == NodeError.None:
      ticket = started.value
      admitted = true
    else:
      assert started.error in [NodeError.Unavailable, NodeError.LimitExceeded], "ordinary audit admission pressure"
      assert getMonoTime() < deadline, "durable-audit admission deadline"
      assert a.poll(getMonoTime(), now, 0), "server admission progress"
      assert b.poll(getMonoTime(), now, 0), "client admission progress"
  while true:
    # The production server captures a closed archive read and responds only after exact collection; the client exposes bytes only after both FINs.
    assert getMonoTime() < deadline, "real durable-audit proof/FIN deadline"
    assert a.poll(getMonoTime(), now, 0), "actual durable server work progress"
    assert b.poll(getMonoTime(), now, 0), "actual durable client FIN progress"
    let reply = b.takeReply(ticket)
    if reply.error == ReadError.Unavailable: continue
    assert reply.error == ReadError.None and reply.value.bytes == expected,
      "real durable assurance reply matches independently derived original framed data/proof reply"
    break
  assert server.assuranceStorageInfo.records == records and not server.assuranceStorageInfo.faulted,
    "native serving preserves the actual retained namespace"
  assert not server.assuranceSigningConfigured and not receiver.assuranceStorageInfo.opened,
    "no private signer or client archive is implicitly enabled"
