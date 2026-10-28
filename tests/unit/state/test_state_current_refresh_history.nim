# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual current forget/restore guests refresh same-identity request histories and exact new wire extents without dropping preimages.
# @@Verification={"arc":"state_current_refresh_history_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_accumulation_execution_context
import ../../support/pvm_accumulation_program
import ../../support/state_supplied_services_context
import ../../support/testing_arc_evidence
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_request_keys as state_current_request_keys
import ../../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_service_values as codec_state_service_values
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual signed current host execution and original key capture finish before hash-free admission/projection assertions.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Cached history extents, fixed decoders and detached projection need no primitive.
proc historyCode(hash: ServicePreimageHash, restore: bool): seq[byte] =
  ## Existing current host26 forget and optional funded host25 restoration use actual invocation time and the same declared one-byte preimage.
  let raw = array[32, byte](hash)
  var writable = newSeq[byte](32)
  for i in 0..<32: writable[i] = raw[i] # Exact lookup hash is present in initialized guest memory before either host call.
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), @[10'u8, 26]]
  if restore:
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
        registerImmediate(9, 1), @[10'u8, 25]]:
      instructions.add(instruction) # Re-establish self/hash/length registers before the second real host invocation.
  instructions.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(
      octet) # Maintained whole-code framing owns every instruction/memory byte.
proc fixture(base: OwnedReport, restore: bool): CurrentNamespaceTransition =
  ## Original available history, code request and funded99 enter the original root and genuine signatures.
  let seeds = namespaceSeeds()
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = historyCode(seeds[1].preimages[1].hash, restore)
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = seeds
  namespaceTransitionFixture(base, options)
proc verify(logical: CurrentLogicalState, restore: bool) =
  ## Old logical hash/length identity stays fixed while all current history slots come from the actual authenticated successor.
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  let request = inventory.inventoryRequestAt(InventoryServiceIndex(1), InventoryRequestIndex(1)).value
  assert uint32(request.length) == 1
  if restore:
    assert request.history.state == RequestState.Reavailable
    assert uint32(request.history.originalFrom) == 1 and uint32(request.history.removedAt) == 2 and
        uint32(request.history.restoredAt) == 2
  else:
    assert request.history.state == RequestState.Unavailable
    assert uint32(request.history.availableFrom) == 1 and uint32(request.history.unavailableFrom) == 2
proc cycle(plan: CurrentLogicalRefreshPlan, restore: bool) =
  ## Retire complete current captures and detached request-history/code payload copies on both actual transition branches.
  let logical = executeCurrentLogicalRefresh(plan).value
  verify(logical, restore)
  assert copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value[1].preimages[1].value == @[77'u8]
proc main() {.raises.} =
  ## Neither branch creates/removes physical identities; even unavailable content stays present until the distinct later expunge rule.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let forgotten = fixture(base, false)
  let restored = fixture(base, true)
  let first = namespaceRefreshStages(forgotten)
  let second = namespaceRefreshStages(restored)
  for restore in [false, true]:
    let source = if restore: restored else: forgotten
    let stages = if restore: second else: first
    let key = stages.keys.currentRequestKeyAt(InventoryServiceIndex(1), InventoryRequestIndex(1)).value
    let original = source.parent.logicalParentInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value
    assert original.lookup(key).value.byteLength == 5
    assert source.update.currentUpdateState.lookup(key).value.byteLength == (if restore: 13 else: 9)
    fail(1)
    let info = stages.reconstruction.refreshPlanInfo.value
    assert info.wireBytes == (if restore: 248'u64 else: 244'u64)
    assert stages.identities.identityInfo.value.entries == 34
    var old = namespaceRefreshLimits
    old.wireBytes = ByteLimit(240)
    let refused = planCurrentRefresh(stages.keys, old)
    assert refused.error == CurrentRefreshPlanError.LimitExceeded and refused.refusedPhase ==
        CurrentRefreshRefusal.Wire
    old.wireBytes = ByteLimit(info.wireBytes)
    assert planCurrentRefresh(stages.keys, old).error == CurrentRefreshPlanError.None and calls() == 0
    fail(0)
    let logical = executeCurrentLogicalRefresh(stages.complete).value
    verify(logical, restore)
    let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
    let metadata = inventory.inventoryServiceAt(InventoryServiceIndex(1)).value.metadata
    assert uint32(metadata.storageItems) == 8 and uint64(metadata.storageBytes) == uint64(
        source.services[1].metadata.storageBytes)
    assert uint32(metadata.lastAccumulation) == 2
    assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
        source.update.currentUpdateState)
    fail(1)
    var copied = copySuppliedServices(logical.currentLogicalInventory.value,
        suppliedServicesTestLimits).value
    assert copied[1].preimages[1].value == @[77'u8]
    copied[1].requests[1].history = requestedHistory()
    verify(logical, restore)
    assert calls() == 0
    fail(0)
  for i in 0..<25:
    cycle(first.complete, false)
    cycle(second.complete, true)
  let before = getOccupiedMem()
  for i in 0..<1000:
    cycle(first.complete, false)
    cycle(second.complete, true)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_history", 1000, before, finalBytes)
  echo "state-current-refresh-history: ok"
try:
  main()
except:
  quit(2) # Only real current host histories and complete source-bound matching qualify this continuation witness.
