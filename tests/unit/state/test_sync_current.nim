# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS discovery and complete-state current admission catch up beyond finite command limits.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils]
import std/posix/posix
import ../../../src/app/current/download/[command as current_download_command,
    policy as current_download_policy]
import ../../../src/app/sync_logging
import ../../../src/lib/logging
import "../../../src/app/block/author" as block_author
import ../../../src/app/[tiny_genesis, chain, candidate, services, options]
import ../../../src/app/download/schedule as download_schedule
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/download/[command as current_download_command,
    policy as current_download_policy]
import "../../../src/jamnp-s/current/sync" as current_sync
import "../../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
import "../../../src/jamnp-s/current/block/download/peers" as current_block_download_peers
import "../../../src/jamnp-s/current/block/download/stream" as current_block_download_stream
import "../../../src/jamnp-s/announcements"
import ../../../src/codec/[bounded, header, block_codec]
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/assurances
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/bandersnatch/bandersnatch
import ../../support/[current_consecutive_context, sync_transport]

proc collectLog(raw: nil pointer, batch: string) {.raises: [].} =
  ## The writer alone mutates captured bytes; the test reads them only after joined close.
  let text = cast[ptr string](raw)
  text[].add(batch)

proc admitLog(state: var SyncLogState, logger: var Logger, progress: CurrentSyncProgress,
    now: uint64) =
  ## Tests retry only queue contention, restoring reporter history so admission is deterministic.
  let before = state
  let accepted = logger.stats.accepted
  for attempt in 0..<1000:
    state = before
    state.logSyncProgress(logger.writer, progress, now)
    if logger.stats.accepted > accepted: return
    sleep(1)
  assert false, "bounded sync log admission"

proc checkLog(progress: CurrentSyncProgress, expected: string,
    severity = LogLevel.Info) =
  ## Actual host samples test guarded unknown targets, sparse slots and readiness refusal labels.
  var text = ""
  var logger = default(Logger)
  assert start(logger, initLogPolicy(severity), collectLog, addr text)
  var status = default(SyncLogState)
  status.admitLog(logger, progress, 1000)
  # Neither a hot dispatcher nor a regressed diagnostic clock may flood default output.
  for turn in 0..<1000: status.logSyncProgress(logger.writer, progress, 1000)
  status.logSyncProgress(logger.writer, progress, 999)
  assert logger.stats.accepted == 1
  status.admitLog(logger, progress, 6000)
  close(logger)
  assert logger.stats.processed == 2
  assert expected in text, text
  assert "light ready: true" notin text and "authoring gate: open" notin text, text
  # Component-level warning/off filters must precede record creation.
  text = ""
  var policy = default(LogPolicy)
  assert parseLogPolicy("info,startup=off", policy)
  assert start(logger, policy, collectLog, addr text)
  status = default(SyncLogState)
  status.logSyncProgress(logger.writer, progress, 0)
  close(logger)
  assert text.len == 0 and logger.stats.accepted == 0

proc checkFirstReady(unknown, ready: CurrentSyncProgress) =
  ## A genuine rapid catch-up must report readiness before the ordinary one-second transition limit.
  assert not unknown.fullReady and ready.fullReady
  var text = ""
  var logger = default(Logger)
  assert start(logger, initLogPolicy(), collectLog, addr text)
  var status = default(SyncLogState)
  status.admitLog(logger, unknown, 1000)
  status.admitLog(logger, ready, 1999)
  status.logSyncProgress(logger.writer, ready, 2000)
  assert logger.stats.accepted == 2
  close(logger)
  assert "Waiting for sync target" in text and "Idle (caught up to observed peer targets)" in text

proc currentPid(): posix.Pid {.importc: "getpid", header: "<unistd.h>".}
  ## The isolated responder signals its original parent through libc's actual pid_t ABI.
let interruptSignal {.importc: "SIGINT", header: "<signal.h>".}: cint

proc claim(head: BlockSnapshot): AnnouncedBlock =
  ## Only real independently installed fixture heads become advertised target scalars.
  AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](head.blockHash)),
    slot: HeaderSlot(head.slot))
proc peerKey(): CurrentDownloadPeerKey {.raises.} =
  ## The client pins the actual second fixture principal, independently of server-side validation.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert raw.len == 32
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(raw[index])
  CurrentDownloadPeerKey(key)
proc limits(): CurrentSyncLimits =
  ## Keep a tiny rolling ancestry window while allowing arbitrarily many actual imports.
  CurrentSyncLimits(download: CurrentDownloadLoopLimits(
    schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 2,
      retryDelay: DownloadRetryDelay(5)),
    input: CurrentBlockInputLimits(blockBytes: ByteLimit(65536), ancestors: ElementLimit(2),
      ancestorBytes: ByteLimit(8192)), candidate: currentConsecutiveLimits(),
    stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: CurrentDownloadTimeout(1000)), attemptTimeout: CurrentDownloadAttemptTimeout(5000)),
    announcements: AnnouncementLimits(leaves: ElementLimit(4), bytes: ByteLimit(65536),
      header: HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
        epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096))),
    sourceAgeMs: 300000, reconnectMs: 1000)
proc advance(host: var CurrentSync, server: var SyncResponder, target: CurrentSyncStage,
    now: var uint64) =
  ## Native and worker scheduling use a real bounded deadline; logical time is independently controlled.
  let started = getMonoTime()
  while host.progress.stage != target:
    assert (getMonoTime() - started).inSeconds < 60, "bounded sync stage " & $target & " actual=" &
        $host.progress.stage &
      " adopted=" & $host.progress.adoptedBlocks & " sources=" & $host.progress.liveSources &
      " requests=" & $server.requests
    server.poll()
    let status = host.tick(CurrentDownloadLoopTick(now))
    if status != CurrentSyncError.None: echo "sync refusal ", $status
    assert status == CurrentSyncError.None
    var pause = Timespec(tv_sec: posix.Time(0), tv_nsec: 100000)
    var remaining = default(Timespec)
    discard nanosleep(pause, remaining) # Yield to the actual bounded preparation pool without touching its borrowed graph.

proc commandRound(initial: BlockSnapshot, wires: seq[SyncWireBlock], expected: BlockSnapshot,
    chainPath, policyPath, stopPath, database: string, requested: int) {.raises.} =
  ## Start a real foreground lifetime and inspect its outbound Final before either initial or resumed shutdown.
  var server = default(SyncResponder)
  defer: server.close()
  server.catalog = wires
  server.expectedHeader = newSeq[byte](expected.header.headerInfo.value.consumed)
  assert expected.header.encodeOwnedHeader(server.expectedHeader).error == HeaderError.None
  let port = server.open(claim(initial), @[claim(expected)])
  let parent = currentPid()
  let child = posix.fork()
  assert int(child) >= 0, "foreground responder process"
  if int(child) == 0:
    let started = getMonoTime()
    var sent = false
    var validAnchor = false
    while not fileExists(stopPath) and (getMonoTime() - started).inSeconds < 20:
      server.poll()
      let observed = server.targetObserved or (requested == 0 and server.handshakes > 0)
      if observed and not sent:
        validAnchor = server.receivedFinal == claim(
            initial) # Disk restart must retain the original independent Final, never promote restored bestBlock.
        assert posix.kill(parent, interruptSignal) == 0
        sent = true # Only an exact canonical publication message triggers the normal foreground interruption.
      var pause = Timespec(tv_sec: posix.Time(0), tv_nsec: 100000)
      var remaining = default(Timespec)
      discard nanosleep(pause, remaining)
    if not sent:
      discard posix.kill(parent, SIGTERM) # A failed positive control cannot hang the foreground command forever.
    server.close()
    posix.exitnow(cint(if sent and validAnchor: 0 else: 3)) # Never run destructors over inherited parent ARC/native owners after fork.
  server.close() # Parent drops only its private listener copy before starting native workers and outgoing engines.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0)
  var options = default(Options)
  assert parseCanonicalOptions(@["sync-current", $port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), getEnv("RAGNAROK_TEST_PEER_B"), "jamnp-s/1/00000000", "10000",
    policyPath, "--with-state", "--chain", chainPath, "--state-storage", "disk", "--state-db",
        database], options)
  var text = ""
  var logger = default(Logger)
  assert start(logger, initLogPolicy(), collectLog, addr text)
  defer: close(logger) # No writer exists in the child fork; parent Services retire before joined logging.
  options.attachLogWriter(logger.writer)
  let outcome = runCurrentSync(options)
  close(logger)
  var missing = 0'u64
  for expected in ["Continuous sync started; pinned peers: 1", "Sync peer 1: 127.0.0.1:",
      "full state ready:", "Continuous sync Stopped; imported: " & $requested & " blocks"]:
    if expected notin text: inc missing
  # Integration output remains deliberately best effort; isolated reporter tests prove exact records.
  assert missing <= logger.stats.dropped, text
  assert "light ready: true" notin text, text
  writeFile(stopPath, "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "foreground independent source joined"
  assert outcome.error == CurrentDownloadCommandResult.Stopped and outcome.requestedBlocks == 0
  assert outcome.adoptedBlocks == requested, "signal stop preserves the actual imported prefix"

proc commandCheck(initial: BlockSnapshot, wires: seq[SyncWireBlock],
    expected: BlockSnapshot) {.raises.} =
  ## Initial import and a fresh sync restart must advertise the same independent checkpoint Final.
  var chainPath = "sync-command-chain.json"
  var policyPath = "sync-command-policy.conf"
  var stopPath = "sync-command-stop"
  var database = "sync-command-state"
  defer:
    for name in [chainPath, policyPath, stopPath, database]:
      var path = name
      discard posix.unlink(path.toCString()) # Retire only exact test-owned files after joined command shutdown.
  for name in [chainPath, policyPath, stopPath, database]:
    var path = name
    discard posix.unlink(path.toCString()) # A deliberate regression failure must not poison the next isolated run.
  writeFile(chainPath, tinyChainText(initial))
  writeFile(policyPath, encodeCurrentDownloadPolicy(limits().download))
  commandRound(initial, wires, expected, chainPath, policyPath, stopPath, database, 2)
  discard posix.unlink(stopPath.toCString()) # The second isolated responder starts with fresh stop/evidence state.
  commandRound(initial, wires, expected, chainPath, policyPath, stopPath, database, 0)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", chainPath,
    "--state-storage", "disk", "--state-db", database], options)
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(options, "continuous durable restart")
  let anchor = reopened.startupBlockAnchor
  assert anchor.available and array[32, byte](anchor.blockHash) == array[32, byte](
      initial.blockHash)
  assert uint32(anchor.slot) == initial.slot
  assert array[32, byte](reopened.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.blockHash)
  assert array[32, byte](reopened.stateSnapshot.value.commitment.root) == array[32, byte](
      expected.stateSnapshot.commitment.root)

proc finalizedTargetCheck(initial: BlockSnapshot, wires: seq[SyncWireBlock],
    expected: BlockSnapshot) {.raises.} =
  ## A legal empty leaf list still names an untrusted Final target; only actual full imports can satisfy it.
  var path = "sync-final-target-chain.json"
  writeFile(path, tinyChainText(initial))
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var host = default(CurrentSync)
  var server = default(SyncResponder)
  defer:
    host.close()
    server.close()
    owner.close()
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "untrusted finalized target")
  assert host.configure(owner, @[DownloadPeerId(1)], @[], limits(), CurrentDownloadLoopTick(0)) ==
      CurrentSyncError.None
  server.catalog = wires
  let port = server.open(claim(expected), @[])
  assert host.openPeer(DownloadPeerId(1), peerKey(), port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") == CurrentDownloadPeerError.None
  var now = 0'u64
  host.advance(server, CurrentSyncStage.CatchingUp, now)
  assert host.progress.adoptedBlocks == 0 and not host.progress.fullReady
  host.advance(server, CurrentSyncStage.CaughtUp, now)
  assert host.progress.adoptedBlocks == 2 and host.progress.localHead == claim(expected)
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](
      expected.stateSnapshot.commitment.root)
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  assert not host.progress.lightReady # Reaching a claimed Final neither finalizes locally nor grants light authority.

proc main() {.raises.} =
  ## Build 72 genuine signed/admitted children, then independently synchronize a second complete-state owner.
  let initial = initTinyGenesis()
  assert initial.error == GenesisError.None
  var storage = genesisStoreLimits()
  storage.writes = ElementLimit(1000)
  storage.writeValueBytes = ByteLimit(1048576)
  let loaded = initApplicationChain(tinyChainText(initial.value), storage)
  assert loaded.error == ApplicationChainError.None
  var chain = loaded.value
  var wires: seq[SyncWireBlock] = @[]
  var heads: seq[BlockSnapshot] = @[]
  let policies = currentConsecutiveLimits()
  for ordinal in 1..72:
    let parent = chain.chainView.bestBlock.value
    var child = default(OwnedBlock)
    var eligible = 0
    for index in 0..<6:
      let key = tinySigningKey(index)
      assert key.error == BsError.None
      let authored = authorEmptyBlock(parent, HeaderSlot(uint32(ordinal * 2)), key.value,
        policies.reporting.admission.frame, policies.reporting.safrole)
      if authored.error == BlockAuthorError.None:
        child = authored.value
        inc eligible
      else:
        assert authored.error == BlockAuthorError.NotEligible
    assert eligible == 1, "one true eligible signer for each sparse slot"
    var bytes = newSeq[byte](65536)
    let encoded = encodeOwnedBlock(child, bytes)
    assert encoded.error == FrameError.None
    bytes.setLen(encoded.value)
    let prepared = prepareCurrentCandidate(chain, child, [], policies)
    assert prepared.error == CurrentCandidateError.None
    chain.installPrepared(prepared.value)
    wires.add(SyncWireBlock(parent: array[32, byte](parent.blockHash), bytes: bytes))
    heads.add(chain.chainView.bestBlock.value)
  commandCheck(initial.value, wires, heads[1])
  finalizedTargetCheck(initial.value, wires, heads[1])
  var path = "sync-current-genesis.json"
  writeFile(path, tinyChainText(initial.value))
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var host = default(CurrentSync)
  var server = default(SyncResponder)
  defer:
    host.close()
    server.close()
    owner.close() # Joined callbacks and workers precede release of either canonical owner.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "continuous full sync")
  assert host.configure(owner, @[DownloadPeerId(1)], @[], limits(), CurrentDownloadLoopTick(0)) ==
      CurrentSyncError.None
  for turn in 0..<4: assert host.tick(CurrentDownloadLoopTick(0)) == CurrentSyncError.None
  assert host.progress.stage == CurrentSyncStage.Unknown and not host.progress.fullReady
  assert not host.progress.lightReady and host.progress.adoptedBlocks == 0
  let unsynchronized = host.progress
  checkLog(host.progress, "Waiting for sync target")
  checkLog(host.progress, "peer target: unknown, lag: unknown")
  server.catalog = wires
  let port = server.open(claim(initial.value), @[claim(heads[67])])
  assert host.openPeer(DownloadPeerId(1), peerKey(), port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") == CurrentDownloadPeerError.None
  server.empty = true
  var now = 0'u64
  host.advance(server, CurrentSyncStage.CatchingUp, now)
  checkLog(host.progress, "lag: 136 slots")
  let started = getMonoTime()
  while server.requests < 4:
    assert (getMonoTime() - started).inSeconds < 20
    server.poll()
    inc now
    assert host.tick(CurrentDownloadLoopTick(now)) == CurrentSyncError.None, "continuous native host tick"
  assert not host.progress.fullReady and host.progress.adoptedBlocks == 0
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      initial.value.blockHash)
  server.empty = false
  server.corrupt = true
  while server.requests < 8:
    assert (getMonoTime() - started).inSeconds < 30, "invalid/partial catch-up bounded deadline"
    server.poll()
    inc now
    assert host.tick(CurrentDownloadLoopTick(now)) == CurrentSyncError.None, "continuous native host tick"
    assert host.progress.adoptedBlocks == 0 and not host.progress.fullReady
  server.corrupt = false
  # One actual import is still partial progress; a moving target is learned while catch-up runs.
  while host.progress.adoptedBlocks < 1:
    server.poll()
    inc now
    assert host.tick(CurrentDownloadLoopTick(now)) == CurrentSyncError.None, "continuous native host tick"
    assert (getMonoTime() - started).inSeconds < 30, "invalid/partial catch-up bounded deadline"
  assert not host.progress.fullReady
  server.announce(heads[69].header, claim(initial.value))
  # Exhaustion is renewed only after the independently controlled retry delay.
  host.advance(server, CurrentSyncStage.CaughtUp, now)
  assert host.progress.fullReady and not host.progress.lightReady
  checkFirstReady(unsynchronized, host.progress)
  checkLog(host.progress, "imported: 70")
  checkLog(host.progress, "Idle (caught up to observed peer targets)")
  assert host.progress.adoptedBlocks == 70 and uint32(host.progress.localHead.slot) == 140
  assert host.progress.localHead == claim(heads[69])
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](heads[
      69].stateSnapshot.commitment.root)
  let requests = server.requests
  for turn in 0..<20:
    server.poll()
    assert host.tick(CurrentDownloadLoopTick(now)) == CurrentSyncError.None, "continuous native host tick"
  assert server.requests == requests, "caught-up host polls discovery without another CE input"
  server.announce(heads[71].header, claim(initial.value))
  host.advance(server, CurrentSyncStage.CatchingUp, now)
  host.advance(server, CurrentSyncStage.CaughtUp, now)
  assert host.progress.adoptedBlocks == 72 and host.progress.localHead == claim(heads[71])
  assert host.retainedAncestors == 2 and owner.chainView.retainedCount <= 64
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](heads[
      71].stateSnapshot.commitment.root)
  now += 300000
  assert host.tick(CurrentDownloadLoopTick(now)) == CurrentSyncError.None, "continuous native host tick"
  assert host.progress.stage == CurrentSyncStage.Unknown and not host.progress.fullReady
  host.advance(server, CurrentSyncStage.CaughtUp, now) # Expiry replacement requires a genuine fresh TLS/UP0 handshake.
  var conflicting = newSeq[byte](heads[71].header.headerInfo.value.consumed)
  assert heads[71].header.encodeOwnedHeader(conflicting).error == HeaderError.None
  conflicting[conflicting.len - 1] = conflicting[conflicting.len - 1] xor 1
  let competing = decodeHeader(conflicting, limits().announcements.header)
  assert competing.error == HeaderError.None
  server.announce(competing.value.owner, claim(initial.value))
  host.advance(server, CurrentSyncStage.Blocked, now)
  assert not host.progress.fullReady and host.progress.adoptedBlocks == 72
  checkLog(host.progress, "[warn][startup] Sync blocked", LogLevel.Warn)
  checkLog(host.progress, "lag: 0 slots", LogLevel.Warn)
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](heads[71].blockHash)
  server.disconnect()
  host.advance(server, CurrentSyncStage.Unknown, now)
  assert not host.progress.fullReady
  now += 1001
  host.advance(server, CurrentSyncStage.CaughtUp, now)
  assert host.progress.adoptedBlocks == 72 and host.progress.fullReady
  assert not host.progress.lightReady # Reconnection supplies new full source evidence, never light trust.
  assert now > 0
  assert host.tick(CurrentDownloadLoopTick(now - 1)) == CurrentSyncError.ClockRegression
  assert not host.progress.fullReady
  checkLog(host.progress, "[error][startup] Sync failed", LogLevel.Error)
  host.close()
  assert host.progress.stage == CurrentSyncStage.Closed and not host.progress.fullReady
  assert host.progress.liveSources == 0 and not host.progress.hasTarget
  checkLog(host.progress, "Sync stopped")
try:
  main()
except:
  quit(2) # Genuine TLS, state, signature, worker or ownership failure is never an expected control.
echo "PASS continuous sync: 72 canonical imports, sparse slots, live targets, empty retries and expiry"
