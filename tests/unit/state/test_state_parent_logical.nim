# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full supplied logical seed preserves exact selected physical/history/parameter/finality provenance and atomic matching/resource refusal.
# @@Verification={"arc": "state_parent_logical_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, current_typed_context,
    parent_profile_context, parent_globals_context, supplied_logical_context,
    supplied_services_context, arc_evidence]
import ../../../src/state/parent/[profile as parent_profile, globals as parent_globals,
    logical as parent_logical]
import ../../../src/state/[global_snapshot, manifest, inventory]
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/state/store
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[composition as state_composition, accounts as state_accounts]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashing only after mandatory full supplied-map matching.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Fixed source queries, detached reconstruction and cached manifest refusal perform no hashes.
proc cycle(source: SelectedParentGlobals, services: openArray[StateService]) =
  ## Retire complete supplied raw-key/compact and original selected-owner graphs every cycle.
  let owner = captureLogicalParent(source, services, suppliedLogicalTestLimits).value
  assert owner.logicalParentInventory.value.suppliedLogicalInfo.value.services == 2
proc verify(view: ChainView) =
  ## Every declaration remains supplied information, exhaustively matched to the original selected physical state.
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let snapshot = profile.parentContext.value.state
  var services = currentSuppliedServices(snapshot)
  let result = captureLogicalParent(globals, services, suppliedLogicalTestLimits)
  assert result.error == ParentLogicalError.None
  let owner = result.value
  let logical = owner.logicalParentInventory.value
  assert sameStateSnapshot(logical.suppliedInventory.value.inventorySource.value.manifestSource.value, snapshot)
  assert sameChainView(owner.logicalParentGlobals.value.parentGlobalsProfile.value.copyParentView(
      parentProfileTestLimits.viewBytes).value, view)
  services[0].metadata.balance = AccountBalance(uint64(services[0].metadata.balance) xor 1)
  let changed = captureLogicalParent(globals, services, suppliedLogicalTestLimits)
  assert changed.error == ParentLogicalError.ManifestFailure
  assert changed.manifestFailure.error == StateManifestError.MappingMismatch
  services = currentSuppliedServices(snapshot)
  assert captureLogicalParent(globals, [services[0]],
      suppliedLogicalTestLimits).manifestFailure.error == StateManifestError.MappingMismatch
  assert captureLogicalParent(globals, [services[0], services[0]],
      suppliedLogicalTestLimits).manifestFailure.compositionError ==
      StateCompositionError.DuplicateKey
  var short = suppliedLogicalTestLimits
  short.inventory.facts = ElementLimit(1)
  let refused = captureLogicalParent(globals, services, short)
  assert refused.error == ParentLogicalError.LogicalFailure
  assert refused.logicalFailure.inventoryFailure.error == StateInventoryError.LimitExceeded
  fail(1)
  short = suppliedLogicalTestLimits
  short.inventory.manifest.serialized.items = ElementLimit(17)
  assert captureLogicalParent(globals, services, short).manifestFailure.error ==
      StateManifestError.LimitExceeded
  let copied = copySuppliedServices(logical, suppliedServicesTestLimits).value
  assert copied.len == 2 and uint32(copied[0].service) == 42
  assert sameStateSnapshot(owner.logicalParentGlobals.value.parentGlobals.value.globalSource.value, snapshot)
  assert calls() == 0
  fail(0)
proc main() {.raises.} =
  ## Finalized/unfinalized, dispute/ticket and epoch parent fixtures remain genuine original configured contexts.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let ordinary = currentChainFixture(base, completeState = true)
  verify(genesisView(ordinary.parent))
  verify(ordinary.currentChainSeeded)
  verify(currentChainFixture(base, available = true, disputed = true,
      completeState = true).currentChainSeeded)
  verify(currentChainFixture(base, available = true, ticket = true,
      completeState = true).currentChainSeeded)
  verify(currentChainFixture(base, available = true, rotated = true,
      completeState = true).currentChainSeeded)
  assert captureLogicalParent(default(SelectedParentGlobals), [],
      suppliedLogicalTestLimits).error == ParentLogicalError.InvalidGlobals
  assert default(SelectedLogicalParent).logicalParentGlobals.error ==
      ParentLogicalError.Uninitialized
  assert default(SelectedLogicalParent).logicalParentInventory.error ==
      ParentLogicalError.Uninitialized
  let profile = captureParentProfile(ordinary.currentChainSeeded, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let services = currentSuppliedServices(profile.parentContext.value.state)
  for i in 0..<25: cycle(globals, services)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(globals, services)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_parent_logical", 1000, before, finalBytes)
  echo "state-parent-logical: ok"
try:
  main()
except:
  quit(2) # Failed fixture/matching cannot qualify a complete selected logical parent.
