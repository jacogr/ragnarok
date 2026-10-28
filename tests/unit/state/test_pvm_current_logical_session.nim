# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated logical sessions retain explicit sources through retries and advance only after real consumed adoption across all storage layouts.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_application_context
import ../../support/state_current_consecutive_context
import ../../support/state_current_consecutive_download_context
import ../../support/state_current_download_command_context
import ../../support/state_current_services_disk_samples
import ../../support/app_managed_storage_samples
import ../../support/app_block_download_transport
import ../../support/state_parent_profile_context
import ../../support/state_parent_globals_context
import ../../support/codec_supplied_logical_context
import ../../support/state_current_identity_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_logical_proof_context
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/chain as app_chain
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/current_block_download as app_current_block_download
import ../../../src/app/current_logical_download as app_current_logical_download
import ../../../src/app/download_schedule as app_download_schedule
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../../src/quic/current_block_download_session as quic_current_block_download_session
import ../../../src/quic/current_block_download_peers as quic_current_block_download_peers
import ../../../src/quic/current_block_download_stream as quic_current_block_download_stream
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/state/store as state_store
import ../../../src/state/parent_profile as state_parent_profile
import ../../../src/state/parent_globals as state_parent_globals
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/report_admission as state_report_admission
import ../../../src/storage/managed_manifest as storage_managed_manifest

type Mode {.pure.} = enum ## Success includes a real empty-response retry; refusals and joined closes publish no logical prefix.
  Consecutive, BudgetRefusal, IdentityRefusal, JoinDone, CancelQueued
proc logicalLimits(): CurrentLogicalDownloadLimits =
  ## Original caller budgets are frozen once; subsequent children must not infer larger limits from actual successor sizes.
  CurrentLogicalDownloadLimits(identities: currentIdentityTestLimits,
      requests: namespaceRequestLimits,

reconstruction: namespaceRefreshLimits, logical: namespaceLogicalLimits())
proc key(): CurrentDownloadPeerKey {.raises.} =
  ## Pin the responder's independently generated fixture identity before opening any endpoint.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for i in 0..<32: bytes[i] = byte(raw[i])
  CurrentDownloadPeerKey(bytes)
proc parent(owner: Services, fixture: NamespaceExecutionFixture): SelectedLogicalParent =
  ## Supplied complete declarations are matched against the actual configured Services owner, never the fixture's equal-root owner.
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  captureLogicalParent(globals, fixture.executableNamespaceServices(owner.stateSnapshot.value),
      suppliedLogicalTestLimits).value
proc probeSession(owner: Services, policy: CurrentLogicalDownloadPolicy,
    limits: CurrentDownloadLoopLimits) =
  ## Exact token and queued/native-close gates protect logical queries before any worker or native stream exists.
  var session = default(CurrentDownloadSession)
  assert session.configure([DownloadPeerId(2)], limits.schedule, DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let admitted = session.begin(owner, [], limits.input, limits.candidate, DownloadScheduleTick(0), policy)
  assert admitted.error == CurrentDownloadSessionError.None
  assert session.logicalCompletion(admitted.value).error == CurrentDownloadSessionError.NotReady
  let foreign = CurrentDownloadSessionAttempt()
  assert session.logicalCompletion(foreign).error == CurrentDownloadSessionError.StaleAttempt
  assert session.discardInput(admitted.value).error == CurrentDownloadSessionError.None
  assert session.finish(admitted.value, DownloadAttemptOutcome.Retry, DownloadScheduleTick(
      0)).error == CurrentDownloadSessionError.None
  assert session.logicalCompletion(admitted.value).error ==
      CurrentDownloadSessionError.StaleAttempt
proc advance(dispatcher: var CurrentDownloadLoop, servers: var DownloadResponders,
    target: CurrentDownloadLoopStage, now: var uint64) =
  ## Monotonic local ticks let real retry cooldowns expire without resetting any whole-attempt deadline.
  let started = getMonoTime()
  while dispatcher.stage != target:
    assert (getMonoTime()-started).inSeconds < 20, "logical dispatcher stage " & $target
    assert servers.poll()
    inc now
    assert dispatcher.tick(CurrentDownloadLoopTick(now)) == CurrentDownloadLoopError.None
    yieldCurrentDiskThread() # Only scalar stages and endpoint polling occur throughout preparation/publication leases.
proc scenario(fixture: NamespaceExecutionFixture, layout: int, mode: Mode) {.raises.} =
  ## Persistent authenticated endpoints deliver exact authored requests; strict reopens retain only actual successful adoption.
  var path = "pvm-logical-session-chain"
  var database = "pvm-logical-session-state-" & $layout
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString()) # Join every native borrower before removing the explicit test namespace.
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # The dispatcher ends all graph/callback borrows before canonical ownership retires.
  var options = default(Options)
  if layout == 0:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  else: options = currentDiskOptions(path, database, layout == 2, 0)
  assert owner.start(options, "logical authenticated session")
  let original = owner.stateSnapshot.value
  let source = owner.parent(fixture)
  var budgets = logicalLimits()
  if mode == Mode.BudgetRefusal: budgets.identities.keys = ElementLimit(0)
  let logical = initCurrentLogicalDownloadPolicy(source, budgets)
  var policy = currentConsecutivePolicy()
  policy.schedule.attempts = if mode == Mode.Consecutive: 2 else: 1
  policy.input.ancestorBytes = ByteLimit(1) # Empty ancestor context is valid; any replacement header must still pass the independent byte ceiling.
  probeSession(owner, logical, policy)
  var expected = @[fixture.parent.bestBlock.value]
  let first = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var children = @[first]
  var model = initApplicationChain(fixture.parent).value
  assert model.canInstallPrepared(fixture.update), "namespace fixture update must bind the model parent exactly"
  model.installPrepared(fixture.update)
  expected.add(model.chainView.bestBlock.value)
  if mode == Mode.Consecutive:
    for index in 0..<2:
      let child = currentEmptyChild(model.chainView.bestBlock.value)
      let update = phaseCurrentUpdate(model, child, [], currentConsecutiveLimits())
      model.installPrepared(update)
      children.add(child)
      expected.add(model.chainView.bestBlock.value) # Authored expected maps do not grant canonical or independent full-STF authority.
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  if mode == Mode.Consecutive:
    requests.add(currentExpectedRequest(array[32, byte](expected[0].blockHash)))
    responses.add(@[0'u8, 0, 0, 0]) # Explicit E4 zero-length bytes, independent of the responder's fragmentation mode.
    modes.add(EmptyReply) # A real first response is empty; retry must retain the original complete logical source and frozen policies.
  for index, child in children:
    requests.add(currentExpectedRequest(array[32, byte](expected[index].blockHash)))
    responses.add(currentConsecutiveResponse(child))
    modes.add(Healthy)
  assert servers.openSequenceResponders(requests, responses, modes)
  assert dispatcher.configure(owner, [DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(0),
      logical) == CurrentDownloadLoopError.None
  budgets.identities.keys = ElementLimit(0) # A detached caller edit cannot change initial admission or the later continued policy.
  assert dispatcher.openPeer(DownloadPeerId(2), key(), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
          CurrentDownloadPeerError.None
  var now = 0'u64
  if mode in [Mode.BudgetRefusal, Mode.IdentityRefusal]:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Exhausted, now)
    assert not dispatcher.completed
    let reason = dispatcher.sessionFailure
    assert reason.error == CurrentDownloadSessionError.DownloadFailure
    assert reason.downloadFailure.error == CurrentBlockDownloadError.LogicalFailure
    let actual = reason.downloadFailure.logicalFailure
    assert actual.error == CurrentLogicalDownloadError.IdentityFailure
    assert actual.identityFailure.error == (if mode == Mode.BudgetRefusal:
      CurrentIdentityError.LimitExceeded else: CurrentIdentityError.NewIdentity)
    assert servers.requestCount(true) == 1
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    assert sameStateSnapshot(original, owner.stateSnapshot.value)
    assert dispatcher.nextChild([], CurrentDownloadLoopTick(now)) == CurrentDownloadLoopError.Busy
  elif mode in [Mode.JoinDone, Mode.CancelQueued]:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Preparing, now)
    let started = getMonoTime()
    while owner.preparationPhase != PreparationPhase.Done:
      assert (getMonoTime()-started).inSeconds < 20
      yieldCurrentDiskThread() # No dispatcher tick may collect or touch the graph before the joined-close control.
    if mode == Mode.CancelQueued:
      dispatcher.advance(servers, CurrentDownloadLoopStage.Queued, now)
      assert not dispatcher.completed
      assert dispatcher.nextChild([], CurrentDownloadLoopTick(now)) ==
          CurrentDownloadLoopError.Busy
    dispatcher.close()
    assert sameStateSnapshot(original, owner.stateSnapshot.value)
    assert owner.preparationAvailable and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Idle
  else:
    for index in 0..<3:
      if index == 0:
        dispatcher.advance(servers, CurrentDownloadLoopStage.Queued, now)
        assert not dispatcher.completed
        assert dispatcher.nextChild([], CurrentDownloadLoopTick(now)) ==
            CurrentDownloadLoopError.Busy
        assert sameStateSnapshot(original, owner.stateSnapshot.value)
      dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, now)
      let receipt = dispatcher.logicalAdoption
      assert receipt.error == CurrentDownloadSessionError.None
      let update = receipt.value.logicalProducer
      assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
      equalCurrentDiskMap(owner.stateSnapshot.value, expected[index+1].stateSnapshot)
      assert dispatcher.adoption.error == CurrentHandoffError.None
      assert servers.requestCount(true) == index+2 and servers.requestCount(false) == 0
      if index < 2:
        assert dispatcher.nextChild([], CurrentDownloadLoopTick(now-1)) ==
            CurrentDownloadLoopError.ClockRegression
        assert dispatcher.nextChild([default(OwnedHeader)], CurrentDownloadLoopTick(now)) ==
            CurrentDownloadLoopError.InvalidPolicy
        assert dispatcher.nextChild([expected[0].header], CurrentDownloadLoopTick(now)) ==
            CurrentDownloadLoopError.InvalidPolicy
        assert dispatcher.completed and dispatcher.logicalAdoption.error ==
            CurrentDownloadSessionError.None
        assert sameStateSnapshot(dispatcher.logicalAdoption.value.logicalProducer.currentUpdateState,
            owner.stateSnapshot.value)
        assert dispatcher.nextChild([], CurrentDownloadLoopTick(now)) ==
            CurrentDownloadLoopError.None
        assert not dispatcher.completed and dispatcher.stage == CurrentDownloadLoopStage.Waiting
        assert dispatcher.nextChild([], CurrentDownloadLoopTick(now)) ==
            CurrentDownloadLoopError.Busy
        assert servers.requestCount(true) == index+2,
            "logical session check: servers.requestCount(true) == index+2 " # Rearming performs no extra network request, guest work or adoption.
  let finalState = owner.stateSnapshot.value
  let count = owner.chainView.retainedCount
  assert count == (if mode == Mode.Consecutive: 4 else: 1)
  dispatcher.close()
  servers.close()
  owner.close()
  if layout != 0:
    assert owner.start(options, "strict logical session reopen")
    assert owner.chainView.retainedCount == count
    equalCurrentDiskMap(owner.stateSnapshot.value, finalState)
    for index in 0..<count:
      let actual = owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      equalCurrentDiskMap(actual.stateSnapshot, expected[index].stateSnapshot)
    owner.close()
proc main() {.raises.} =
  ## Real complete code/request/storage namespaces feed successful and unsupported-identity authenticated transfers.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let fixture = namespaceExecutionFixture(base, namespaceHaltCode(), namespaceHaltCode())
  let mutation = namespaceExecutionFixture(base, namespaceHaltCode(), namespaceStorageCode(@[21'u8, 22]))
  for layout in 0..2:
    for mode in Mode.Consecutive..Mode.CancelQueued:
      scenario(if mode == Mode.IdentityRefusal: mutation else: fixture, layout, mode)
  echo "PVM current logical session passed"
try:
  main()
except:
  quit(2) # Any native, provenance, publication, rearm or strict-reopen failure is a hard failure.
