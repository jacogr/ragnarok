# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed original and successor maps preserve authored untouched namespaces and exact account footprints.
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_namespace_context
import ../../support/codec_service_namespace_seed
import ../../support/state_accumulation_current_chain_context
import ../../support/state_current_checkpoint_context
import ../../support/state_parent_profile_context
import ../../support/state_parent_globals_context
import ../../support/codec_supplied_logical_context
import ../../support/state_current_state_context
import ../../support/state_inventory_context
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/state/parent_profile as state_parent_profile
import ../../../src/state/parent_globals as state_parent_globals
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/store as state_store
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
proc verify(view: ChainView, seeds: openArray[ServiceNamespaceSeed]) =
  ## Only the original selected complete snapshot may match supplied namespaces.
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let services = currentNamespaceServices(profile.parentContext.value.state, seeds)
  let parent = captureLogicalParent(globals, services, suppliedLogicalTestLimits).value
  assert parent.logicalParentInventory.value.suppliedLogicalInfo.value.services == 2
  for i in 0..<services.len:
    assert uint32(services[i].metadata.storageItems) == 6
    assert uint64(services[i].metadata.storageBytes) == (if i == 0: 236'u64 else: 233'u64)
    assert services[i].storage.len == 2 and services[i].preimages.len == 2 and services[
        i].requests.len == 2
proc main() {.raises.} =
  ## Roots and every block/report signature are authored with the new namespaces already present.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let seeds = namespaceSeeds()
  let fixture = currentChainFixture(base, available = true, completeState = true,
      serviceNamespaces = seeds)
  assert fixture.entries.len == 30
  verify(fixture.currentChainSeeded, seeds)
  let update = currentCheckpointPrepared(fixture)
  verify(update.currentUpdateView, seeds)
  let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(1024),
      bytes: ByteLimit(65536))).value
  let globals = qualifyCurrentGlobals(profile, parentGlobalsTestLimits).value
  let services = currentNamespaceServices(update.currentUpdateState, seeds)
  let current = qualifyCurrentState(globals, services, inventoryCaptureLimits).value
  assert captureCurrentLogicalState(current, services, suppliedLogicalTestLimits).error ==
      CurrentLogicalError.None
  let legacy = currentChainFixture(base)
  assert legacy.entries.len == 18 # Legacy C250 sentinel and namespace-empty defaults stay intact.
  let ordinary = currentChainFixture(base, completeState = true)
  assert ordinary.entries.len == 18
  echo "state-current-namespace-seed: ok"
try:
  main()
except:
  quit(2) # Invalid signatures, current preparation or complete-map matching fail fixture qualification.
