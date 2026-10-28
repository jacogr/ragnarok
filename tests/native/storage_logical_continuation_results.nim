# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real native growth, deletion and rollback continue from original raw identities without supplied successor declarations; all-stage refusal exposes no prefix.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/app_collected_native_context
import ../support/app_collected_logical_context
import ../support/app_collected_mutation_context
import ../support/state_current_namespace_transition_context
import ../support/state_current_namespace_execution_context
import ../support/state_current_namespace_context
import ../support/state_current_namespace_refresh_context
import ../support/state_accumulation_execution_context
import ../support/state_accumulation_current_candidate_context
import ../support/state_current_identity_context
import ../support/state_current_repeated_logical_context
import ../support/app_download_chain
import ../support/testing_arc_evidence
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/state/storage_logical_continuation as state_storage_logical_continuation
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_storage_history as state_accumulation_storage_history
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_identities as state_current_identities
import ../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../src/state/supplied_services as state_supplied_services
import ../../src/state/inventory as state_inventory
import ../../src/state/manifest as state_manifest
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Bound refusal and genuine mandatory request-key hashing remain distinct.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Source/resource admission must precede namespace hashing on these selected early failures.
type Fixture = object ## Actual original namespaces and native producer update are the only test-owned source descriptors.
  origin: CurrentNamespaceTransition
  update: PreparedCurrentChainUpdate
proc candidatePolicy(): CurrentCandidateLimits =
  ## Both initial and later real cohorts capture bounded raw storage identities before whole-source history retention.
  result = currentCandidateLimits()
  result.completion.composition.validators.services = ElementLimit(2)
  result.storage = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
      facts: ElementLimit(16), bytes: ByteLimit(65536))
  result.completion.execution.initial.guests.storageFacts = AccumulationStorageFactLimits(
      items: ElementLimit(2), perKey: ByteLimit(2), totalKeyBytes: ByteLimit(2))
  result.completion.execution.execution.round.guests.storageFacts = result.completion.execution.initial.guests.storageFacts
proc policy(): StorageContinuationLimits =
  ## Independent real-map reconstruction and current logical retention budgets stay explicit.
  let logical = namespaceLogicalLimits()
  StorageContinuationLimits(identity: currentIdentityTestLimits, checks: ElementLimit(4096),
      scratchBytes: ByteLimit(262144), projection: namespaceRefreshLimits.projection,
      profile: logical.profile, globals: logical.globals, logical: logical.logical)
proc fixture(kind: int): Fixture {.raises.} =
  ## Every key and guest enters the parent commitment/signatures; no completed private map or result is repaired.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(@[9'u8])
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  if kind == 1:
    options.secondProgram = namespaceStorageCode(@[])
    options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8])
  elif kind == 2:
    options.secondProgram = writeMutationCode(@[9'u8], [@[
        0'u8]]) # Uncheckpointed panic removes both the new value and selected identity.
  elif kind == 3:
    options.secondProgram = writeMutationCode(@[9'u8], [@[10'u8, 19], @[
        0'u8]]) # A real checkpoint retains the write on panic.
  elif kind == 4:
    options.secondProgram = requestMutationCode(default(ServicePreimageHash), RequestLength(17), [
        25'u8]) # Unhandled request identity creation must remain refused.
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var owner = initApplicationChain(origin.update.currentUpdatePriorView).value
  let admitted = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(owner, currentWire(admitted), origin.source.older, candidatePolicy())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  Fixture(origin: origin, update: receipt.currentValue.value)
proc check(fixture: Fixture, expected: bool): CurrentLogicalState =
  ## The new consumer discovers raw key7 only from genuine producer evidence, then matches every actual serialized entry.
  let done = continueCurrentStorage(fixture.origin.parent, fixture.update, policy())
  assert done.error == StorageContinuationError.None, $done.error
  let logical = done.value
  let observed = logical.currentLogicalInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value
  assert sameStateSnapshot(observed, fixture.update.currentUpdateState)
  let copied = copySuppliedServices(logical.currentLogicalInventory.value,
      namespaceRefreshLimits.projection).value
  var found = false
  for service in copied:
    for item in service.storage:
      if uint32(service.service) == 99 and item.key == @[
          7'u8]: found = true # Compare explicit retained raw identities, never a physical hash inversion.
  assert found == expected
  logical
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(StorageContinuationResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.identityFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "metadata": discard empty.metadataError; return
  if mode == "request": discard empty.requestError; return
  if mode == "profile": discard empty.profileFailure; return
  if mode == "globals": discard empty.globalsFailure; return
  if mode == "state": discard empty.stateFailure; return
  if mode == "logical": discard empty.logicalFailure; return
  let grown = fixture(0)
  assert preserveCurrentIdentities(grown.origin.parent, grown.update,
      currentIdentityTestLimits).error == CurrentIdentityError.NewIdentity
  let continued = check(grown, true)
  let removed = fixture(1)
  assert preserveCurrentIdentities(removed.origin.parent, removed.update,
      currentIdentityTestLimits).error == CurrentIdentityError.MissingIdentity
  discard check(removed, false)
  discard check(fixture(2), false)
  discard check(fixture(3), true)
  let unhandled = fixture(4)
  assert continueCurrentStorage(unhandled.origin.parent, unhandled.update, policy()).error ==
      StorageContinuationError.StateFailure
  assert continueCurrentStorage(grown.origin.parent, grown.origin.update, policy()).error ==
      StorageContinuationError.MissingStorageEvidence
  let crossed = continueCurrentStorage(removed.origin.parent, grown.update, policy())
  assert crossed.identityFailure.error == CurrentIdentityError.ParentMismatch
  fail(1)
  var short = policy()
  short.scratchBytes = ByteLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.LimitExceeded and calls() == 0
  short = policy()
  short.checks = ElementLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.LimitExceeded and calls() == 0
  short = policy()
  short.projection.bytes = ByteLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.LimitExceeded and calls() == 0
  assert continueCurrentStorage(grown.origin.parent, grown.update, policy()).requestError ==
      RequestError.BackendFailure
  fail(0)
  short = policy()
  short.profile.validators = ElementLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.ProfileFailure
  short = policy()
  short.globals.totalBytes = ByteLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.GlobalsFailure
  short = policy()
  short.logical.rawKeyBytes = ByteLimit(0)
  assert continueCurrentStorage(grown.origin.parent, grown.update, short).error ==
      StorageContinuationError.LogicalFailure
  assert continueCurrentStorage(default(CurrentLogicalState), grown.update, policy()).error ==
      StorageContinuationError.InvalidParent
  var nextOwner = initApplicationChain(grown.update.currentUpdateView).value
  let child = signedChild(grown.update.currentUpdateChild)
  let nextReceipt = collectNative(nextOwner, currentWire(child), [], candidatePolicy())
  assert nextReceipt.kind == PreparationCompletionKind.CurrentCompleted and
      nextReceipt.currentValue.error == CurrentBlockInputError.None
  let repeated = continueCurrentStorage(continued, nextReceipt.currentValue.value, policy())
  assert repeated.error == StorageContinuationError.None, $repeated.error
  assert sameStateSnapshot(repeated.value.currentLogicalUpdate.value.currentUpdatePriorState,
      grown.update.currentUpdateState)
  for i in 0..<25: discard continueCurrentStorage(grown.origin.parent, grown.update, policy()).value # Warm the entire admitted reconstruction and current qualification path.
  let before = getOccupiedMem()
  for i in 0..<1000: discard continueCurrentStorage(grown.origin.parent, grown.update, policy()).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_logical_continuation", 1000, before, after)
  echo "storage-logical-continuation: ok"
try:
  main()
except:
  quit(2) # No unexpected fixture/execution failure may masquerade as a guarded result rejection.
