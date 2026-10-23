# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repeated real Services children continue complete logical provenance after a guest overwrites an existing service99 storage identity.
import std/[assertions, envvars, syncio, strutils, base64]
import std/posix/posix
import ../../support/rpc_socket
import ../../support/[current_namespace_execution_context, current_application_context,
    current_logical_collection_context, current_consecutive_context,
    accumulation_current_candidate_context, parent_profile_context, parent_globals_context,
    supplied_logical_context, current_identity_context, current_logical_proof_context,
    pvm_accumulation_program, current_services_disk_samples, managed_storage_samples, current_namespace_refresh_context]
import ../../../src/app/[services, options, current_block_input, current_handoff, disk_worker]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, block_codec, report_owned, state_layout, state_accounts, state_service_values]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_identities,
    current_logical, accumulation_current_update, store, block_admission, report_admission, supplied_services]
import ../../../src/storage/managed_manifest
import ../../../src/rpc/server
proc overwriteCode(): seq[byte] =
  ## Actual write host targets the existing raw key5 of funded service99; the original present-empty value grows without creating a namespace identity.
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, 3),
      @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[5'u8, 17, 18, 19]): result.add(octet)
proc scenario(fixture: NamespaceExecutionFixture, layout: int, joinAfterDone,
    network: bool) {.raises.} =
  ## Each matching native collection precedes logical continuation; each explicit adoption precedes signing/preparing the following child.
  var path = "pvm-current-logical-sequence-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  var database = "pvm-current-logical-sequence-state-" & $layout
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString()) # Only this invocation's exact physical namespace is removed after joined close.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd) # Only this invocation's actual loopback reservation selects the listener.
  var options = default(Options)
  if layout == 0:
    var args = @["server", "--with-state", "--chain", path]
    if network:
      args.add("--with-rpc")
      args.add("--rpc-port")
      args.add($port) # Append individual explicit arguments supported by the pinned compiler.
    assert parseOptions(args, options)
  else:
    options = currentDiskOptions(path, database, layout == 2, port)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "current logical sequence")
  var peer = -1.cint
  var pending = ""
  defer:
    if peer >= 0: discard posix.close(peer) # Client retirement precedes the outer Services joined close on every raised path.
  if network:
    peer = client(port)
    upgrade(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":1}""")
    assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
    assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let original = owner.stateSnapshot.value
  let declarations = fixture.executableNamespaceServices(original)
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits).value
  let key = serviceStorageKey(ServiceIndex(99), @[5'u8], ByteLimit(1)).value
  assert original.lookup(key).value.bytes.len == 0
  var heads = @[owner.chainView.bestBlock.value]
  var logical = default(CurrentLogicalState)
  var first = default(CurrentLogicalState)
  var policies = currentCandidateLimits()
  policies.completion.composition.validators.services = ElementLimit(2)
  for index in 0..<3:
    # The first child is the genuinely admitted namespace guest; later children are sealed against the actual adopted posterior, with no replayed report.
    let before = owner.stateSnapshot.value
    let child = if index == 0:
        fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
      else: currentEmptyChild(owner.chainView.bestBlock.value)
    if index == 1:
      # Retain the fully qualified prior logical owner across both real cancellation lifetimes, then prepare the same signed child successfully.
      for afterDone in [false, true]:
        owner.cancelLogicalChild(input, child, policies, afterDone)
        assert sameStateSnapshot(before, owner.stateSnapshot.value)
        assert sameStateSnapshot(before, logical.logicalProducer.currentUpdateState)
        assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    let update = owner.collectLogicalChild(input, child, policies)
    let identities = if index == 0:
        preserveCurrentIdentities(parent, update, currentIdentityTestLimits)
      else: preserveCurrentIdentities(logical, update, currentIdentityTestLimits)
    assert identities.error == CurrentIdentityError.None
    if index == 2:
      assert preserveCurrentIdentities(first, update, currentIdentityTestLimits).error ==
          CurrentIdentityError.ParentMismatch
    logical = refreshCollectedIdentities(identities.value)
    if index == 0: first = logical
    assert sameStateSnapshot(logical.logicalProducer.currentUpdateState, update.currentUpdateState)
    assert update.currentUpdateState.lookup(key).value.bytes == @[17'u8, 18, 19]
    assert uint32(update.currentUpdateChildContext.slot) == uint32(index+2)
    assert sameStateSnapshot(before, owner.stateSnapshot.value)
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    heads.add(update.currentUpdateChild) # Every retained alias is constructed before the native disk lease begins.
    assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
    owner.tick(0)
    if layout != 0:
      assert owner.diskPublicationActive and owner.currentAccumulationPhase ==
          CurrentHandoffPhase.Publishing
      owner.waitCurrentDiskDone()
      assert owner.diskPublicationActive and owner.diskPublicationPhase == DiskWorkerPhase.Done
      assert not owner.preparationAvailable and not owner.stateProofAvailable
      owner.tick(0) # Matching native collection reopens graph access before logical/head/update owners are inspected again.
      assert not owner.diskPublicationActive
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
    assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
    assert sameStateSnapshot(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
    assert owner.chainView.retainedCount == index+2
    assert owner.chainView.finalizedBlock.error != GenesisError.None
    if network:
      # Only the reopened host gate can serve current subscriber/query observations, and all three surfaces must identify the qualified posterior.
      let hash = base64.encode(array[32, byte](update.currentUpdateChildContext.hash))
      assert hash in readPacket(owner.rpc, peer, pending)
      sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":2}""")
      assert hash in readPacket(owner.rpc, peer, pending)
      sendText(peer, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" & hash & "\"],\"id\":3}")
      let root = base64.encode(array[32, byte](logical.logicalProducer.currentUpdateState.commitment.root))
      assert root in readPacket(owner.rpc, peer, pending)
    assert owner.preparationAvailable and owner.stateProofAvailable
    owner.proveLogicalCurrent(logical) # Installed current provenance survives a real canonical proof lease before the next preparation.
    if index == 1:
      for joined in [false, true]:
        for afterDone in [false, true]: owner.retireLogicalProof(logical, afterDone, joined)
      owner.proveLogicalCurrent(logical) # Capacity is truly reusable after both cancellations, with the same original logical owner/root.
  assert original.lookup(key).value.bytes.len == 0 # Original physical aliases remain immutable across every real adoption.
  assert first.logicalProducer.currentUpdateState.lookup(key).value.bytes == @[17'u8, 18, 19]
  if peer >= 0:
    discard posix.close(peer)
    peer = -1 # No stale client or pending response can cross the later Services close/restart lifetime.
  let uncollected = currentEmptyChild(owner.chainView.bestBlock.value)
  owner.joinLogicalChild(input, uncollected, policies, joinAfterDone)
  assert logical.logicalProducer.currentUpdateState.lookup(key).value.bytes == @[17'u8, 18, 19]
  assert logical.logicalProducer.currentUpdateView.retainedCount == 4
  if layout != 0:
    assert owner.start(options, "strict logical sequence restart")
    let view = owner.chainView
    assert view.retainedCount == heads.len
    for index in 0..<heads.len:
      # Strict disk startup must recover every actual retained map/header/parent/slot, not merely the best root or expected entry count.
      let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      let expected = heads[index]
      assert array[32, byte](actual.blockHash) == array[32, byte](expected.blockHash)
      assert actual.slot == expected.slot
      assert array[32, byte](actual.parentHash) == array[32, byte](expected.parentHash)
      equalCurrentDiskMap(actual.stateSnapshot, expected.stateSnapshot)
    assert view.finalizedBlock.error != GenesisError.None
    equalCurrentDiskMap(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
    # Reopening creates new physical graph owners, so copy declarations on the open host gate and match them to the actual recovered full view before another native job.
    let copied = copySuppliedServices(logical.currentLogicalInventory.value,
        namespaceRefreshLimits.projection)
    assert copied.error == SuppliedServicesError.None
    let resumedProfile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
    let resumedGlobals = qualifyParentGlobals(resumedProfile, parentGlobalsTestLimits).value
    let resumedParent = captureLogicalParent(resumedGlobals, copied.value, suppliedLogicalTestLimits)
    assert resumedParent.error == ParentLogicalError.None
    let resumed = owner.collectLogicalChild(input, currentEmptyChild(
        owner.chainView.bestBlock.value), policies)
    assert preserveCurrentIdentities(logical, resumed, currentIdentityTestLimits).error ==
        CurrentIdentityError.ParentMismatch
    let resumedIdentities = preserveCurrentIdentities(resumedParent.value, resumed, currentIdentityTestLimits)
    assert resumedIdentities.error == CurrentIdentityError.None
    logical = refreshCollectedIdentities(resumedIdentities.value)
    assert logical.logicalProducer.currentUpdateState.lookup(key).value.bytes == @[17'u8, 18, 19]
    heads.add(resumed.currentUpdateChild)
    assert owner.enqueueCurrentAccumulation(resumed) == CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.diskPublicationActive
    owner.waitCurrentDiskDone()
    assert owner.diskPublicationActive
    owner.tick(0)
    assert not owner.diskPublicationActive and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Finished
    assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
    assert sameStateSnapshot(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
    owner.proveLogicalCurrent(logical)
    owner.close()
    assert owner.start(options, "strict resumed logical restart")
    assert owner.chainView.retainedCount == heads.len and heads.len == 5
    for index in 0..<heads.len:
      # Confirm the newly continued child and every earlier durable state after a second independent open.
      let actual = owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      assert array[32, byte](actual.blockHash) == array[32, byte](heads[index].blockHash)
      assert array[32, byte](actual.parentHash) == array[32, byte](heads[index].parentHash)
      assert actual.slot == heads[index].slot
      equalCurrentDiskMap(actual.stateSnapshot, heads[index].stateSnapshot)
    assert owner.chainView.finalizedBlock.error != GenesisError.None
    owner.close()
proc main() {.raises.} =
  ## Complete original code namespaces and actual funded overwrite feed three independent native preparation/adoption lifetimes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, namespaceHaltCode(),
      overwriteCode())
  for layout in 0..2:
    for joinAfterDone in [false, true]:
      for network in [false, true]: scenario(fixture, layout, joinAfterDone, network)
  echo "PVM current logical sequence passed"
try:
  main()
except:
  quit(2) # A namespace, provenance, execution or later installation failure cannot count as successful continuation.
