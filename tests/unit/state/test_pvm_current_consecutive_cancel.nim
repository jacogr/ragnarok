# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A real adopted prefix survives later uncollected-Done cancellation, joined preparation and a cancelled pending handoff.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/download/schedule as download_schedule
import ../../../src/app/preparation_worker
import "../../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
import "../../../src/jamnp-s/current/block/download/peers" as current_block_download_peers
import "../../../src/jamnp-s/current/block/download/stream" as current_block_download_stream
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/state/store
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/rpc/server
import ../../support/[current_application_context, current_services_disk_samples,
  block_download_transport, current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  current_download_command_context, managed_storage_samples]
type LoopWitness {.pure.} = enum ## Explicit stages distinguish actual adoption from unwanted/lost execution or handoff.
  CancelDone, Joined, LostHandoff
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
proc assertPreparationLease(owner: Services) =
  ## Observe the actual managed lease without teaching the compiler stale facts about pointer-owned dispatcher mutations.
  assert owner.preparationActive and owner.rpc.chainPaused
proc transfer(fixture: CurrentConsecutiveFixture, witness: LoopWitness, disk,
    managed: bool) {.raises.} =
  ## A second real TLS/current execution reaches the retirement stage after the first child is confirmed.
  var path = "pvm-current-consecutive-cancel-chain"
  var database = "pvm-current-consecutive-cancel-state"
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
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(100)
  assert dispatcher.configure(owner, @[DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), key(true), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
      CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted)
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  let parent = owner.stateSnapshot.value
  assert not sameStateSnapshot(original, parent)
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Preparing, 1)
  assertPreparationLease(owner)
  assert not dispatcher.completed
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    assert servers.poll()
    yieldCurrentDiskThread() # Deliberately leave Done uncollected until the authored producer action.
  if witness == LoopWitness.CancelDone:
    assert dispatcher.tick(CurrentDownloadLoopTick(101)) == CurrentDownloadLoopError.None
    assert dispatcher.stage == CurrentDownloadLoopStage.Cancelling
    assertPreparationLease(owner)
    dispatcher.advance(servers, CurrentDownloadLoopStage.Exhausted, 101)
    assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  elif witness == LoopWitness.Joined:
    dispatcher.close()
    assert dispatcher.stage == CurrentDownloadLoopStage.Closed and not owner.preparationActive
    assert not owner.rpc.chainPaused and owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  else:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Queued, 1)
    assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
    if witness == LoopWitness.LostHandoff:
      assert owner.cancelCurrentAccumulation()
      assert dispatcher.tick(CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.LostHandoff
      assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
  dispatcher.close()
  assert not owner.preparationActive and not owner.rpc.chainPaused
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  assert servers.requestCount(true) == 2 and servers.requestCount(false) == 0
  assert owner.chainView.retainedCount == 2
  servers.close()
  owner.close()
  if disk:
    assert owner.start(options, "strict prefix restart after later cancellation")
    equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
    assert owner.chainView.retainedCount == 2
    owner.close()

proc main() {.raises.} =
  ## Each producer retirement mode follows a real first adoption in memory and both durable layouts.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for fixture in [currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value, 2),
      currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value, 2)]:
    for witness in [LoopWitness.CancelDone, LoopWitness.Joined, LoopWitness.LostHandoff]:
      transfer(fixture, witness, false, false)
      transfer(fixture, witness, true, false)
      transfer(fixture, witness, true, true)
try:
  main()
except:
  quit(2) # Later cancellation cannot undo a confirmed prefix or authorize the unwanted second child.
echo "PVM current consecutive cancel passed"
