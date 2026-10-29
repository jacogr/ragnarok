# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual Services native forget/restore execution refreshes complete logical request histories before host enqueue.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/current_consecutive_context
import ../../support/[current_services_disk_samples, managed_storage_samples]
import ../../../src/app/disk/worker as disk_worker
import ../../../src/storage/managed/manifest as managed_manifest
import ../../support/[current_namespace_execution_context, current_logical_history_context,
    current_logical_collection_context, current_application_context, parent_profile_context,
    parent_globals_context, supplied_logical_context, current_identity_context,
    accumulation_current_candidate_context, current_logical_proof_context]
import ../../../src/app/[services, options]
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, requests as state_requests]
import ../../../src/state/parent/[profile as parent_profile, globals as parent_globals,
    logical as parent_logical]
import ../../../src/state/current/identities as current_identities
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/admission as report_admission
import ../../../src/state/current/logical as current_logical
proc publishHistory(owner: var Services, update: PreparedCurrentChainUpdate, disk: bool) =
  ## All retained logical/current owners remain stable from enqueue through native disk Done and matching publication collection.
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  if disk:
    assert owner.diskPublicationActive and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Publishing
    owner.waitCurrentDiskDone()
    assert owner.diskPublicationActive and owner.diskPublicationPhase == DiskWorkerPhase.Done
    owner.tick(0)
    assert not owner.diskPublicationActive
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
proc scenario(fixture: NamespaceExecutionFixture, restore: bool, layout: int) {.raises.} =
  ## Seed the actual configured physical parent, collect a genuinely executed history update and qualify it while host access is open.
  var path = "pvm-current-logical-history-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  var database = "pvm-current-logical-history-state-" & $layout & "-" & $ord(restore)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString())
  var options = default(Options)
  if layout == 0:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  else: options = currentDiskOptions(path, database, layout == 2, 0)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "collected logical history")
  let before = owner.stateSnapshot.value
  let hash = fixture.seeds[1].preimages[1].hash
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(32)).value
  assert before.lookup(key).value.byteLength == 5
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let declarations = fixture.executableNamespaceServices(before)
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits).value
  let child = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var heads = @[owner.chainView.bestBlock.value]
  var policies = currentCandidateLimits()
  policies.completion.composition.validators.services = ElementLimit(
      2) # Later actual parents carry both completed service statistics.
  let update = owner.collectLogicalChild(input, child, policies)
  let identities = preserveCurrentIdentities(parent, update, currentIdentityTestLimits)
  assert identities.error == CurrentIdentityError.None
  var logical = refreshCollectedIdentities(identities.value)
  logical.checkCollectedHistory(hash, restore)
  assert sameStateSnapshot(logical.logicalProducer.currentUpdateState, update.currentUpdateState)
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  heads.add(update.currentUpdateChild)
  owner.publishHistory(update, layout != 0)
  assert sameStateSnapshot(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
  assert before.lookup(key).value.byteLength == 5 # The original configured owner remains unchanged after actual logical history adoption.
  for i in 0..<2:
    # Each next child is genuinely sealed against the actual adopted Services head; the completed logical result, not the configured startup seed, authorizes continuation.
    let next = owner.collectLogicalChild(input, currentEmptyChild(owner.chainView.bestBlock.value), policies)
    let continued = preserveCurrentIdentities(logical, next, currentIdentityTestLimits)
    assert continued.error == CurrentIdentityError.None
    logical = refreshCollectedIdentities(continued.value)
    logical.checkCollectedHistory(hash, restore)
    assert sameStateSnapshot(logical.logicalProducer.currentUpdateState, next.currentUpdateState)
    heads.add(next.currentUpdateChild)
    owner.publishHistory(next, layout != 0)
    assert sameStateSnapshot(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
    assert uint32(owner.chainView.bestBlock.value.slot) == uint32(i+3)
  assert before.lookup(key).value.byteLength == 5
  owner.close()
  if layout != 0:
    assert owner.start(options, "strict logical history restart")
    let view = owner.chainView
    assert view.retainedCount == heads.len and heads.len == 4
    assert view.finalizedBlock.error != GenesisError.None
    for index in 0..<heads.len:
      # Every confirmed logical history transition must survive strict reopen with the same complete map and exact linear history identities.
      let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      let expected = heads[index]
      equalCurrentDiskMap(actual.stateSnapshot, expected.stateSnapshot)
      assert array[32, byte](actual.blockHash) == array[32, byte](expected.blockHash)
      assert array[32, byte](actual.parentHash) == array[32, byte](expected.parentHash)
      assert actual.slot == expected.slot
    equalCurrentDiskMap(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
    assert owner.stateSnapshot.value.lookup(key).value.byteLength == (if restore: 13 else: 9)
    owner.close()
proc main() {.raises.} =
  ## Available(1) becomes Unavailable(1,2) or Reavailable(1,2,2) through real native guest hosts, never caller-authored posterior histories.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  for restore in [false, true]:
    let fixture = logicalHistoryFixture(base, restore)
    for layout in 0..2: scenario(fixture, restore, layout)
  echo "PVM current logical histories passed"
try:
  main()
except:
  quit(2) # Native request execution, exact logical provenance and host installation must all succeed.
