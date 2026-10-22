# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplied logical current descriptions retain exact original physical/profile provenance and refuse altered/incomplete declarations.
# @@Verification={"arc": "state_current_logical_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_checkpoint_context, current_state_context, current_typed_context,
    accumulation_current_chain_context, supplied_logical_context, supplied_services_context, arc_evidence]
import ../../../src/state/[current_logical, current_state, current_globals, current_profile,
    accumulation_current_update, supplied_logical_inventory, supplied_services, inventory, manifest,
    store, economic_profile]
import ../../../src/codec/[bounded, report_owned, state_composition, state_accounts]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Original producer preparation and complete matching happen before hash-free source/query probes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Retaining provenance and copying already-qualified declarations cannot hash.
proc verify(source: CurrentStateSerialization) =
  ## Original current compact capture and the raw-key companion are different inventories bound to the same original snapshot.
  let original = source.currentStateInventory.value
  let snapshot = original.inventorySource.value.manifestSource.value
  var services = currentSuppliedServices(snapshot)
  let completed = captureCurrentLogicalState(source, services, suppliedLogicalTestLimits)
  assert completed.error == CurrentLogicalError.None
  let owner = completed.value
  let logical = owner.currentLogicalInventory.value
  assert sameStateSnapshot(logical.suppliedInventory.value.inventorySource.value.manifestSource.value, snapshot)
  assert not sameStateInventory(logical.suppliedInventory.value, original)
  assert sameStateInventory(owner.currentLogicalSource.value.currentStateInventory.value, original)
  let expected = captureEconomicProfile(source.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value).value
  let actual = captureEconomicProfile(owner.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value).value
  assert sameEconomicProfile(expected, actual)
  services[0].metadata.balance = AccountBalance(uint64(services[0].metadata.balance) xor 1)
  let changed = captureCurrentLogicalState(source, services, suppliedLogicalTestLimits)
  assert changed.error == CurrentLogicalError.LogicalFailure
  assert changed.logicalFailure.inventoryFailure.manifestFailure.error ==
      StateManifestError.MappingMismatch
  services = currentSuppliedServices(snapshot)
  assert captureCurrentLogicalState(source, [services[0]],
      suppliedLogicalTestLimits).logicalFailure.inventoryFailure.manifestFailure.error ==
      StateManifestError.MappingMismatch
  fail(1)
  var short = suppliedLogicalTestLimits
  short.bytes = ByteLimit(0)
  assert captureCurrentLogicalState(source, services, short).logicalFailure.error ==
      SuppliedLogicalError.LimitExceeded
  let detached = copySuppliedServices(logical, suppliedServicesTestLimits).value
  assert detached.len == 2 and uint32(detached[0].service) == uint32(services[0].service)
  assert sameStateSnapshot(owner.currentLogicalSource.value.currentStateInventory.value.inventorySource.value.manifestSource.value, snapshot)
  assert calls() == 0
  fail(0)
proc cycle(source: CurrentStateSerialization, services: openArray[StateService]) =
  ## Retire every new raw-key/compact owner and retained current producer alias on each cycle.
  let owner = captureCurrentLogicalState(source, services, suppliedLogicalTestLimits).value
  assert owner.currentLogicalInventory.value.suppliedLogicalInfo.value.services == 2
proc main() {.raises.} =
  ## Complete authored ordinary/disputed/ticketed/epoch successors are actual signed current producer outputs.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let source = currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base,
      available = true, completeState = true)))
  verify(source)
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      disputed = true, completeState = true))))
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      ticket = true, completeState = true))))
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true, completeState = true))))
  assert captureCurrentLogicalState(default(CurrentStateSerialization), [],
      suppliedLogicalTestLimits).error == CurrentLogicalError.InvalidState
  assert default(CurrentLogicalState).currentLogicalSource.error ==
      CurrentLogicalError.Uninitialized
  assert default(CurrentLogicalState).currentLogicalInventory.error ==
      CurrentLogicalError.Uninitialized
  let services = currentSuppliedServices(source.currentStateInventory.value.inventorySource.value.manifestSource.value)
  for i in 0..<25: cycle(source, services)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_logical", 1000, before, finalBytes)
  echo "state-current-logical: ok"
try:
  main()
except:
  quit(2) # Failed original producer or supplied matching cannot qualify retained logical parent evidence.
