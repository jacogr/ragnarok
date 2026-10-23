# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine collected successors select original compact inventory and child time for complete logical code observations.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_supplied_context]
import ../../src/app/logical_code
import ../../src/state/[current_logical, current_state, code_availability, inventory, supplied_logical_inventory]
import ../../src/codec/[bounded, state_requests]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Real backend failures remain nested under the complete logical code stage.
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalCodeResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.codeFailure
    return
  if mode == "source":
    discard default(LogicalCodeAvailability).logicalCodeSource
    return
  if mode == "table":
    discard default(LogicalCodeAvailability).logicalCodeTable
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let limits = CodeAvailabilityLimits(services: ElementLimit(2), visits: ElementLimit(128),
      descriptors: ByteLimit(65536), perCode: ByteLimit(65536), totalCodeBytes: ByteLimit(131072))
  let paired = auditLogicalCodeAvailability(logical, limits).value
  let table = paired.logicalCodeTable
  let report = table.codeAvailabilityInfo.value
  assert report.services == 2 and report.present > 0 and report.available > 0
  assert uint32(report.slot) == logical.currentLogicalContext.value.slot
  assert sameStateInventory(table.codeAvailabilityInventory.value,
      logical.currentLogicalSource.value.currentStateInventory.value)
  assert not sameStateInventory(table.codeAvailabilityInventory.value,
      logical.currentLogicalInventory.value.suppliedInventory.value)
  assert paired.logicalCodeSource.currentLogicalContext.value.slot ==
      logical.currentLogicalContext.value.slot
  for i in 0..<report.services:
    let code = table.serviceCodeAt(i).value
    if code.state == ServiceCodeState.Available:
      assert uint64(table.copyServiceCode(i, ByteLimit(65536)).value.len) ==
          code.bytes # Actual current fixture program bytes stay tied to the account's selected identity.
  fail(1)
  var short = limits
  short.visits = ElementLimit(0)
  assert auditLogicalCodeAvailability(logical, short).codeFailure.error ==
      CodeAvailabilityError.LimitExceeded
  assert auditLogicalCodeAvailability(logical, limits).codeFailure.error ==
      CodeAvailabilityError.BackendFailure
  assert auditLogicalCodeAvailability(default(CurrentLogicalState), limits).error ==
      LogicalCodeError.InvalidLogical
  fail(0)
  assert auditLogicalCodeAvailability(logical, limits).error == LogicalCodeError.None
  echo "application-logical-code: ok"
try:
  main()
except:
  quit(2) # Fixture or ordinary errors never stand in for a selected guarded extraction failure.
