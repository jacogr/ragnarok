# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact joined shutdown receipts distinguish uncollected durable completion from pending cancellation, raw success and refused qualification using actual TLS/native workers.
import std/[assertions, syncio, envvars, cmdline, monotimes, times, strutils]
import std/posix/posix
import ../support/[current_namespace_execution_context, current_namespace_transition_context,
  current_logical_cli_context, current_namespace_policy_context, current_application_context,
  current_consecutive_download_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport, current_download_command_context]
import ../../src/app/[services, options, current_handoff, current_download_policy,
  current_logical_startup, current_logical_download, logical_source_export, candidate, disk_worker, download_schedule]
import ../../src/quic/[current_block_download_loop, current_block_download_session,
  current_block_download_peers, current_block_download_stream]
import ../../src/state/[store, current_logical, accumulation_current_update, accumulation_round,
  accumulation_queue,
  report_admission, block_transition, block_admission]
import ../../src/codec/[bounded, report_owned, state_service_values, state_accounts]
import ../../src/chain/[provider, genesis]
import ../../src/storage/managed_manifest
type Witness {.pure.} = enum ## Independently selected legal ownership boundaries require no probabilistic sleep or guessed worker timing.
  Pending, NativeDone, Finished, Observed, Raw, Refused
proc peerKey(): CurrentDownloadPeerKey {.raises.} =
  ## The real independent peer certificate supplies only its explicitly retained 32-byte public identity.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert raw.len == 32
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = byte(raw[i])
  CurrentDownloadPeerKey(key)
proc advance(dispatcher: var CurrentDownloadLoop, servers: var DownloadResponders,
    target: CurrentDownloadLoopStage) =
  ## Scalar stages and native polling alone select exact execution/adoption boundaries while graph leases remain untouched.
  let started = getMonoTime()
  while dispatcher.stage != target:
    assert (getMonoTime()-started).inSeconds < 20
    assert servers.poll()
    assert dispatcher.tick(CurrentDownloadLoopTick(0)) == CurrentDownloadLoopError.None
    yieldCurrentDiskThread()
proc scenario(fixture: NamespaceExecutionFixture, layout: int, witness: Witness) {.raises.} =
  ## Real original qualification and signed TLS reception precede every controlled native completion/close alternative.
  var path = "current-logical-shutdown-chain"
  var database = "current-logical-shutdown-state-" & $getMonoTime().ticks
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString()) # Retire only this scenario's joined test-owned storage.
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # Every callback and native worker retires before canonical or retained result aliases.
  var options = default(Options)
  if layout == 0: assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  else: options = currentDiskOptions(path, database, layout == 2, 0)
  assert owner.start(options, "joined logical receipt")
  let parent = owner.stateSnapshot.value
  let startup = logicalStartupTestLimits()
  let declarations = decodeCurrentLogicalDeclarations(logicalDeclarationText(
      fixture.executableNamespaceServices(parent)), startup.projection).value
  let original = captureCurrentLogicalStartup(owner.chainView, declarations, startup).value
  var namespacePolicy = namespacePolicyTestLimits()
  if witness == Witness.Refused: namespacePolicy.continuation.scratchBytes = ByteLimit(
      0) # Real execution succeeds but no complete logical prefix can be enqueued.
  let logical = initCurrentLogicalDownloadPolicy(original, namespacePolicy.continuation)
  let candidate = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let response = currentConsecutiveResponse(candidate)
  let request = currentExpectedRequest(array[32, byte](owner.chainView.bestBlock.value.blockHash))
  assert servers.openResponders(request, response, Healthy)
  var limits = currentConsecutivePolicy()
  configureCurrentNamespaces(limits.candidate, namespacePolicy)
  let configured = if witness == Witness.Raw:
      dispatcher.configure(owner, [DownloadPeerId(2)], [], limits, CurrentDownloadLoopTick(0))
    else: dispatcher.configure(owner, [DownloadPeerId(2)], [], limits, CurrentDownloadLoopTick(0), logical)
  assert configured == CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), peerKey(), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
      CurrentDownloadPeerError.None
  if witness == Witness.Refused:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Exhausted) # Logical refusal consumes the one actual attempt, without granting handoff authority.
  else:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Queued)
    if witness in [Witness.NativeDone, Witness.Finished, Witness.Raw]:
      owner.tick(0) # Start only this already queued publication; the dispatcher does not get a subsequent adoption tick.
      if layout != 0:
        owner.waitCurrentDiskDone() # Done deliberately retains the exclusive native lease until joined close.
        assert owner.diskPublicationActive
      if witness == Witness.Finished:
        owner.tick(0) # Collect/install under the normal Services gate, while leaving the receipt unconsumed by the dispatcher.
        assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
    elif witness == Witness.Observed:
      dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted) # The compatibility path already consumed its actual canonical receipt.
  let settled = dispatcher.closeAndCaptureLogical()
  assert dispatcher.stage == CurrentDownloadLoopStage.Closed
  assert not owner.preparationActive and not owner.diskPublicationActive
  if layout != 0 and witness in [Witness.NativeDone, Witness.Raw]:
    assert not owner.preparationAvailable and not owner.stateProofAvailable # Explicit native IO shutdown preserves the existing fresh-start requirement, even after a durable receipt.
  else:
    assert owner.preparationAvailable and owner.stateProofAvailable # Ordinary collection and unattempted cancellation retire leases without faulting the backend.
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  if witness in [Witness.Pending, Witness.Refused]:
    assert settled.error != CurrentDownloadSessionError.None
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  else:
    assert owner.chainView.retainedCount == 2
    if witness == Witness.Raw:
      assert settled.error != CurrentDownloadSessionError.None # A genuine raw canonical adoption never masquerades as qualified logical state.
    else:
      assert settled.error == CurrentDownloadSessionError.None
      let update = settled.value.currentLogicalUpdate.value
      assert sameStateSnapshot(update.currentUpdateState, owner.stateSnapshot.value)
      assert sameChainView(update.currentUpdateView, owner.chainView)
      assert array[32, byte](dispatcher.adoption.value.blockHash) == array[32, byte](
          update.currentUpdateChild.blockHash)
      let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
      assert update.currentUpdateState.lookup(key).value.bytes == @[9'u8, 8]
      owner.close() # The detached exact logical receipt must remain usable after every Services/native owner has joined and retired.
      let plan = planLogicalSourceExport(settled.value, LogicalSourceExportLimits(
          services: ElementLimit(2), facts: ElementLimit(64), perKey: ByteLimit(8),
          bytes: ByteLimit(65536))).value
      assert "k=07\n" in executeLogicalSourceExport(plan).value
      if layout != 0:
        assert owner.start(options, "strict joined logical reopen")
        assert owner.chainView.retainedCount == 2
        equalCurrentDiskMap(owner.stateSnapshot.value, update.currentUpdateState)
        owner.close()
  assert dispatcher.closeAndCaptureLogical().error !=
      CurrentDownloadSessionError.None # A closed dispatcher grants no second logical receipt or stale prefix.
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "main"
  if mode in ["value", "control"]:
    var dispatcher = default(CurrentDownloadLoop)
    let absent = dispatcher.closeAndCaptureLogical()
    if mode == "value": discard absent.value # A default/closed aggregate has no adopted logical payload.
    else: assert absent.error != CurrentDownloadSessionError.None # Healthy default close is the independent runtime control.
    return
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, namespaceHaltCode(),
      namespaceStorageCode(@[9'u8, 8]))
  for layout in 0..2:
    for witness in Witness.Pending..Witness.Refused:
      scenario(fixture, layout, witness) # Every selected boundary uses fresh actual TLS endpoints, native owners and its own exact storage namespace.
  echo "current-logical-shutdown: ok"
try: main()
except: quit(2) # Native source/lifetime/refusal mismatch cannot satisfy a result guard or successful close contract.
