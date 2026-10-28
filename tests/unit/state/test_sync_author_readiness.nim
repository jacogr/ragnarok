# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real production UP0/CE128 serving and shared full-state evidence gate participation independently of idle work.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../../src/app/[tiny_genesis, block_author, chain, candidate, download_schedule,
    services, options, current_block_input]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, block_codec, state_trie]
import ../../../src/quic/[devnet, sync_targets, announcements, current_block_download_peers,
    current_sync, current_block_download_loop, current_block_download_stream]
import ../../../src/state/[store, accumulation_current_update]
import ../../../src/bandersnatch/bandersnatch
import ../../support/current_consecutive_context

proc key(path: string): array[32, byte] {.raises.} =
  ## Native fixture certificates expose exact public principals; no process-global private key is decoded here.
  let raw = readFile(path)
  assert raw.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(raw[index])
proc stamp(head: BlockSnapshot): AnnouncedBlock =
  ## Use actual independently installed header identities as untrusted wire target records.
  AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](head.blockHash)), slot: HeaderSlot(head.slot))
proc sample(targets: var SyncTargets, peers: CurrentDownloadPeers, view: ChainView,
    now: uint64, pending = false): SyncTargetProgress =
  ## Every permission decision requires a new source-sampling turn against the actual full selected view.
  assert targets.beginTurn(now)
  assert targets.observePeer(DownloadPeerId(1), peers.incarnation(DownloadPeerId(1)),
    peers.announcements(DownloadPeerId(1)))
  if pending: targets.pending() else: targets.evaluate(view)
proc awaitSequence(server: var DevnetNetwork, peers: var CurrentDownloadPeers, sequence: uint64) =
  ## Real TLS/frame delivery is bounded independently of the authored monotonic freshness boundary.
  let started = getMonoTime()
  while true:
    assert (getMonoTime() - started).inSeconds < 5, "bounded production UP0 message"
    assert server.poll()
    discard peers.poll()
    let snapshot = peers.announcements(DownloadPeerId(1))
    if snapshot.available and snapshot.value.sequence >= sequence: return

proc main() {.raises.} =
  ## A signed child at slot2 is one actual block; neither a live handshake nor pending/empty work grants readiness.
  let genesis = initTinyGenesis()
  assert genesis.error == GenesisError.None
  var storage = genesisStoreLimits()
  storage.writes = ElementLimit(1000)
  storage.writeValueBytes = ByteLimit(1048576)
  let initial = initApplicationChain(tinyChainText(genesis.value), storage)
  assert initial.error == ApplicationChainError.None
  var remote = initial.value
  let policies = currentConsecutiveLimits()
  let secret = tinySigningKey(2)
  assert secret.error == BsError.None
  let authored = authorEmptyBlock(genesis.value, HeaderSlot(2), secret.value,
    policies.reporting.admission.frame, policies.reporting.safrole)
  assert authored.error == BlockAuthorError.None
  let prepared = prepareCurrentCandidate(remote, authored.value, [], policies)
  assert prepared.error == CurrentCandidateError.None
  remote.installPrepared(prepared.value)
  let child = remote.chainView.bestBlock.value
  var wire = newSeq[byte](65536)
  let encoded = encodeOwnedBlock(authored.value, wire)
  assert encoded.error == FrameError.None
  wire.setLen(encoded.value)
  var server = default(DevnetNetwork)
  var peers = default(CurrentDownloadPeers)
  var host = default(CurrentSync)
  var owner = default(Services)
  defer:
    host.close()
    peers.close()
    server.close()
    owner.close()
  let resource = policies.reporting.reports.ancestors.header
  let limits = AnnouncementLimits(leaves: ElementLimit(4), bytes: ByteLimit(65536),
      header: resource)
  let anchor = stamp(genesis.value)
  let local = AnnouncementHandshake(finalized: anchor, leaves: @[])
  assert server.enableAnnouncements(AnnouncementHandshake(finalized: anchor, leaves: @[stamp(child)]),
    limits) == AnnouncementError.None
  assert server.publish(array[32, byte](genesis.value.blockHash), wire)
  var principals = default(array[6, array[32, byte]])
  principals[0] = key(getEnv("RAGNAROK_TEST_PEER_A"))
  assert server.open(0, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"),
    "jamnp-s/1/00000000", principals)
  assert peers.configure(ElementLimit(1)) == CurrentDownloadPeerError.None
  assert peers.enableAnnouncements(local, limits) == CurrentDownloadPeerError.None
  var targets = default(SyncTargets)
  assert targets.configure(initial.value.chainView, @[DownloadPeerId(1)], 30, 100)
  let absent = targets.sample(peers, initial.value.chainView, 100)
  assert absent.stage == CurrentSyncStage.Unknown and not absent.fullReady
  assert not absent.lightReady
  assert peers.openPeer(DownloadPeerId(1), CurrentDownloadPeerKey(key(getEnv(
      "RAGNAROK_TEST_PEER_B"))),
    server.localPort, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000") == CurrentDownloadPeerError.None
  server.awaitSequence(peers, 1)
  let behind = targets.sample(peers, initial.value.chainView, 100)
  assert behind.stage == CurrentSyncStage.CatchingUp and not behind.fullReady
  assert behind.hasTarget and behind.target == stamp(child)
  assert server.request(server.localPort, key(getEnv("RAGNAROK_TEST_PEER_B")),
    array[32, byte](child.blockHash), getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000")
  let emptyStarted = getMonoTime()
  while not server.finished:
    assert (getMonoTime() - emptyStarted).inSeconds < 5, "bounded production empty CE response"
    assert server.poll()
    discard peers.poll()
  var empty: seq[byte] = @[]
  assert server.take(empty) and empty.len == 0 # A real E4-zero empty message is ordinary lack of children.
  server.closeRequest()
  assert not targets.sample(peers, initial.value.chainView, 100).fullReady
  assert not targets.sample(peers, remote.chainView, 100, pending = true).fullReady
  let reached = targets.sample(peers, remote.chainView, 100)
  assert reached.fullReady and not reached.lightReady
  assert targets.sample(peers, remote.chainView, 129).fullReady
  assert not targets.sample(peers, remote.chainView, 130).fullReady # Repeated polling is not a new peer message.
  assert not targets.beginTurn(129)
  assert not targets.evaluate(remote.chainView).fullReady # Ignoring a regressed clock cannot resurrect an earlier permission.
  assert server.publishAnnouncement(child.header, anchor) == AnnouncementError.None
  server.awaitSequence(peers, 2)
  assert targets.sample(peers, remote.chainView, 140).fullReady
  var absentView = default(ChainView) # Keep the nested tagged default outside the call boundary on the pinned compiler.
  assert not targets.recordInstalled(absentView)
  assert not targets.progress.fullReady # A refused canonical recording revokes the previous permission immediately.

  # The production server must multiplex an actual current download alongside persistent UP0.
  var path = "sync-author-chain.json"
  writeFile(path, tinyChainText(genesis.value))
  defer: discard posix.unlink(path.toCString())
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "production announcement server")
  let execution = CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(5)), input: CurrentBlockInputLimits(
        blockBytes: ByteLimit(65536)),
    candidate: policies, stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(73),
        writeBytes: ByteLimit(3),
      timeout: CurrentDownloadTimeout(1000)), attemptTimeout: CurrentDownloadAttemptTimeout(5000))
  assert host.configure(owner, @[DownloadPeerId(1)], @[], CurrentSyncLimits(download: execution,
    announcements: limits, sourceAgeMs: 30000, reconnectMs: 5000), CurrentDownloadLoopTick(0)) ==
        CurrentSyncError.None
  assert host.openPeer(DownloadPeerId(1), CurrentDownloadPeerKey(key(getEnv(
      "RAGNAROK_TEST_PEER_B"))),
    server.localPort, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000") == CurrentDownloadPeerError.None
  let started = getMonoTime()
  while not host.progress.fullReady:
    assert (getMonoTime() - started).inSeconds < 10, "production UP0 and CE128 adoption"
    assert server.poll()
    discard peers.poll()
    assert host.tick(CurrentDownloadLoopTick(0)) == CurrentSyncError.None
    var pause = Timespec(tv_sec: posix.Time(0), tv_nsec: 100000)
    var remaining = default(Timespec)
    discard nanosleep(pause, remaining)
  assert host.progress.adoptedBlocks == 1 and uint32(host.progress.localHead.slot) == 2
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](
      child.stateSnapshot.commitment.root)
  host.close()

  var conflicting = newSeq[byte](child.header.headerInfo.value.consumed)
  assert child.header.encodeOwnedHeader(conflicting).error == HeaderError.None
  conflicting[conflicting.len - 1] = conflicting[conflicting.len - 1] xor 1
  let fork = decodeHeader(conflicting, resource)
  assert fork.error == HeaderError.None
  assert server.publishAnnouncement(fork.value.owner, anchor) == AnnouncementError.None
  server.awaitSequence(peers, 3)
  let blocked = targets.sample(peers, remote.chainView, 141)
  assert blocked.stage == CurrentSyncStage.Blocked and not blocked.fullReady
  assert not targets.recordInstalled(initial.value.chainView) # No stale or fabricated parent replacement can authorize a new turn.
  peers.close()
  assert not targets.sample(peers, remote.chainView, 142).fullReady
try:
  main()
except:
  quit(2) # Genuine protocol, signature, state, lifecycle or native failures cannot satisfy readiness.
echo "PASS author readiness: real targets, canonical imports, expiry, conflicts and pending-work exclusion"
