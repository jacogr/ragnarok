# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Clock, ancestor-count, malformed-header and byte-budget rearm refusals preserve actual adopted authority before genuine continuation.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/download/schedule as download_schedule
import ../../../src/app/preparation_worker
import "../../../src/quic/current/block/download/loop" as current_block_download_loop
import "../../../src/quic/current/block/download/peers" as current_block_download_peers
import "../../../src/quic/current/block/download/stream" as current_block_download_stream
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/rpc/server
import ../../support/[current_application_context, current_services_disk_samples,
  block_download_transport, current_consecutive_context, current_consecutive_download_context,
  current_download_command_context, managed_storage_samples]
proc key(second: bool): CurrentDownloadPeerKey {.raises.} =
  ## Authenticated host identities come from the two independent local fixture certificates.
  let raw = readFile(getEnv(if second: "RAGNAROK_TEST_PEER_B" else: "RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  CurrentDownloadPeerKey(bytes)
proc advance(dispatcher: var CurrentDownloadLoop, servers: var DownloadResponders,
    target: CurrentDownloadLoopStage, now = 0'u64) =
  ## Bounded native polling preserves the authored monotonic deadline until this exact stage is observed.
  let started = getMonoTime()
  while dispatcher.stage != target:
    assert (getMonoTime()-started).inSeconds < 20, "bounded current dispatcher stage " & $target
    assert servers.poll()
    assert dispatcher.tick(CurrentDownloadLoopTick(now)) == CurrentDownloadLoopError.None
    yieldCurrentDiskThread() # Independent scheduler yield touches no leased canonical/input aliases.
proc transfer(fixture: CurrentConsecutiveFixture, disk, managed: bool) {.raises.} =
  ## Invalid replacement contexts cannot consume the first adopted receipt or prevent a later valid successor.
  var path = "pvm-current-consecutive-rearm-chain"
  var database = "pvm-current-consecutive-rearm-state-" & $getMonoTime().ticks
  let context = fixture.seed
  writeFile(path, context.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if disk:
      if managed: removeManagedSample(database, [ManagedEpoch(1)])
      else: discard posix.unlink(database.toCString()) # Join all owners before retiring exact test-owned storage.
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # Dispatcher ends its exclusive Services borrow before canonical shutdown.
  let port = 0'u16
  var options = default(Options)
  if disk:
    options = currentDiskOptions(path, database, managed, port)
  else:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current dispatcher")
  let original = owner.stateSnapshot.value
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  for index in 0..1:
    requests.add(currentExpectedRequest(array[32, byte](fixture.heads[index].blockHash)))
    responses.add(currentConsecutiveResponse(fixture.children[index]))
  assert servers.openSequenceResponders(requests, responses, @[Healthy, Healthy])
  var policy = currentConsecutivePolicy()
  policy.input.ancestorBytes = ByteLimit(1) # Empty child inputs need no older headers; attempted replacement headers must still be charged.
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(100)
  assert dispatcher.configure(owner, @[DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), key(true), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
      CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, 10)
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  let parent = owner.stateSnapshot.value
  assert not sameStateSnapshot(original, parent)
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(9)) ==
      CurrentDownloadLoopError.ClockRegression
  assert dispatcher.completed
  let confirmed = dispatcher.adoption
  assert confirmed.error == CurrentHandoffError.None
  assert array[32, byte](confirmed.value.blockHash) == array[32, byte](fixture.heads[1].blockHash)
  var excessive: seq[OwnedHeader] = @[]
  for index in 0..8:
    excessive.add(fixture.heads[0].header) # Whole-count refusal must preserve the consumed first receipt.
  assert dispatcher.nextChild(excessive, CurrentDownloadLoopTick(11)) ==
      CurrentDownloadLoopError.InvalidPolicy
  assert dispatcher.completed
  assert dispatcher.nextChild([default(OwnedHeader)], CurrentDownloadLoopTick(11)) ==
      CurrentDownloadLoopError.InvalidPolicy
  assert dispatcher.completed
  assert dispatcher.nextChild([fixture.heads[0].header], CurrentDownloadLoopTick(11)) ==
      CurrentDownloadLoopError.InvalidPolicy
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  assert servers.requestCount(true) == 1
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(11)) == CurrentDownloadLoopError.None
  assert not dispatcher.completed and dispatcher.stage == CurrentDownloadLoopStage.Waiting
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(11)) == CurrentDownloadLoopError.Busy
  assert servers.requestCount(true) == 1 # Rearming alone never opens a new request or executes a candidate.
  dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, 11)
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[2].stateSnapshot)
  assert servers.requestCount(true) == 2 and servers.requestCount(false) == 0
  dispatcher.close()
  servers.close()
  owner.close()
  if disk:
    assert owner.start(options, "strict restart after refused rearm and genuine continuation")
    assert owner.chainView.retainedCount == 3
    for index in 0..2:
      let actual = owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      assert array[32, byte](actual.blockHash) == array[32, byte](fixture.heads[index].blockHash)
      equalCurrentDiskMap(actual.stateSnapshot, fixture.heads[index].stateSnapshot)
    owner.close()

proc main() {.raises.} =
  ## Actual first-child receipts qualify atomic rearm validation in memory and both durable layouts.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value, 2)
  transfer(fixture, false, false)
  transfer(fixture, true, false)
  transfer(fixture, true, true)

try:
  main()
except:
  quit(2) # A refused rearm cannot consume a confirmed receipt or fabricate successor progress.
echo "PVM current consecutive rearm passed"
