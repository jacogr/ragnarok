# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen export admits exact whole-output resources, survives source retirement and preserves original complete matching after caller mutation.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_supplied_context]
import ../../src/app/[logical_export, collected_supplied_state]
import ../../src/state/[current_logical, supplied_services, supplied_logical_inventory]
import ../../src/codec/[bounded, state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Projection must remain hash-free after complete logical qualification has finished.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe primitive work independently of the frozen output ledger.
proc escaped(): LogicalExportPlan {.raises.} =
  ## Retire all fixture/current/logical activation aliases while preserving only the admitted export owner.
  let fixture = collectedNativeFixture()
  planLogicalExport(suppliedNativeState(fixture), SuppliedServicesLimits(services: ElementLimit(8),
      facts: ElementLimit(128), perValue: ByteLimit(65536), bytes: ByteLimit(1048576))).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalExportResult[LogicalExportPlan])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.projectionError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  var limits = SuppliedServicesLimits(services: ElementLimit(8), facts: ElementLimit(128),
      perValue: ByteLimit(65536), bytes: ByteLimit(1048576))
  fail(1)
  let plan = planLogicalExport(logical, limits).value
  let info = plan.logicalExportInfo.value
  assert info.services == 2 and info.facts > 0 and info.bytes > 0
  var output = executeLogicalExport(plan).value
  assert calls() == 0
  output[0].storage[0].key.add(99'u8)
  output[0].preimages[0].value.add(98'u8)
  output[0].requests = @[]
  let clean = executeLogicalExport(plan).value
  assert clean[0].storage[0].key != output[0].storage[0].key
  assert clean[0].preimages[0].value != output[0].preimages[0].value
  assert clean[0].requests.len > 0 and calls() == 0
  limits.bytes = ByteLimit(info.bytes)
  limits.facts = ElementLimit(info.facts)
  assert planLogicalExport(logical, limits).error == LogicalExportError.None
  limits.bytes = ByteLimit(info.bytes-1)
  assert planLogicalExport(logical, limits).projectionError == SuppliedServicesError.LimitExceeded
  limits.bytes = ByteLimit(high(uint64))
  limits.facts = ElementLimit(0)
  assert planLogicalExport(logical, limits).error == LogicalExportError.ProjectionFailure
  assert executeLogicalExport(plan).error == LogicalExportError.None
  assert executeLogicalExport(default(LogicalExportPlan)).error == LogicalExportError.InvalidPlan
  assert executeSuppliedServices(default(SuppliedServicesPlan)).error ==
      SuppliedServicesError.InvalidPlan
  fail(0)
  assert executeCollectedSupplied(fixture.chain, suppliedNativePlan(fixture), clean).error ==
      CollectedSuppliedError.None
  let retained = escaped()
  assert executeLogicalExport(retained).value.len == 2
  echo "application-logical-export-plans: ok"
try:
  main()
except:
  quit(2) # Setup or matching failure cannot impersonate strict extraction rejection.
