# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original report context after a real adoption resumes hash-free under the same clock/token, or preserves only the actually selected prefix.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options, chain]
import ../../../src/app/current/handoff as current_handoff
import "../../../src/app/current/block/download" as current_block_download
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/download/schedule as download_schedule
import "../../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
import "../../../src/jamnp-s/current/block/download/peers" as current_block_download_peers
import "../../../src/jamnp-s/current/block/download/session" as current_block_download_session
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/state/store
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/report/anchors as report_anchors
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/rpc/server
import ../../support/[current_guarantee_sequence_context, current_consecutive_context,
  current_consecutive_download_context, current_download_command_context,
  current_application_context,
  current_services_disk_samples, managed_storage_samples, block_download_transport]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Hash failures cover only synchronous resumption while every managed worker remains idle.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## The actual backend counter excludes a fabricated zero-work verdict.
type LookupCase {.pure.} = enum ## Each explicit host action follows the first genuine consumed adoption.
  Resume, Expire, ChangedParent
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

proc scenario(fixture: CurrentGuaranteeSequenceFixture, mode: LookupCase, layout: int) {.raises.} =
  ## Native report reception drains all connections before external original headers or a canonical replacement may be considered.
  var path = "pvm-current-guarantee-ancestry-chain"
  var database = "pvm-current-guarantee-ancestry-state-" & $getMonoTime().ticks
  writeFile(path, fixture.sequence.seed.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString())
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # The stable Services address survives every callback/input/worker borrower.
  var options = default(Options)
  if layout == 0:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  else:
    options = currentDiskOptions(path, database, layout == 2, 0)
  assert owner.start(options, "current guarantee ancestry after adoption")
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  for index in 0..1:
    requests.add(currentExpectedRequest(array[32, byte](fixture.sequence.heads[index].blockHash)))
    responses.add(currentConsecutiveResponse(fixture.sequence.children[index]))
  assert servers.openSequenceResponders(requests, responses, @[Healthy, Healthy])
  var policy = currentConsecutivePolicy()
  policy.input.discoverAncestors = true
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(100)
  assert dispatcher.configure(owner, @[DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), key(true), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
      CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted)
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.sequence.heads[1].stateSnapshot)
  let parent = owner.stateSnapshot.value
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.AwaitingAncestors, 1)
  assert not owner.preparationActive and not owner.diskPublicationActive
  assert dispatcher.readyPeers.len == 0 and not dispatcher.completed
  let demand = dispatcher.ancestorDemand
  assert demand.error == CurrentDownloadSessionError.None and demand.value.missingLookups.value > 0
  assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(1)) == 100
  assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(30)) == 71
  var expected = fixture.sequence.heads[1]
  if mode == LookupCase.ChangedParent:
    var live = initApplicationChain(owner.chainView).value
    let alternate = currentEmptyChild(owner.chainView.bestBlock.value)
    let replacement = phaseCurrentUpdate(live, alternate, fixture.ancestors,
        currentConsecutiveLimits())
    assert owner.enqueueCurrentAccumulation(replacement) == CurrentHandoffAdmission.None
    let started = getMonoTime()
    while owner.currentAccumulationPhase != CurrentHandoffPhase.Finished:
      assert (getMonoTime()-started).inSeconds < 20
      owner.tick(0)
      yieldCurrentDiskThread() # Only synchronized/scalar observations occur during an actual foreign publication.
    assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
    expected = replacement.currentUpdateChild
    failHash(1)
    assert dispatcher.resumeAncestors(fixture.ancestors, CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.SessionFailure
    assert dispatcher.stage == CurrentDownloadLoopStage.AwaitingAncestors
    let reason = dispatcher.sessionFailure
    assert reason.error == CurrentDownloadSessionError.DownloadFailure
    assert reason.downloadFailure.error == CurrentBlockDownloadError.InputFailure
    assert reason.downloadFailure.inputError == CurrentBlockInputError.StateChanged
    assert hashCalls() == 0 and not dispatcher.completed
    failHash(0)
  elif mode == LookupCase.Expire:
    assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(101)) == 0
    failHash(1)
    assert dispatcher.resumeAncestors(fixture.ancestors, CurrentDownloadLoopTick(101)) ==
        CurrentDownloadLoopError.AttemptExpired
    assert dispatcher.stage == CurrentDownloadLoopStage.Failed and not dispatcher.completed
    assert hashCalls() == 0
    failHash(0)
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  else:
    failHash(1)
    assert dispatcher.resumeAncestors([default(OwnedHeader)], CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.SessionFailure
    assert dispatcher.stage == CurrentDownloadLoopStage.AwaitingAncestors
    assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(30)) == 71
    var supplied = newSeq[OwnedHeader](fixture.ancestors.len)
    for index, header in fixture.ancestors: supplied[index] = header
    assert dispatcher.resumeAncestors(supplied, CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.None
    for index in 0..<supplied.len:
      supplied[index] = default(OwnedHeader) # Receiver-owned immutable handles outlive this independent caller backing.
    assert dispatcher.stage == CurrentDownloadLoopStage.Receiving and hashCalls() == 0
    failHash(0)
    dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, 30)
    assert dispatcher.completed and dispatcher.adoption.error == CurrentHandoffError.None
    expected = fixture.sequence.heads[2]
  dispatcher.close()
  assert not owner.preparationActive and not owner.diskPublicationActive and
      not owner.rpc.chainPaused
  assert servers.requestCount(true) == 2 and servers.requestCount(false) == 0
  equalCurrentDiskMap(owner.stateSnapshot.value, expected.stateSnapshot)
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.blockHash)
  let count = if mode == LookupCase.Expire: 2 else: 3
  assert owner.chainView.retainedCount == count
  servers.close()
  owner.close()
  if layout != 0:
    assert owner.start(options, "strict resumed guarantee ancestry restart")
    assert owner.chainView.retainedCount == count
    assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
        expected.blockHash)
    equalCurrentDiskMap(owner.stateSnapshot.value, expected.stateSnapshot)
    owner.close()

proc main() {.raises.} =
  ## Complete resumption, original deadline expiry and actual competing publication are deterministic separate owner lifetimes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentGuaranteeSequenceFixture(decodeOwnedReport(bytes, 2).value)
  for mode in [LookupCase.Resume, LookupCase.Expire, LookupCase.ChangedParent]:
    for layout in 0..2: scenario(fixture, mode, layout)
try:
  main()
except:
  quit(2) # Missing authority, repeated child requests, hash work during resume or changed durable prefixes remain failures.
echo "PVM current guarantee ancestry passed"
