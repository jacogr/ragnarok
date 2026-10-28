# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable logical facts retain exact complete source provenance with independent preflight and ARC checks.
# @@Verification={"arc": "state_inventory_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/testing_arc_evidence
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_service_values as codec_state_service_values
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observer counters and optionally refuse all hashes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Measure precise preflight/backend boundaries independently of result tags.
proc after(successes: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse only after the whole existing manifest matcher has completed.
proc cycle(source: ValidatedStateManifest, services: seq[StateService]) =
  ## Retire captured facts and rejected inputs before allocator observation.
  let inventory = captureStateInventory(source, services, inventoryCaptureLimits).value
  assert inventory.inventoryInfo.value.facts == 5
  assert inventory.inventoryServiceAt(InventoryServiceIndex(high(uint64))).error ==
      StateInventoryError.InvalidIndex
proc main() {.raises.} =
  ## Authenticate authored logical declarations once, then exercise each bound public fact family.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = inventoryManifest(fixture, services)
  let result = captureStateInventory(source, services, inventoryCaptureLimits)
  assert result.error == StateInventoryError.None
  let inventory = result.value
  let info = inventory.inventoryInfo.value
  assert info.services == 2 and info.facts == 5
  assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
      source.manifestSource.value)
  let first = InventoryServiceIndex(0)
  assert uint32(inventory.inventoryServiceAt(first).value.service) == 7
  assert uint64(inventory.inventoryServiceAt(first).value.metadata.storageBytes) == 121
  let storage = inventory.inventoryStorageAt(first, InventoryStorageIndex(0)).value
  assert storage.keyBytes == 2 and storage.valueBytes == 1
  let preimage = inventory.inventoryPreimageAt(first, InventoryPreimageIndex(0)).value
  assert preimage.bytes == 3
  assert source.manifestSource.value.lookup(preimage.key).value.bytes == @[byte(97), 98, 99]
  assert uint32(inventory.inventoryRequestAt(first, InventoryRequestIndex(0)).value.length) == 3
  var copied = inventory.inventoryServiceAt(first).value
  copied.metadata.storageBytes = AccountStorageBytes(0)
  assert uint64(inventory.inventoryServiceAt(first).value.metadata.storageBytes) == 121
  var limits = inventoryCaptureLimits
  limits.facts = ElementLimit(info.facts)
  limits.bytes = ByteLimit(info.descriptorBytes)
  assert captureStateInventory(source, services, limits).error == StateInventoryError.None
  fail(1)
  limits.facts = ElementLimit(info.facts-1)
  assert captureStateInventory(source, services, limits).error == StateInventoryError.LimitExceeded
  limits = inventoryCaptureLimits
  limits.bytes = ByteLimit(info.descriptorBytes-1)
  assert captureStateInventory(source, services, limits).error == StateInventoryError.LimitExceeded
  assert calls() == 0
  let refused = captureStateInventory(source, services, inventoryCaptureLimits)
  assert refused.error == StateInventoryError.ManifestFailure
  assert refused.manifestFailure.compositionError == StateCompositionError.BackendFailure
  fail(0)
  discard validateStateManifest(source.manifestGlobals.value, services,
      inventoryManifestLimits).value
  let matching = calls()
  after(matching)
  let late = captureStateInventory(source, services, inventoryCaptureLimits)
  assert late.error == StateInventoryError.KeyFailure
  assert late.keyError == ServiceValueError.BackendFailure
  fail(0)
  assert captureStateInventory(default(ValidatedStateManifest), services,
      inventoryCaptureLimits).error == StateInventoryError.InvalidSource
  assert default(StateInventory).inventoryInfo.error == StateInventoryError.Uninitialized
  for index in [1'u64, high(uint64)]:
    assert inventory.inventoryStorageAt(first, InventoryStorageIndex(index)).error ==
        StateInventoryError.InvalidIndex
    assert inventory.inventoryPreimageAt(first, InventoryPreimageIndex(index)).error ==
        StateInventoryError.InvalidIndex
    assert inventory.inventoryRequestAt(first, InventoryRequestIndex(index)).error ==
        StateInventoryError.InvalidIndex
  assert inventory.inventoryServiceAt(InventoryServiceIndex(2)).error ==
      StateInventoryError.InvalidIndex
  services[0].metadata.balance = AccountBalance(1)
  let mismatch = captureStateInventory(source, services, inventoryCaptureLimits)
  assert mismatch.error == StateInventoryError.ManifestFailure
  assert mismatch.manifestFailure.error == StateManifestError.MappingMismatch
  assert uint64(inventory.inventoryServiceAt(first).value.metadata.balance) == 1000
  services = inventoryServices()
  for i in 0..<25: cycle(source, services) # Warm the exact captured ownership graph before measurement.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services) # Complete compact graphs retire without caller-array or payload retention.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_inventory", 1000, before, finalBytes)
  echo "state-inventory: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot replace a successful provenance or lifetime verdict.
