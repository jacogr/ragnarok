# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-source certified footprints bind economic observations without treating uncovered accounts as invalid state.
# @@Verification={"arc": "state_service_deposit_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, service_deposit_context, arc_evidence]
import ../../../src/state/[service_deposit, account_deposit, footprint_audit, service_directory, inventory]
import ../../../src/codec/state_accounts
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after all real independent test certificates are built.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observation must read only fixed source-bound metadata and checked equations.
proc cycle(source: ServiceDepositTestSource) =
  ## Retire one fixed observation and both retained evidence owners each cycle.
  let result = observeServiceDeposit(source.footprints, source.directory, ServiceIndex(7), depositTestSchedule)
  assert uint64(result.value.serviceDepositInfo.value.minimum) == 469
proc main() {.raises.} =
  ## Distinct complete maps independently vary pool coverage and gratis while keeping correct footprint metadata.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = depositTestSource(fixture, services)
  let other = depositTestSource(fixture, services)
  services[0].metadata.balance = AccountBalance(100)
  let uncovered = depositTestSource(fixture, services)
  services[0].metadata.balance = AccountBalance(449)
  let protected = depositTestSource(fixture, services)
  services[0].metadata.depositOffset = AccountBalance(469)
  let gratis = depositTestSource(fixture, services)
  fail(1)
  let result = observeServiceDeposit(source.footprints, source.directory, ServiceIndex(7), depositTestSchedule)
  assert result.error == ServiceDepositError.None
  let selected = result.value
  let info = selected.serviceDepositInfo.value
  assert uint32(info.service) == 7 and uint64(info.minimum) == 469 and info.covered
  assert uint32(info.footprint.items) == 3 and uint64(info.footprint.bytes) == 121
  assert uint64(info.liquid) == 1000 and uint64(info.protected) == 20 and uint64(info.gratis) == 0
  assert sameStateInventory(selected.depositFootprints.value.footprintInventory.value,
      selected.depositDirectory.value.directoryInventory.value)
  let under = observeServiceDeposit(uncovered.footprints, uncovered.directory, ServiceIndex(7), depositTestSchedule)
  assert under.error == ServiceDepositError.None and
      not under.value.serviceDepositInfo.value.covered
  assert observeServiceDeposit(protected.footprints, protected.directory, ServiceIndex(7),
      depositTestSchedule).value.serviceDepositInfo.value.covered
  assert uint64(observeServiceDeposit(gratis.footprints, gratis.directory, ServiceIndex(7),
      depositTestSchedule).value.serviceDepositInfo.value.minimum) == 0
  let overflow = observeServiceDeposit(source.footprints, source.directory, ServiceIndex(7),
      AccountDepositSchedule(octet: AccountBalance(high(uint64))))
  assert overflow.error == ServiceDepositError.ArithmeticFailure and overflow.arithmeticError ==
      AccountDepositError.Overflow
  assert observeServiceDeposit(source.footprints, other.directory, ServiceIndex(7),
      depositTestSchedule).error == ServiceDepositError.SourceMismatch
  assert observeServiceDeposit(default(CheckedAccountFootprints), source.directory, ServiceIndex(7),
      depositTestSchedule).error == ServiceDepositError.InvalidFootprints
  assert observeServiceDeposit(source.footprints, default(StateServiceDirectory), ServiceIndex(7),
      depositTestSchedule).error == ServiceDepositError.InvalidDirectory
  assert observeServiceDeposit(source.footprints, source.directory, ServiceIndex(high(uint32)),
      depositTestSchedule).error == ServiceDepositError.NoService
  assert default(ServiceDepositObservation).serviceDepositInfo.error ==
      ServiceDepositError.Uninitialized
  assert default(ServiceDepositObservation).depositFootprints.error ==
      ServiceDepositError.Uninitialized
  assert default(ServiceDepositObservation).depositDirectory.error ==
      ServiceDepositError.Uninitialized
  var copied = info
  copied.minimum = AccountBalance(0)
  assert uint64(selected.serviceDepositInfo.value.minimum) == 469
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm the exact retained certificate path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # No source/evidence owner accumulates after observations retire.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_service_deposit", 1000, before, finalBytes)
  fail(0)
  echo "state-service-deposit: ok"
try:
  main()
except:
  quit(2) # Fixture errors never qualify economic observations.
