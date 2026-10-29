# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-source economic reports preserve explicit policy, uncovered observations, late failure rollback and retired graphs.
# @@Verification={"arc": "state_economics_table_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, service_deposit_context, economic_profile_context, arc_evidence]
import ../../../src/chain/parameters
import ../../../src/state/[economics_table, economic_profile]
import ../../../src/state/service/deposit as service_deposit
import ../../../src/state/account/deposit as account_deposit
import ../../../src/state/footprint_audit
import ../../../src/state/service/directory as service_directory
import ../../../src/state/inventory
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after real source/evidence construction.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Reports must use only fixed certified observations.
const limits = EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096))
proc cycle(source: ServiceDepositTestSource, profile: StateEconomicProfile) =
  ## Retire a whole fixed-row report and its evidence/configuration owners each cycle.
  let table = buildEconomicsTable(source.footprints, source.directory, profile, limits).value
  assert table.economicTableInfo.value.uncovered == 1
proc main() {.raises.} =
  ## Keep valid footprint fields while varying balances and declaration order independently.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let source = depositTestSource(fixture, services)
  let other = depositTestSource(fixture, services)
  let original = inventoryServices()
  let late = depositTestSource(fixture, @[original[1], original[0]])
  let empty = depositTestSource(fixture, @[])
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let overflow = captureEconomicProfile(decodeParameters(economicTestWire(0, 0, high(
      uint64))).value).value
  fail(1)
  let table = buildEconomicsTable(source.footprints, source.directory, profile, limits).value
  let info = table.economicTableInfo.value
  assert info.services == 2 and info.covered == 1 and info.uncovered == 1
  assert uint64(table.economicsFor(ServiceIndex(7)).value.minimum) == 469
  assert not table.economicsFor(ServiceIndex(7)).value.covered
  assert uint64(table.economicsFor(ServiceIndex(8)).value.minimum) == 100
  assert table.economicsFor(ServiceIndex(8)).value.covered
  assert sameStateInventory(table.economicTableFootprints.value.footprintInventory.value,
      source.footprints.footprintInventory.value)
  assert sameStateInventory(table.economicTableDirectory.value.directoryInventory.value,
      source.directory.directoryInventory.value)
  assert sameEconomicProfile(table.economicTableProfile.value, profile)
  assert table.economicTableAt(InventoryServiceIndex(high(uint64))).error ==
      EconomicsTableError.InvalidIndex
  assert table.economicsFor(ServiceIndex(high(uint32))).error == EconomicsTableError.NoService
  let refused = buildEconomicsTable(late.footprints, late.directory, overflow, limits)
  assert refused.error == EconomicsTableError.ObservationFailure
  assert uint32(refused.failedService) == 7 and uint64(refused.failedOrdinal) == 1
  assert refused.observationFailure.error == ServiceDepositError.ArithmeticFailure
  assert refused.observationFailure.arithmeticError == AccountDepositError.Overflow
  var exact = EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(info.retainedBytes))
  assert buildEconomicsTable(source.footprints, source.directory, profile, exact).error ==
      EconomicsTableError.None
  exact.services = ElementLimit(1)
  assert buildEconomicsTable(source.footprints, source.directory, profile, exact).error ==
      EconomicsTableError.LimitExceeded
  exact = limits
  exact.bytes = ByteLimit(info.retainedBytes-1)
  assert buildEconomicsTable(late.footprints, late.directory, overflow, exact).error ==
      EconomicsTableError.LimitExceeded
  assert buildEconomicsTable(default(CheckedAccountFootprints), source.directory, profile,
      limits).error == EconomicsTableError.InvalidFootprints
  assert buildEconomicsTable(source.footprints, default(StateServiceDirectory), profile,
      limits).error == EconomicsTableError.InvalidDirectory
  assert buildEconomicsTable(source.footprints, source.directory, default(StateEconomicProfile),
      limits).error == EconomicsTableError.InvalidProfile
  assert buildEconomicsTable(source.footprints, other.directory, profile, limits).error ==
      EconomicsTableError.SourceMismatch
  assert default(StateEconomicsTable).economicTableInfo.error == EconomicsTableError.Uninitialized
  assert default(StateEconomicsTable).economicTableFootprints.error ==
      EconomicsTableError.Uninitialized
  assert default(StateEconomicsTable).economicTableDirectory.error ==
      EconomicsTableError.Uninitialized
  assert default(StateEconomicsTable).economicTableProfile.error ==
      EconomicsTableError.Uninitialized
  assert default(StateEconomicsTable).economicsFor(ServiceIndex(7)).error ==
      EconomicsTableError.Uninitialized
  assert buildEconomicsTable(empty.footprints, empty.directory, profile, EconomicsTableLimits()).value.economicTableInfo.value.services == 0
  assert calls() == 0
  for i in 0..<25: cycle(source, profile) # Warm the complete fixed-row allocation and owner path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, profile) # Every batch array and temporary per-service observation retires.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_economics_table", 1000, before, finalBytes)
  fail(0)
  echo "state-economics-table: ok"
try:
  main()
except:
  quit(2) # Fixture failure cannot satisfy economic report evidence.
