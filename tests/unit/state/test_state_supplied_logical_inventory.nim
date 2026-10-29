# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplied raw-key retention is bounded before hashing and remains tied to the exact source through detachment and ARC retirement.
# @@Verification={"arc": "state_supplied_logical_inventory_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, supplied_logical_context, arc_evidence]
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../../src/state/[inventory, manifest, store]
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition,
    service_values as state_service_values]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Short extra-retention limits must refuse before mandatory complete matching hashes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Queries and detached key copies must perform no hashing.
proc cycle(source: ValidatedStateManifest, services: openArray[StateService]) =
  ## Retire the full copied-key and compact fact graph on every cycle.
  let logical = captureSuppliedLogicalInventory(source, services, suppliedLogicalTestLimits).value
  assert logical.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(2)).value.len == 2
proc main() {.raises.} =
  ## Independent chapter bytes plus explicit service declarations construct genuine complete manifests.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = inventoryManifest(fixture, services)
  let other = inventoryManifest(fixture, services)
  let captured = captureSuppliedLogicalInventory(source, services, suppliedLogicalTestLimits)
  assert captured.error == SuppliedLogicalError.None
  let owner = captured.value
  let compact = owner.suppliedInventory.value
  assert sameStateSnapshot(compact.inventorySource.value.manifestSource.value,
      source.manifestSource.value)
  assert not sameStateSnapshot(compact.inventorySource.value.manifestSource.value,
      other.manifestSource.value)
  let info = owner.suppliedLogicalInfo.value
  assert info.services == 2 and info.keys == 1 and info.rawKeyBytes == 2
  assert info.retainedBytes == info.descriptorBytes+2
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0), ByteLimit(
      2)).value == @[byte(1), 2]
  services[0].storage[0].key[0] = 99
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0), ByteLimit(
      2)).value == @[byte(1), 2]
  var copied = owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(2)).value
  copied[0] = 88
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0), ByteLimit(
      2)).value[0] == 1
  let changed = captureSuppliedLogicalInventory(source, services, suppliedLogicalTestLimits)
  assert changed.error == SuppliedLogicalError.InventoryFailure
  assert changed.inventoryFailure.error == StateInventoryError.ManifestFailure
  assert changed.inventoryFailure.manifestFailure.error == StateManifestError.MappingMismatch
  services = inventoryServices()
  let omitted = captureSuppliedLogicalInventory(source, [services[0]], suppliedLogicalTestLimits)
  assert omitted.error == SuppliedLogicalError.InventoryFailure
  assert omitted.inventoryFailure.manifestFailure.error == StateManifestError.MappingMismatch
  let duplicate = captureSuppliedLogicalInventory(source, [services[0], services[0]], suppliedLogicalTestLimits)
  assert duplicate.inventoryFailure.manifestFailure.compositionError ==
      StateCompositionError.DuplicateKey
  services[0].captured = @[default(ServiceValueSnapshot)]
  let opaque = captureSuppliedLogicalInventory(source, services, suppliedLogicalTestLimits)
  assert opaque.inventoryFailure.manifestFailure.error == StateManifestError.OpaqueValues
  services = inventoryServices()
  services[0].storage[0].key = @[]
  let emptySource = inventoryManifest(fixture, services)
  let emptyOwner = captureSuppliedLogicalInventory(emptySource, services,
      suppliedLogicalTestLimits).value
  assert emptyOwner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(0)).value.len == 0
  services = inventoryServices()
  var exact = suppliedLogicalTestLimits
  exact.keys = ElementLimit(info.keys)
  exact.rawKeyBytes = ByteLimit(info.rawKeyBytes)
  exact.bytes = ByteLimit(info.retainedBytes)
  assert captureSuppliedLogicalInventory(source, services, exact).error == SuppliedLogicalError.None
  fail(1)
  for phase in 0..<4:
    var short = exact
    case phase
    of 0: short.keys = ElementLimit(0)
    of 1: short.rawKeyBytes = ByteLimit(1)
    of 2: short.bytes = ByteLimit(info.retainedBytes-1)
    else: short.inventory.manifest.storageKeyBytes = ByteLimit(1)
    assert captureSuppliedLogicalInventory(source, services, short).error ==
        SuppliedLogicalError.LimitExceeded
  assert calls() == 0
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0), ByteLimit(
      1)).error == SuppliedLogicalError.LimitExceeded
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(high(uint64)), InventoryStorageIndex(0),
      ByteLimit(2)).error == SuppliedLogicalError.InvalidIndex
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(1), InventoryStorageIndex(0), ByteLimit(
      2)).error == SuppliedLogicalError.InvalidIndex
  assert owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(high(uint64)),
      ByteLimit(2)).error == SuppliedLogicalError.InvalidIndex
  assert default(SuppliedLogicalInventory).suppliedInventory.error ==
      SuppliedLogicalError.Uninitialized
  assert default(SuppliedLogicalInventory).suppliedLogicalInfo.error ==
      SuppliedLogicalError.Uninitialized
  assert default(SuppliedLogicalInventory).copySuppliedStorageKey(InventoryServiceIndex(0),
      InventoryStorageIndex(0), ByteLimit(2)).error == SuppliedLogicalError.Uninitialized
  assert captureSuppliedLogicalInventory(default(ValidatedStateManifest), [], exact).error ==
      SuppliedLogicalError.InvalidSource
  assert calls() == 0
  fail(0)
  for i in 0..<25: cycle(source, services)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_supplied_logical_inventory", 1000, before, finalBytes)
  echo "state-supplied-logical-inventory: ok"
try:
  main()
except:
  quit(2) # Setup failures cannot qualify complete supplied-key ownership or resource evidence.
