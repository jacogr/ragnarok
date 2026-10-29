# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen supplied input survives caller mutation/scope retirement and preserves actual qualification, resource and stale-source failures.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_supplied_context]
import ../../src/app/frozen_supplied
import ../../src/app/collected/supplied/[plan as collected_supplied_plan,
    state as collected_supplied_state]
import ../../src/app/chain
import ../../src/state/current/logical as current_logical
import ../../src/state/supplied/services as supplied_services
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/state/store
import ../../src/codec/bounded
import ../../src/codec/state/[composition as state_composition,
    service_values as state_service_values]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Inject backend refusal only after source planning and detached input capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Freezing must neither hash nor qualify the borrowed declarations.
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(FrozenSuppliedResult[FrozenSuppliedInput])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.qualificationFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  var canonical = fixture.chain
  let plan = suppliedNativePlan(fixture)
  var rows = fixture.declarations
  var limits = SuppliedServicesLimits(services: ElementLimit(8), facts: ElementLimit(128),
      perValue: ByteLimit(65536), bytes: ByteLimit(1048576))
  fail(1)
  let frozen = freezeCollectedSupplied(canonical, plan, rows, limits).value
  let info = frozen.frozenSuppliedInfo.value
  assert info.services == rows.len and info.facts > 0 and info.bytes > 0 and calls() == 0
  rows[0].storage[0].key.add(211'u8)
  rows[0].preimages[0].value.add(212'u8)
  rows[0].requests = @[]
  let refused = executeFrozenSupplied(canonical, frozen)
  assert refused.error == FrozenSuppliedError.QualificationFailure
  assert refused.qualificationFailure.error == CollectedSuppliedError.StateFailure
  fail(0)
  assert executeFrozenSupplied(canonical, frozen).error == FrozenSuppliedError.None
  limits.bytes = ByteLimit(info.bytes)
  limits.facts = ElementLimit(info.facts)
  assert freezeCollectedSupplied(canonical, plan, fixture.declarations, limits).error ==
      FrozenSuppliedError.None
  limits.bytes = ByteLimit(info.bytes-1)
  assert freezeCollectedSupplied(canonical, plan, fixture.declarations, limits).error ==
      FrozenSuppliedError.LimitExceeded
  limits.bytes = ByteLimit(high(uint64))
  limits.facts = ElementLimit(info.facts-1)
  assert freezeCollectedSupplied(canonical, plan, fixture.declarations, limits).error ==
      FrozenSuppliedError.LimitExceeded
  let missing = default(FrozenSuppliedInput)
  assert executeFrozenSupplied(canonical, missing).error == FrozenSuppliedError.InvalidPlan
  canonical.installPrepared(plan.collectedSuppliedUpdate.value)
  assert executeFrozenSupplied(canonical, frozen).error == FrozenSuppliedError.StaleUpdate
  echo "application-frozen-supplied: ok"
try:
  main()
except:
  quit(2) # Setup, backend and quota failures cannot satisfy selected runtime guards.
