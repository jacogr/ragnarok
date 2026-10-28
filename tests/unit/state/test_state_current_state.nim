# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact supplied-inventory qualification on genuine complete current successors refuses substitutions and detaches inputs.
# @@Verification={"arc": "state_current_state_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_checkpoint_context
import ../../support/state_current_typed_context
import ../../support/state_accumulation_current_chain_context
import ../../support/state_inventory_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/manifest as state_manifest
import ../../../src/state/inventory as state_inventory
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Query assertions disable hashing only after mandatory exact matching/capture completes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Retained accessors cannot rehash original current state.
const
  projection = CurrentProfileLimits(validators: ElementLimit(1024), bytes: ByteLimit(65536))
  globalsLimits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
proc qualified(source: PreparedCurrentChainUpdate): CurrentGlobalSerialization =
  ## Derive the profile from this exact authenticated update before all-global validation.
  qualifyCurrentGlobals(captureCurrentProfile(source, projection).value, globalsLimits).value
proc cycle(source: CurrentGlobalSerialization, services: openArray[StateService]) =
  ## Retire detached compact rows and both retained owners on every iteration.
  let state = qualifyCurrentState(source, services, inventoryCaptureLimits).value
  assert state.currentStateInventory.value.inventoryInfo.value.services == 2
proc verify(source: PreparedCurrentChainUpdate) =
  ## Supplied authored services are verified against the original complete successor, never a stripped replacement map.
  let globals = qualified(source)
  var services = currentSuppliedServices(source.currentUpdateState)
  let result = qualifyCurrentState(globals, services, inventoryCaptureLimits)
  assert result.error == CurrentStateError.None
  let retained = result.value.currentStateInventory.value
  assert sameStateSnapshot(retained.inventorySource.value.manifestSource.value,
      source.currentUpdateState)
  assert sameStateSnapshot(result.value.currentStateGlobals.value.qualifiedGlobals.value.globalSource.value,
      source.currentUpdateState)
  let other = qualifyCurrentState(globals, services, inventoryCaptureLimits).value
  assert not sameStateInventory(other.currentStateInventory.value, retained)
  let originalBalance = uint64(services[0].metadata.balance)
  services[0].metadata.balance = AccountBalance(originalBalance xor 1)
  let changed = qualifyCurrentState(globals, services, inventoryCaptureLimits)
  assert changed.error == CurrentStateError.ManifestFailure
  assert changed.manifestFailure.error == StateManifestError.MappingMismatch
  assert uint64(retained.inventoryServiceAt(InventoryServiceIndex(0)).value.metadata.balance) == originalBalance
  services = currentSuppliedServices(source.currentUpdateState)
  assert qualifyCurrentState(globals, [services[0]],
      inventoryCaptureLimits).manifestFailure.error == StateManifestError.MappingMismatch
  assert qualifyCurrentState(globals, [services[0], services[0]],
      inventoryCaptureLimits).manifestFailure.compositionError == StateCompositionError.DuplicateKey
  var short = inventoryCaptureLimits
  short.facts = ElementLimit(1)
  let refused = qualifyCurrentState(globals, services, short)
  assert refused.error == CurrentStateError.InventoryFailure
  assert refused.inventoryFailure.error == StateInventoryError.LimitExceeded
  short = inventoryCaptureLimits
  short.manifest.serialized.items = ElementLimit(17)
  let bounded = qualifyCurrentState(globals, services, short)
  assert bounded.error == CurrentStateError.ManifestFailure
  assert bounded.manifestFailure.error == StateManifestError.LimitExceeded
  fail(1)
  assert retained.inventoryInfo.value.services == 2
  assert result.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.error ==
      CurrentProfileError.None
  assert calls() == 0
  fail(0)
proc main() {.raises.} =
  ## Genuine signed current candidates supply the producer boundary; default and rollback-sentinel sources refuse precisely.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let ordinary = currentCheckpointPrepared(currentChainFixture(base, available = true,
      completeState = true))
  verify(ordinary)
  verify(currentCheckpointPrepared(currentChainFixture(base, available = true, disputed = true,
      completeState = true)))
  verify(currentCheckpointPrepared(currentChainFixture(base, available = true, ticket = true,
      completeState = true)))
  verify(currentCheckpointPrepared(currentChainFixture(base, available = true, rotated = true,
      completeState = true)))
  assert qualifyCurrentState(default(CurrentGlobalSerialization), [],
      inventoryCaptureLimits).error == CurrentStateError.InvalidGlobals
  assert default(CurrentStateSerialization).currentStateGlobals.error ==
      CurrentStateError.Uninitialized
  assert default(CurrentStateSerialization).currentStateInventory.error ==
      CurrentStateError.Uninitialized
  let old = currentCheckpointPrepared(currentChainFixture(base, available = true))
  assert qualifyCurrentState(qualified(old), currentSuppliedServices(old.currentUpdateState),
      inventoryCaptureLimits).manifestFailure.error == StateManifestError.MappingMismatch
  let source = qualified(ordinary)
  let services = currentSuppliedServices(ordinary.currentUpdateState)
  for i in 0..<25: cycle(source, services)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_state", 1000, before, finalBytes)
  echo "state-current-state: ok"
try:
  main()
except:
  quit(2) # Setup/admission failures cannot qualify supplied-inventory contracts.
