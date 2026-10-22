# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-source supervisor batches preserve all decisions, complete absence, bounded allocation and retired owners.
# @@Verification={"arc": "state_supervision_table_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, service_directory_context, arc_evidence]
import ../../../src/state/[supervision_table, service_supervision, service_directory, inventory]
import ../../../src/codec/[bounded, state_accounts, state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashing after complete directory fixture construction.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Verify batch construction and queries never hash payloads.
const limits = SupervisionTableLimits(services: ElementLimit(3), bytes: ByteLimit(4096))
proc cycle(source: StateServiceDirectory) =
  ## Retire the complete batch's array and retained directory each cycle.
  let table = buildSupervisionTable(source, limits).value
  assert table.supervisionTableInfo.value.services == 3
proc main() {.raises.} =
  ## Build one complete source carrying all three independently specified selection reasons.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[1].metadata.supervisorCreated = AccountSlot(3)
  services.add(StateService(service: ServiceIndex(9), metadata: ServiceMetadata(
      supervisor: ServiceIndex(99))))
  let inventory = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  let source = buildStateServiceDirectory(inventory, directoryTestLimits).value
  services = @[]
  let empty = buildStateServiceDirectory(captureStateInventory(inventoryManifest(fixture, services),
      services, inventoryCaptureLimits).value, directoryTestLimits).value
  fail(1)
  let table = buildSupervisionTable(source, limits).value
  let info = table.supervisionTableInfo.value
  assert info.services == 3 and info.designated == 1 and info.absent == 1 and info.recreated == 1
  assert sameStateInventory(table.supervisionTableDirectory.value.directoryInventory.value, inventory)
  assert uint32(table.supervisionFor(ServiceIndex(7)).value.effective) == 7
  assert table.supervisionFor(ServiceIndex(8)).value.decision ==
      SupervisionDecision.RecreatedNominee
  assert table.supervisionFor(ServiceIndex(9)).value.decision == SupervisionDecision.AbsentNominee
  for i in 0..<3:
    let batch = table.supervisionTableAt(InventoryServiceIndex(uint64(i))).value
    let individual = resolveServiceSupervision(source, batch.service).value.supervisionInfo.value
    assert uint32(batch.effective) == uint32(individual.effective) and batch.decision ==
        individual.decision # Batch preserves exact single-row semantics.
  assert table.supervisionFor(ServiceIndex(high(uint32))).error == SupervisionTableError.NoService
  assert table.supervisionTableAt(InventoryServiceIndex(high(uint64))).error ==
      SupervisionTableError.InvalidIndex
  var exact = SupervisionTableLimits(services: ElementLimit(3), bytes: ByteLimit(
      info.retainedBytes))
  assert buildSupervisionTable(source, exact).error == SupervisionTableError.None
  exact.services = ElementLimit(2)
  assert buildSupervisionTable(source, exact).error == SupervisionTableError.LimitExceeded
  exact = limits
  exact.bytes = ByteLimit(info.retainedBytes-1)
  assert buildSupervisionTable(source, exact).error == SupervisionTableError.LimitExceeded
  assert buildSupervisionTable(default(StateServiceDirectory), limits).error ==
      SupervisionTableError.InvalidSource
  assert default(StateSupervisionTable).supervisionTableInfo.error ==
      SupervisionTableError.Uninitialized
  assert default(StateSupervisionTable).supervisionTableDirectory.error ==
      SupervisionTableError.Uninitialized
  assert default(StateSupervisionTable).supervisionFor(ServiceIndex(7)).error ==
      SupervisionTableError.Uninitialized
  assert buildSupervisionTable(empty, SupervisionTableLimits()).value.supervisionTableInfo.value.services == 0
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm exact array construction and retirement.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Complete fixed-row batches retire without leaked source owners.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_supervision_table", 1000, before, finalBytes)
  fail(0)
  echo "state-supervision-table: ok"
try:
  main()
except:
  quit(2) # Fixture failure cannot qualify the completed batch.
