# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual pinned identities, wrong-key refusal, native-close readiness and timeout/cancellation never modify state.
import std/[assertions, syncio, envvars]
import ../../../src/quic/[ancestor_peer, ancestor_stream]
import ../../../src/app/[ancestor_response, ancestor_receiver]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../support/[application_download_chain, application_candidate_context, block_download_transport]

proc peerKey(name: string): AncestorPeerKey {.raises.} =
  ## Read exactly the independently generated certificate's Ed25519 key bytes.
  let raw = readFile(getEnv(name))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index]) # Fixed-size pin never aliases a string or header hash.
  AncestorPeerKey(bytes)
proc limits(): AncestorStreamLimits =
  ## One-byte write/read bounds also cover prefix fragments and every outgoing request offset.
  AncestorStreamLimits(readBytes: ByteLimit(1), writeBytes: ByteLimit(1), timeout: AncestorTimeout(100000))
proc open(peer: var AncestorPeer, request: AncestorRequest, key: AncestorPeerKey,
    port: uint16): AncestorPeerError =
  ## Explicit fixture certificate paths select the unchanged production TLS policy.
  peer.open(request, ByteLimit(100000), key, port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", limits(), AncestorTick(100))
proc scenario(request: AncestorRequest, body: seq[byte], key: AncestorPeerKey,
    config: FrameConfig, mode: DownloadTransferMode, wrong = false) =
  ## Independent responders authenticate different identities and observe whether any request reached the selected listener.
  var servers = default(DownloadResponders)
  let wire = if mode == EmptyReply: @[0'u8, 0, 0, 0]
    elif mode == Oversized: @[255'u8, 255, 255, 255]
    else: body
  assert servers.openResponders(request.requestBytes, wire, mode)
  defer: servers.close()
  var peer = default(AncestorPeer)
  defer: peer.close()
  assert peer.open(request, key, servers.port(wrong)) == AncestorPeerError.None
  assert peer.open(request, key, servers.port(false)) == AncestorPeerError.Busy
  var settled = false
  for tick in 0..<4000:
    assert servers.poll()
    let status = peer.tick(AncestorTick(uint64(100 + tick)))
    if peer.stage in [AncestorPeerStage.Ready, AncestorPeerStage.Failed]:
      settled = true
      break # Readiness is selected by actual final native close, never the fixture's byte counter.
    assert status == AncestorPeerError.None
    if mode == NoFin and servers.requestCount(false) == 1 and tick > 1000:
      assert peer.tick(AncestorTick(100100)) == AncestorPeerError.Timeout
      settled = true
      break # A complete response without FIN remains bounded by the original total deadline.
  assert settled
  if wrong:
    assert peer.stage == AncestorPeerStage.Failed and peer.failure ==
        AncestorPeerError.IdentityFailure
    assert servers.requestCount(true) == 0 and servers.requestCount(false) == 0
  elif mode in [Healthy, EmptyReply]:
    assert peer.stage == AncestorPeerStage.Ready
    let response = peer.response(config, ByteLimit(100000))
    let expected = if mode == Healthy: AncestorResponseError.None else: AncestorResponseError.Empty
    assert response.error == expected
    assert servers.requestCount(false) == 1 and servers.requestCount(true) == 0
    peer.close()
    assert peer.stage == AncestorPeerStage.Idle
    if mode == Healthy:
      assert response.value.headers.len == 1 # Captured context survives whole endpoint/receiver retirement.
  elif mode == Oversized:
    assert peer.stage == AncestorPeerStage.Failed and peer.failure ==
        AncestorPeerError.FramingFailure
    assert peer.framingError == AncestorReceiveError.LimitExceeded
  elif mode == PrematureClose:
    assert peer.stage == AncestorPeerStage.Failed
    assert peer.failure in [AncestorPeerError.FramingFailure, AncestorPeerError.TransportFailure]
  else:
    assert peer.stage == AncestorPeerStage.Failed and peer.failure == AncestorPeerError.Timeout

proc main() {.raises.} =
  ## Independently composed parent/child fixtures define the exact requested lineage.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var input = newSeq[byte](raw.len)
  for index, octet in raw: input[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(input, 2).value, 2)
  let request = initAncestorRequest(context.heads[2].header, ElementLimit(1)).value
  let key = peerKey("RAGNAROK_TEST_PEER_A")
  let body = responseFrame(context.children[0])
  let config = preparationLimits().reporting.admission.frame
  var peer = default(AncestorPeer)
  defer: peer.close()
  assert peer.tick(AncestorTick(0)) == AncestorPeerError.Uninitialized
  assert peer.open(request, key, 0) == AncestorPeerError.InvalidEndpoint
  assert peer.open(default(AncestorRequest), key, 1) == AncestorPeerError.InvalidRequest
  assert peer.open(request, ByteLimit(high(uint64)), key, 1, "missing", "missing",
      "jamnp-s/1/00000000", limits(), AncestorTick(0)) == AncestorPeerError.InvalidPolicy
  var bad = limits()
  bad.readBytes = ByteLimit(0)
  assert peer.open(request, ByteLimit(1000), key, 1, "missing", "missing", "jamnp-s/1/00000000",
      bad, AncestorTick(0)) == AncestorPeerError.InvalidPolicy
  assert peer.open(request, ByteLimit(1000), key, 1, "missing", "missing", "jamnp-s/1/00000000",
      limits(), AncestorTick(0)) == AncestorPeerError.TransportFailure
  assert peer.stage == AncestorPeerStage.Idle
  assert peer.open(request, key, 1) == AncestorPeerError.None
  assert peer.tick(AncestorTick(99)) == AncestorPeerError.InvalidPolicy
  assert peer.tick(AncestorTick(100100)) == AncestorPeerError.Timeout
  assert peer.failure == AncestorPeerError.Timeout
  peer.close()
  for mode in [Healthy, EmptyReply, Oversized, PrematureClose, NoFin]:
    scenario(request, body, key, config, mode) # Separate actual connections/streams must each retire their callback owner.
  scenario(request, body, key, config, Healthy, true)
  echo "PASS application ancestor peer: exact TLS pins, native retirement, framing and total deadline"
try:
  main() # Real TLS/fixture/backend errors remain visible failures.
except:
  quit(2)
