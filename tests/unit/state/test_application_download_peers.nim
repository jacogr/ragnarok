# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_peers_arc_release"}

## Actual pinned-peer TLS, target selection, binding retry and explicit native retirement preserve session authority.

import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/quic/[block_download_peers, block_download_session, block_download_stream]
import ../../../src/app/[download_schedule, block_download, block_input, candidate, services,
    options, chain]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/[store, accumulation_finalization]
import ../../support/[application_candidate_context, accumulation_completion_context,
    block_download_transport, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## A receiving/native callback cannot silently prepare or publish a block.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe zero hash work during catalog and native-only operations.

proc peerKey(name: string): DownloadPeerKey {.raises.} =
  ## Load all bytes of the fresh, independently generated public-key fixture.
  let raw = readFile(getEnv(name))
  assert raw.len == 32
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(raw[index]) # Only the fixed Ed25519 SPKI payload is accepted by the fixture generator.
  DownloadPeerKey(key)
proc limits(): DownloadStreamLimits =
  ## Explicit callback bounds and total bound-stream duration are unrelated to protocol block slots.
  DownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3), timeout: DownloadTimeout(100))
proc begin(session: var BlockDownloadSession, owner: Services,
    peer: DownloadPeerId): DownloadSessionAttempt =
  ## The scheduler authorizes one explicit registered peer; catalog identity proof remains independent.
  assert session.configure([peer], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 4, retryDelay: DownloadRetryDelay(1)), DownloadScheduleTick(0)) ==
        DownloadScheduleError.None
  let admitted = session.begin(owner, [], BlockInputLimits(blockBytes: ByteLimit(100000)),
    preparationLimits(), DownloadScheduleTick(0))
  assert admitted.error == DownloadSessionError.None
  admitted.value
proc open(catalog: var BlockDownloadPeers, id: uint64, key: DownloadPeerKey,
    port: uint16): DownloadPeerError =
  ## Production callbacks pin key; the test supplies only explicit local TLS/endpoint inputs.
  catalog.openPeer(DownloadPeerId(id), key, port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000")
proc step(catalog: var BlockDownloadPeers, servers: var DownloadResponders) =
  ## Bound native work independently of any block producer or canonical service tick.
  assert servers.poll()
  assert catalog.poll() <= 2
proc authenticate(catalog: var BlockDownloadPeers, servers: var DownloadResponders) =
  ## Wait a bounded number of native ticks for both actual peer handshakes.
  var ready = false
  for tick in 0..<4000:
    step(catalog, servers)
    if catalog.ready(DownloadPeerId(11)) and catalog.ready(DownloadPeerId(22)):
      ready = true
      break # Authentication alone never opens a block stream.
  assert ready

proc registration(keyA, keyB: DownloadPeerKey) =
  ## All preflight failures preserve ownership, and identity pins survive retirement/reconnect.
  var catalog = default(BlockDownloadPeers)
  defer: catalog.close()
  assert catalog.open(11, keyA, 1) == DownloadPeerError.Uninitialized
  assert catalog.configure(ElementLimit(0)) == DownloadPeerError.InvalidPolicy
  assert catalog.configure(ElementLimit(17)) == DownloadPeerError.InvalidPolicy
  assert catalog.configure(ElementLimit(1)) == DownloadPeerError.None
  assert catalog.configure(ElementLimit(1)) == DownloadPeerError.Busy
  assert catalog.open(0, keyA, 1) == DownloadPeerError.InvalidPeer
  assert catalog.open(11, keyA, 0) == DownloadPeerError.InvalidEndpoint
  assert catalog.openPeer(DownloadPeerId(11), keyA, 1, "missing.cert", "missing.key",
    "jamnp-s/1/00000000") == DownloadPeerError.TransportFailure
  assert catalog.count == 0
  assert catalog.open(11, keyA, 1) == DownloadPeerError.None
  assert catalog.open(11, keyA, 1) == DownloadPeerError.DuplicatePeer
  assert catalog.open(22, keyA, 1) == DownloadPeerError.DuplicateIdentity
  assert catalog.open(22, keyB, 1) == DownloadPeerError.Capacity
  assert catalog.retire(DownloadPeerId(11)) and not catalog.retire(DownloadPeerId(11))
  assert catalog.open(11, keyB, 1) == DownloadPeerError.DuplicatePeer
  assert catalog.open(11, keyA, 1) == DownloadPeerError.None
  assert catalog.readyPeers.len == 0 and catalog.count == 1
  assert catalog.bindingFailure(DownloadPeerId(99)).error == DownloadPeerError.MissingPeer
  assert catalog.bindingFailure(DownloadPeerId(11)).error == DownloadPeerError.NoBindingFailure

proc wrongKey(owner: Services, frame: seq[byte], keyA: DownloadPeerKey) =
  ## Pinning the first identity against the second listener must never authorize a stream.
  var session = default(BlockDownloadSession)
  let token = session.begin(owner, DownloadPeerId(22))
  var servers = default(DownloadResponders)
  assert servers.openResponders(session.request(token).value, frame)
  defer: servers.close()
  var catalog = default(BlockDownloadPeers)
  defer: catalog.close()
  assert catalog.configure(ElementLimit(1)) == DownloadPeerError.None
  assert catalog.open(22, keyA, servers.port(true)) == DownloadPeerError.None
  failHash(1)
  for tick in 0..<500: step(catalog, servers) # Bound the failed TLS handshake without converting its old counters into admission.
  assert catalog.identityRejected(DownloadPeerId(22))
  assert not catalog.ready(DownloadPeerId(22)) and catalog.readyPeers.len == 0
  assert catalog.requestStream(session, token, limits(), DownloadTick(100)) ==
      DownloadPeerError.NotAuthenticated
  assert hashCalls() == 0
  failHash(0)
  assert session.discardInput(token).error == DownloadSessionError.None
  assert session.finish(token, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)).error ==
      DownloadSessionError.None

proc transfer(owner: var Services, frame: seq[byte], keyA, keyB: DownloadPeerKey, cancel: bool) =
  ## The second authenticated principal receives the actual request; the first listener remains untouched.
  var session = default(BlockDownloadSession)
  let token = session.begin(owner, DownloadPeerId(22))
  var servers = default(DownloadResponders)
  let mode = if cancel: NoFin else: Healthy
  assert servers.openResponders(session.request(token).value, frame, mode)
  defer: servers.close()
  var catalog = default(BlockDownloadPeers)
  defer: catalog.close()
  assert catalog.configure(ElementLimit(2)) == DownloadPeerError.None
  assert catalog.open(11, keyA, servers.port(false)) == DownloadPeerError.None
  assert catalog.open(22, keyB, servers.port(true)) == DownloadPeerError.None
  failHash(1)
  assert catalog.requestStream(session, token, limits(), DownloadTick(100)) ==
      DownloadPeerError.NotAuthenticated
  authenticate(catalog, servers)
  var copied = catalog.readyPeers
  assert copied.len == 2 and copied[0] == DownloadPeerId(11) and copied[1] == DownloadPeerId(22)
  copied[1] = DownloadPeerId(99) # Mutating the returned list cannot mutate catalog identity storage.
  assert catalog.readyPeers[1] == DownloadPeerId(22)
  let forged = DownloadSessionAttempt()
  assert catalog.requestStream(session, forged, limits(), DownloadTick(100)) ==
      DownloadPeerError.MissingPeer
  var invalid = limits()
  invalid.readBytes = ByteLimit(0)
  assert catalog.requestStream(session, token, invalid, DownloadTick(100)) == DownloadPeerError.None
  assert catalog.requestStream(session, token, limits(), DownloadTick(100)) ==
      DownloadPeerError.Busy
  for tick in 0..<4000:
    step(catalog, servers)
    if not catalog.busy: break # A rejected binding still holds native ownership until actual close.
  assert not catalog.busy and session.stage == BlockDownloadStage.Receiving
  assert catalog.bindingFailure(DownloadPeerId(22)).value.streamError ==
      DownloadStreamError.InvalidPolicy
  assert catalog.requestStream(session, token, limits(), DownloadTick(100)) ==
      DownloadPeerError.None
  var completed = false
  for tick in 0..<4000:
    step(catalog, servers)
    if cancel and session.receivedBytes == uint64(frame.len):
      assert catalog.expire(DownloadTick(199)) == 0
      assert catalog.expire(DownloadTick(200)) == 1
      completed = true
      break # Exact deadline cancels only the selected active stream.
    if not cancel and session.stage == BlockDownloadStage.Ready:
      completed = true
      break # Both genuine FIN observations precede any producer work.
  assert completed and hashCalls() == 0
  assert servers.requestCount(false) == 0 and servers.requestCount(true) == 1
  assert catalog.retire(DownloadPeerId(22)) # Retire the owning engine while the borrowed session remains alive.
  assert not session.streamActive and not catalog.busy and not catalog.ready(DownloadPeerId(22))
  assert catalog.ready(DownloadPeerId(11)) # One peer's retirement must not poison a healthy sibling.
  assert catalog.requestStream(session, token, limits(), DownloadTick(200)) ==
      DownloadPeerError.NotAuthenticated
  failHash(0)
  if cancel:
    assert session.stage == BlockDownloadStage.Idle
    assert session.finish(token, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)).error ==
        DownloadSessionError.None
  else:
    let before = owner.stateSnapshot.value
    let queued = session.enqueue(token, owner, completionLimits().composition)
    assert queued.error == DownloadSessionError.None
    assert sameStateSnapshot(queued.value.finalAccumulationParent.value, before)
    assert sameStateSnapshot(before, owner.stateSnapshot.value)
    owner.tick(0)
    assert owner.takeAccumulation.error == ApplicationChainError.None
    assert session.finish(token, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(0)).error ==
        DownloadSessionError.None

proc cycle(key: DownloadPeerKey) =
  ## Every iteration opens a real endpoint and retires its pending connection before native callback storage leaves scope.
  var catalog = default(BlockDownloadPeers)
  assert catalog.configure(ElementLimit(1)) == DownloadPeerError.None
  assert catalog.open(11, key, 1) == DownloadPeerError.None
  catalog.close()
  catalog.close() # Explicit close is idempotent after native engine/socket retirement.
  assert catalog.count == 0 and not catalog.busy

proc main() {.raises.} =
  ## Build the genuine signed block and complete writable seed independently of transport receiver storage.
  let keyA = peerKey("RAGNAROK_TEST_PEER_A")
  let keyB = peerKey("RAGNAROK_TEST_PEER_B")
  assert keyA != keyB
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Preserve all frozen report bytes.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  var frame = newSeq[byte](body + 4)
  for index in 0..<4: frame[index] = byte((uint64(body) shr (8 * index)) and 255)
  assert encodeBlock(Block(header: blockOwner.blockHeader.value,
      extrinsic: blockOwner.blockExtrinsic.value),
    preparationLimits().reporting.admission.frame, frame.toOpenArray(4, frame.high)).error ==
        FrameError.None
  writeFile("application-download-peers-chain.json", context.text)
  defer: discard posix.unlink("application-download-peers-chain.json")
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain",
    "application-download-peers-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "test")
  defer: owner.close()
  registration(keyA, keyB)
  wrongKey(owner, frame, keyA)
  transfer(owner, frame, keyA, keyB, true)
  cycle(keyA)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(keyA) # Fresh native endpoints retire without retaining Nim callback owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_download_peers", 1000, before, after)
  transfer(owner, frame, keyA, keyB, false)
  echo "Application download peers passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture/file failures cannot satisfy the suite's expected success output.
except:
  quit(2)
