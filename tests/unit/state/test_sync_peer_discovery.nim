# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real pinned TLS peers exchange independently framed UP0 bytes; retired sources cannot retain targets.
import std/[assertions, envvars, monotimes, times, syncio]
import std/posix/posix
import ../../../src/quic/[announcements, announcement_stream]
import "../../../src/quic/current/block/download/peers" as current_block_download_peers
import "../../../src/quic/current/block/download/session" as current_block_download_session
import "../../../src/quic/current/block/download/stream" as current_block_download_stream
import ../../../src/quic/[transport, protocol]
import ../../../src/app/download/schedule as download_schedule
import ../../../src/app/[services, options]
import "../../../src/app/current/block/input" as current_block_input
import "../../../src/app/current/block/download" as current_block_download
import ../../../src/codec/report_owned
import ../../support/[current_application_context, accumulation_current_chain_context,
  accumulation_current_candidate_context]
import ../../../src/codec/[bounded, header]

type RawAnnouncer = object ## Stable test listener deliberately avoids the production UP0 stream route.
  transport: Transport
  stream: NativeStream
  input, output, expected: seq[byte]
  offset: int
  handshake: bool
  ce: NativeStream
  ceInput: seq[byte]
  ceWritten: int
  ceExpected: array[42, byte]
proc `=copy`(destination: var RawAnnouncer, source: RawAnnouncer) {.error.}
  ## Listener callbacks cannot survive a copied or relocated owner.
proc `=dup`(source: RawAnnouncer): RawAnnouncer {.error.}
  ## Composite fixture ownership is exclusive too.
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Use ordinary JAM certificate/SAN checks; the client separately pins the exact server key.
  cint(validPeer(cast[ptr byte](der), length, []))
proc event(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## Independent responder sends single-octet fragments and never treats an idle queue as FIN.
  let server = cast[ptr RawAnnouncer](user)
  if event == 0 and server.stream != NativeStream(nil):
    assert server.ce == NativeStream(nil), "one independent CE stream alongside UP0"
    server.ce = stream
    server.ceInput = @[]
    server.ceWritten = 0
    wantRead(stream, 1)
    return
  if stream == server.ce and stream != NativeStream(nil):
    # This independently framed CE128 request shares the connection with the persistent UP0 stream.
    case event
    of 1:
      var buffer = default(array[43, byte])
      let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
      if count == -2: return
      assert count >= 0 and count <= int64(buffer.len), "bounded CE read"
      assert server.ceInput.len + int(count) <= 42, "exact CE128 request extent"
      for index in 0..<int(count): server.ceInput.add(buffer[index])
      if count == 0:
        assert server.ceInput.len == 42, "request FIN follows all CE128 bytes"
        for index in 0..<42: assert server.ceInput[index] == server.ceExpected[index], "independent CE128 request bytes"
        readDone(stream)
        wantRead(stream, 0)
        wantWrite(stream, 1)
    of 2:
      var empty = default(array[4, byte]) # E4 size zero frames an empty block-sequence message.
      if server.ceWritten < 4:
        let count = streamWrite(stream, addr empty[0], csize_t(4 - server.ceWritten))
        if count == -2: return
        assert count > 0 and count <= int64(4 - server.ceWritten), "bounded empty CE reply"
        server.ceWritten += int(count)
      if server.ceWritten == 4:
        wantWrite(stream, 0)
        streamFin(stream) # A real empty CE reply cannot imply synchronization or erase UP0 claims.
    of 3:
      server.ce = NativeStream(nil)
    of 4:
      wantRead(stream, 0)
      wantWrite(stream, 0)
    else: discard # No other callback can complete this independent CE request.
    return
  case event
  of 0:
    assert server.stream == NativeStream(nil), "raw responder duplicate stream"
    server.stream = stream
    server.input = @[]
    server.offset = 0
    server.handshake = false
    wantRead(stream, 1)
  of 1:
    var buffer = default(array[19, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    if count <= 0:
      streamAbort(stream)
      return # A peer's half-close cannot manufacture a complete handshake.
    assert count <= int64(buffer.len) and server.input.len + int(count) <= 8192, "bounded independent request reads"
    for index in 0..<int(count): server.input.add(buffer[index])
    if not server.handshake and server.input.len >= server.expected.len:
      for index in 0..<server.expected.len: assert server.input[index] == server.expected[index], "raw handshake byte mismatch"
      server.handshake = true
      wantWrite(stream, 1)
  of 2:
    if server.offset < server.output.len:
      let count = streamWrite(stream, addr server.output[server.offset], 1)
      if count == -2: return
      assert count == 1, "raw response write"
      inc server.offset
    if server.offset == server.output.len:
      wantWrite(stream, 0)
      discard streamFlush(stream)
  of 3:
    server.stream = NativeStream(nil)
  of 4:
    wantRead(stream, 0)
    wantWrite(stream, 0)
  else: discard # Native lifecycle events outside this fixture's protocol grant no progress.
proc claim(marker: byte, slot: uint32): AnnouncedBlock =
  ## Deliberately separated slots prove progress is not an inferred adopted-block count.
  result = default(AnnouncedBlock)
  var hash = default(array[32, byte])
  hash[0] = marker
  result.hash = AnnouncedHeaderHash(hash)
  result.slot = HeaderSlot(slot)
proc record(value: AnnouncedBlock): seq[byte] =
  ## Independent fixed wire layout for hash and little-endian E4 slot.
  result = @[]
  for value in array[32, byte](value.hash): result.add(value)
  for index in 0..<4: result.add(byte((uint32(value.slot) shr (index * 8)) and 255))
proc framed(body: seq[byte], kind = false): seq[byte] =
  ## Native tests author their framing independently of the production route.
  result = @[]
  if kind: result.add(0)
  for index in 0..<4: result.add(byte((uint64(body.len) shr (index * 8)) and 255))
  for value in body: result.add(value)
proc handshake(finalized, leaf: AnnouncedBlock): seq[byte] =
  ## One leaf has a literal compact count byte, not an E4 sequence count.
  result = record(finalized)
  result.add(1)
  for value in record(leaf): result.add(value)
proc peerKey(second = false): CurrentDownloadPeerKey {.raises.} =
  ## Fixture provider owns exact generated identity files, independent of application claims.
  let text = readFile(getEnv(if second: "RAGNAROK_TEST_PEER_B" else: "RAGNAROK_TEST_PEER_A"))
  assert text.len == 32, "fixture public key extent"
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(text[index])
  CurrentDownloadPeerKey(bytes)
proc open(server: var RawAnnouncer, expected, response: seq[byte]): bool =
  ## Store callback bytes before the native listener can deliver any read/write event.
  server.expected = expected
  server.output = response
  server.transport.openTransport(true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000", addr server, verify, event)
proc tick(server: var RawAnnouncer, peers: var CurrentDownloadPeers) =
  ## Bound work to one poll per independent endpoint; no execution happens in these callbacks.
  assert server.transport.pollTransport(0), "independent listener poll"
  discard peers.poll()
proc awaitView(server: var RawAnnouncer, peers: var CurrentDownloadPeers,
    sequence: uint64): PeerAnnouncementSnapshot =
  ## Real monotonic deadline bounds handshake and every intentionally fragmented follow-up.
  let start = getMonoTime()
  while (getMonoTime() - start).inMilliseconds < 2000:
    server.tick(peers)
    let view = peers.announcements(DownloadPeerId(1))
    if view.available and view.value.sequence == sequence: return view
  echo "UP0_DEADLINE sequence=", sequence, " request_bytes=", server.input.len,
    " response_bytes=", server.offset, "/", server.output.len, " handshake=", server.handshake,
    " ready_peers=", peers.readyPeers.len, " generation=", peers.incarnation(DownloadPeerId(1)),
    " identity_rejected=", peers.identityRejected(DownloadPeerId(1))
  assert false, "UP0 observation deadline"
  default(PeerAnnouncementSnapshot)
proc main() {.raises.} =
  ## Exact key pinning, live generation changes, updates, malformed frames and native retirement are distinct checks.
  var config = fullHeaderConfig(ByteLimit(4096))
  config.epochSlots = EpochSlots(12)
  let limits = AnnouncementLimits(leaves: ElementLimit(4), bytes: ByteLimit(8192), header: config)
  let final = claim(1, 0)
  let localLeaf = claim(2, 0)
  let far = claim(3, 10000)
  let local = AnnouncementHandshake(finalized: final, leaves: @[localLeaf])
  var absentRoute = default(AnnouncementRoute)
  assert absentRoute.bindStream(NativeStream(nil), true, local, limits) ==
      AnnouncementError.InvalidStream
  assert not absentRoute.snapshot.available

  let report = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var reportBytes = newSeq[byte](report.len)
  for index in 0..<report.len: reportBytes[index] = byte(report[index])
  let context = currentChainFixture(decodeOwnedReport(reportBytes, 2).value, available = true)
  var path = "sync-discovery-current-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  defer: owner.close()
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "UP0 and CE128 coexistence")
  var session = default(CurrentDownloadSession)
  assert session.configure([DownloadPeerId(1)], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(10)), DownloadScheduleTick(100)) ==
        DownloadScheduleError.None
  let admitted = session.begin(owner, [], CurrentBlockInputLimits(blockBytes: ByteLimit(100000)),
    currentCandidateLimits(), DownloadScheduleTick(100))
  assert admitted.error == CurrentDownloadSessionError.None
  let attempt = admitted.value
  var server = default(RawAnnouncer)
  server.ceExpected = session.request(attempt).value
  var peers = default(CurrentDownloadPeers)
  defer:
    peers.close()
    server.transport.closeTransport() # Source retirement precedes every callback byte owner leaving scope.
  assert server.open(framed(handshake(final, localLeaf), true), framed(handshake(final, far))), "independent UP0 listener startup"
  assert peers.configure(ElementLimit(1)) == CurrentDownloadPeerError.None, "bounded peer catalog configuration"
  assert peers.enableAnnouncements(local, limits) == CurrentDownloadPeerError.None, "explicit UP0 opt-in"
  assert not peers.announcements(DownloadPeerId(1)).available, "retired/invalid source must revoke view"
  assert peers.openPeer(DownloadPeerId(1), peerKey(), server.transport.localPort,
    getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None, "opening pinned discovery peer"
  let first = server.awaitView(peers, 1)
  assert first.value.leaves == @[far] and first.value.finalized == final, "exact independently framed leaf claims"
  assert peers.requestStream(session, attempt, CurrentDownloadStreamLimits(readBytes: ByteLimit(73),
    writeBytes: ByteLimit(3), timeout: CurrentDownloadTimeout(1000)), CurrentDownloadTick(100)) ==
        CurrentDownloadPeerError.None
  let ceStarted = getMonoTime()
  while peers.busy or session.streamActive or session.stage == CurrentBlockDownloadStage.Receiving:
    assert (getMonoTime() - ceStarted).inMilliseconds < 2000, "CE128 completes alongside persistent UP0"
    server.tick(peers)
  assert session.stage == CurrentBlockDownloadStage.Empty, "empty reply remains ordinary lack of current work"
  assert peers.announcements(DownloadPeerId(1)).available
  assert peers.announcements(DownloadPeerId(1)).value.sequence == 1
  assert session.discardInput(attempt).error == CurrentDownloadSessionError.None
  assert session.finish(attempt, DownloadAttemptOutcome.Empty, DownloadScheduleTick(200)).error ==
      CurrentDownloadSessionError.None
  let generation = peers.incarnation(DownloadPeerId(1))
  assert generation > 0, "live stream provenance generation"
  var copied = first.value
  copied.leaves[0] = localLeaf
  assert peers.announcements(DownloadPeerId(1)).value.leaves[0] == far, "snapshot mutation cannot change retained source"
  # A descendant announcement supersedes its parent leaf without treating its slot gap as block count.
  var rawHeader = newSeq[byte](297)
  rawHeader[0] = array[32, byte](far.hash)[0]
  rawHeader[96] = byte(10001 and 255)
  rawHeader[97] = byte(10001 shr 8)
  var body = rawHeader
  for value in record(final): body.add(value)
  server.output = framed(body)
  server.offset = 0
  wantWrite(server.stream, 1)
  let second = server.awaitView(peers, 2)
  assert second.value.leaves.len == 1 and uint32(second.value.leaves[0].slot) == 10001, "descendant replaces its announced parent leaf"
  let decoded = decodeHeader(rawHeader, config)
  assert decoded.error == HeaderError.None, "independent structural header"
  let before = server.input.len
  assert peers.publishAnnouncement(decoded.value.owner, final) == AnnouncementError.None, "host-side publication enqueue"
  let start = getMonoTime()
  while server.input.len < before + body.len + 4 and (getMonoTime() - start).inMilliseconds < 2000:
    server.tick(peers)
  assert server.input.len == before + body.len + 4, "host publication extent"
  let expected = framed(body)
  for index in 0..<expected.len: assert server.input[before + index] == expected[index], "host publication body"
  streamFin(server.stream) # A persistent-stream EOF revokes claims even after complete messages.
  let ended = getMonoTime()
  while peers.announcements(DownloadPeerId(1)).available and (getMonoTime() -
      ended).inMilliseconds < 2000:
    server.tick(peers)
  assert not peers.announcements(DownloadPeerId(1)).available, "UP0 FIN cannot imply synchronization"
  assert peers.disconnectPeers() == CurrentDownloadPeerError.None, "begin graceful source retirement"
  assert not peers.announcements(DownloadPeerId(1)).available, "retired/invalid source must revoke view"
  let draining = getMonoTime()
  while peers.count > 0 and (getMonoTime() - draining).inMilliseconds < 2000:
    server.tick(peers)
    assert peers.disconnectPeers() == CurrentDownloadPeerError.None, "drain actual native connection close"
  assert peers.count == 0, "graceful UP0 retirement"
  # An identical target on a new transport/stream is a new provenance incarnation.
  server.output = framed(handshake(final, far))
  server.expected = framed(handshake(final, second.value.leaves[0]), true)
  assert peers.openPeer(DownloadPeerId(1), peerKey(), server.transport.localPort,
    getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None, "opening pinned discovery peer"
  discard server.awaitView(peers, 1)
  assert peers.incarnation(DownloadPeerId(1)) > generation, "new stream incarnation"
  # Oversized E4 after a valid handshake immediately revokes the formerly available target.
  server.output = @[255'u8, 255, 255, 255]
  server.offset = 0
  wantWrite(server.stream, 1)
  let malformed = getMonoTime()
  while peers.announcements(DownloadPeerId(1)).available and
      (getMonoTime() - malformed).inMilliseconds < 2000:
    server.tick(peers)
  assert not peers.announcements(DownloadPeerId(1)).available, "retired/invalid source must revoke view"
  assert peers.retire(DownloadPeerId(1)), "retire malformed source endpoint"
  assert peers.openPeer(DownloadPeerId(1), peerKey(true), server.transport.localPort,
    getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.DuplicatePeer, "reserved identity cannot be rebound"
  var refused = default(CurrentDownloadPeers)
  defer: refused.close()
  assert refused.configure(ElementLimit(1)) == CurrentDownloadPeerError.None
  assert refused.enableAnnouncements(local, limits) == CurrentDownloadPeerError.None
  assert refused.openPeer(DownloadPeerId(1), peerKey(true), server.transport.localPort,
    getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None
  let rejected = getMonoTime()
  while not refused.identityRejected(DownloadPeerId(1)) and (getMonoTime() -
      rejected).inMilliseconds < 2000:
    server.tick(refused)
  assert refused.identityRejected(DownloadPeerId(1)), "wrong peer key must be rejected"
  assert not refused.announcements(DownloadPeerId(1)).available, "unauthenticated sources have no targets"
  peers.close()
  assert not peers.announcements(DownloadPeerId(1)).available, "retired/invalid source must revoke view"
try:
  main() # Fixture file/IO failures remain failed tests, never inferred absence of sync work.
except:
  quit(2)
echo "PASS sync discovery: pinned UP0, fragments, updates, source retirement and wrong identities"
