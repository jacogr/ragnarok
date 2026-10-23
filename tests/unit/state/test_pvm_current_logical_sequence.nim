# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Repeated real Services children continue complete logical provenance after a guest overwrites an existing service99 storage identity.
import std/[assertions, envvars, syncio]
import std/posix/posix
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
proc overwriteCode(): seq[byte] =
  ## Actual write host targets the existing raw key5 of funded service99; the original present-empty value grows without creating a namespace identity.
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, 3),
      @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[5'u8, 17, 18, 19]): result.add(octet)
proc scenario(fixture: NamespaceExecutionFixture, layout: int) {.raises.} =
  ## Each matching native collection precedes logical continuation; each explicit adoption precedes signing/preparing the following child.
  var path = "pvm-current-logical-sequence-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  var database = "pvm-current-logical-sequence-state-" & $layout
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString()) # Only this invocation's exact physical namespace is removed after joined close.
  var options = default(Options)
  if layout == 0:
    assert parseOptions(@["server", "--with-state", "--chain", path], options)
  else:
    options = currentDiskOptions(path, database, layout == 2, 0)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "current logical sequence")
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
    assert owner.preparationAvailable and owner.stateProofAvailable
  assert original.lookup(key).value.bytes.len == 0 # Original physical aliases remain immutable across every real adoption.
  assert first.logicalProducer.currentUpdateState.lookup(key).value.bytes == @[17'u8, 18, 19]
  if layout != 0:
    owner.close()
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
  for layout in 0..2: scenario(fixture, layout)
  echo "PVM current logical sequence passed"
try:
  main()
except:
  quit(2) # A namespace, provenance, execution or later installation failure cannot count as successful continuation.
