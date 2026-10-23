# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual collected refresh plans preserve both source alternatives, original failures, bounded retry and stale-parent refusal.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_logical_context, current_consecutive_context,
    accumulation_current_candidate_context]
import ../../src/app/[current_logical, chain, preparation_worker]
import ../../src/state/[current_logical, parent_logical, current_request_keys,
    current_logical_refresh, accumulation_current_update, store]
import ../../src/codec/bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Primitive refusal occurs after preparation has completed, without replacing source or policy.
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(CollectedLogicalPlanResult)
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  var canonical = fixture.chain
  var limits = collectedLogicalTestLimits()
  let plan = planCollectedLogical(canonical, fixture.receipt, fixture.fixture.first.parent, limits)
  assert plan.error == CollectedLogicalError.None
  limits.requests.requests = ElementLimit(0)
  assert planCollectedLogical(canonical, fixture.receipt, fixture.fixture.first.parent,
      limits).failure.error == CollectedLogicalError.RequestFailure
  let original = canonical.stateSnapshot.value
  fail(1)
  assert executeCollectedLogical(canonical, plan.value).error ==
      CollectedLogicalError.RefreshFailure
  fail(0)
  let logical = executeCollectedLogical(canonical, plan.value).value
  assert sameStateSnapshot(original, canonical.stateSnapshot.value)
  assert executeCollectedLogical(canonical, default(CollectedLogicalPlan)).error ==
      CollectedLogicalError.InvalidPlan
  let absent = planCollectedLogical(canonical, default(PreparationCompletion),
      fixture.fixture.first.parent, collectedLogicalTestLimits())
  assert absent.error == CollectedLogicalError.NoCompletion and absent.failure.error ==
      CollectedLogicalError.NoCompletion
  let update = fixture.receipt.currentValue.value
  canonical.installPrepared(update)
  assert executeCollectedLogical(canonical, plan.value).error == CollectedLogicalError.StaleUpdate
  let child = currentEmptyChild(update.currentUpdateChild)
  var policies = currentCandidateLimits()
  policies.completion.composition.validators.services = ElementLimit(2)
  let receipt = collectNative(canonical, currentWire(child), [], policies)
  let continued = planCollectedLogical(canonical, receipt, logical, collectedLogicalTestLimits())
  assert continued.error == CollectedLogicalError.None
  assert executeCollectedLogical(canonical, continued.value).error == CollectedLogicalError.None
  echo "application-collected-refresh-plans: ok"
try:
  main()
except:
  quit(2) # Ordinary source/worker errors cannot qualify as a strict contract failure.
