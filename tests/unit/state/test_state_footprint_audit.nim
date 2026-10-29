# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete sources distinguish mismatched dependent metadata from bounded refusal and ownership.
# @@Verification={"arc": "state_footprint_audit_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, arc_evidence]
import ../../../src/state/[footprint_audit, inventory, manifest, store]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force hash refusal to prove this audit consumes only already captured facts.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count hash calls independently of success reasons.
const limits = FootprintAuditLimits(services: ElementLimit(2), checks: ElementLimit(4))
proc cycle(source: StateInventory) =
  ## Retire a complete audit result and its retained source before allocator observation.
  let checked = auditAccountFootprints(source, limits).value
  assert checked.footprintInfo.value.checks == 4
  assert checked.checkedFootprintAt(InventoryServiceIndex(0)).value.bytes.uint64 == 121
proc main() {.raises.} =
  ## Build structurally valid independent fixtures before disabling all hashing.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services[0].metadata.storageItems = AccountStorageItems(4)
  let wrongItems = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  services[0].metadata.storageBytes = AccountStorageBytes(122)
  let wrongBytes = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = @[]
  let empty = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(1)
  let result = auditAccountFootprints(source, limits)
  assert result.error == FootprintAuditError.None
  let checked = result.value
  assert checked.footprintInfo.value.services == 2
  assert checked.footprintInfo.value.checks == 4
  assert sameStateSnapshot(checked.footprintInventory.value.inventorySource.value.manifestSource.value,
    source.inventorySource.value.manifestSource.value)
  let first = InventoryServiceIndex(0)
  assert uint32(checked.checkedFootprintAt(first).value.items) == 3
  assert uint64(checked.checkedFootprintAt(first).value.bytes) == 121
  assert uint64(checked.checkedFootprintAt(InventoryServiceIndex(1)).value.bytes) == 0
  for index in [2'u64, high(uint64)]:
    assert checked.checkedFootprintAt(InventoryServiceIndex(index)).error ==
        FootprintAuditError.InvalidIndex # No truncated ordinal.
  let items = auditAccountFootprints(wrongItems, limits)
  assert items.error == FootprintAuditError.ItemsMismatch
  assert uint32(items.failedService) == 7 and uint64(items.failedOrdinal) == 0
  let bytes = auditAccountFootprints(wrongBytes, limits)
  assert bytes.error == FootprintAuditError.BytesMismatch
  assert uint32(bytes.failedService) == 7 and uint64(bytes.failedOrdinal) == 0
  assert auditAccountFootprints(source, FootprintAuditLimits(services: ElementLimit(1),
      checks: ElementLimit(4))).error == FootprintAuditError.LimitExceeded
  assert auditAccountFootprints(wrongItems, FootprintAuditLimits(services: ElementLimit(2),
      checks: ElementLimit(3))).error == FootprintAuditError.LimitExceeded
  assert auditAccountFootprints(default(StateInventory), limits).error ==
      FootprintAuditError.InvalidSource
  assert default(CheckedAccountFootprints).footprintInfo.error == FootprintAuditError.Uninitialized
  assert default(CheckedAccountFootprints).footprintInventory.error ==
      FootprintAuditError.Uninitialized
  assert default(CheckedAccountFootprints).checkedFootprintAt(first).error ==
      FootprintAuditError.Uninitialized
  assert auditAccountFootprints(empty, FootprintAuditLimits()).value.footprintInfo.value.services == 0
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm retained-owner extraction before measuring the same path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # No accumulated audit owner or source references survive retirement.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_footprint_audit", 1000, before, finalBytes)
  fail(0)
  echo "state-footprint-audit: ok"
try:
  main()
except:
  quit(2) # Fixture setup failure never satisfies assertion or ownership evidence.
