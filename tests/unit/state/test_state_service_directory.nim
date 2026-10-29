# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-source service lookup preserves capture identity, sorted order, resource preflight and ARC retirement.
# @@Verification={"arc": "state_service_directory_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, arc_evidence]
import ../../../src/state/service/directory as service_directory
import ../../../src/state/inventory
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after fixture capture; directory work is descriptor-only.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe independence from hashing or source reconstruction.
const limits = ServiceDirectoryLimits(services: ElementLimit(16), comparisons: ElementLimit(120),
    bytes: ByteLimit(4096))
proc cycle(source: StateInventory) =
  ## Retire a complete sorted index and its source handles before memory observation.
  let directory = buildStateServiceDirectory(source, limits).value
  assert uint64(directory.findService(ServiceIndex(7)).value) == 1
proc main() {.raises.} =
  ## Capture deliberately descending service declarations before disabling hashing.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let original = inventoryServices()
  var services = @[original[1], original[0]]
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services.add(StateService(service: ServiceIndex(9)))
  let odd = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services.setLen(1)
  let single = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = @[]
  let empty = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(1)
  let result = buildStateServiceDirectory(source, limits)
  assert result.error == ServiceDirectoryError.None
  let directory = result.value
  let info = directory.directoryInfo.value
  assert info.services == 2 and info.comparisonCeiling == 1
  assert sameStateInventory(source, directory.directoryInventory.value)
  assert uint64(directory.findService(ServiceIndex(7)).value) == 1
  assert uint64(directory.findService(ServiceIndex(8)).value) == 0
  let row = directory.directoryServiceAt(DirectoryServiceIndex(0)).value
  assert uint32(row.service) == 7 and uint64(row.ordinal) == 1
  var copied = row
  copied.service = ServiceIndex(99)
  assert uint32(directory.directoryServiceAt(DirectoryServiceIndex(0)).value.service) == 7
  for missing in [0'u32, 6, 9, high(uint32)]:
    assert directory.findService(ServiceIndex(missing)).error ==
        ServiceDirectoryError.NoService # Complete absence never becomes default witness refusal.
  for invalid in [2'u64, high(uint64)]:
    assert directory.directoryServiceAt(DirectoryServiceIndex(invalid)).error ==
        ServiceDirectoryError.InvalidIndex # No narrowing before bounds.
  var exact = ServiceDirectoryLimits(services: ElementLimit(2), comparisons: ElementLimit(1),
      bytes: ByteLimit(info.retainedBytes))
  assert buildStateServiceDirectory(source, exact).error == ServiceDirectoryError.None
  exact.services = ElementLimit(1)
  assert buildStateServiceDirectory(source, exact).error == ServiceDirectoryError.LimitExceeded
  exact = limits
  exact.comparisons = ElementLimit(0)
  assert buildStateServiceDirectory(source, exact).error == ServiceDirectoryError.LimitExceeded
  exact = limits
  exact.bytes = ByteLimit(info.retainedBytes-1)
  assert buildStateServiceDirectory(source, exact).error == ServiceDirectoryError.LimitExceeded
  assert buildStateServiceDirectory(default(StateInventory), limits).error ==
      ServiceDirectoryError.InvalidSource
  assert default(StateServiceDirectory).directoryInfo.error == ServiceDirectoryError.Uninitialized
  assert default(StateServiceDirectory).directoryInventory.error ==
      ServiceDirectoryError.Uninitialized
  assert default(StateServiceDirectory).findService(ServiceIndex(7)).error ==
      ServiceDirectoryError.Uninitialized
  let zero = buildStateServiceDirectory(empty, ServiceDirectoryLimits()).value
  assert zero.directoryInfo.value.services == 0
  assert zero.findService(ServiceIndex(7)).error == ServiceDirectoryError.NoService
  let three = ServiceDirectoryLimits(services: ElementLimit(3), comparisons: ElementLimit(3),
      bytes: ByteLimit(4096))
  assert buildStateServiceDirectory(odd, three).value.directoryInfo.value.comparisonCeiling == 3
  assert buildStateServiceDirectory(odd, ServiceDirectoryLimits(services: ElementLimit(3),
      comparisons: ElementLimit(2), bytes: ByteLimit(4096))).error ==
      ServiceDirectoryError.LimitExceeded
  assert buildStateServiceDirectory(single, ServiceDirectoryLimits(services: ElementLimit(1),
      bytes: ByteLimit(4096))).value.directoryInfo.value.comparisonCeiling == 0
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm the retained descriptor graph before observing the same allocation path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Retire all sorted arrays and source references each cycle.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_service_directory", 1000, before, finalBytes)
  fail(0)
  echo "state-service-directory: ok"
try:
  main()
except:
  quit(2) # Fixture failure cannot satisfy lookup or ownership qualification.
