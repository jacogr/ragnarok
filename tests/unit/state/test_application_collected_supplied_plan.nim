# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen plans bind exact actual native receipts, original child profiles and policies before supplied namespace matching.
import std/[assertions, syncio]
import ../../support/[collected_native_context, current_namespace_refresh_context]
import ../../../src/app/[collected_supplied_plan, collected_update, preparation_worker, current_block_input]
import ../../../src/state/[current_profile, current_globals, accumulation_current_update, store]
import ../../../src/codec/bounded
proc main() {.raises.} =
  ## Actual collected execution is the only target; caller policy mutation and default sources grant no substitute.
  let fixture = collectedNativeFixture()
  let policy = namespaceLogicalLimits()
  let limits = CollectedSuppliedLimits(profile: policy.profile, globals: policy.globals,
      logical: policy.logical)
  let result = planCollectedSupplied(fixture.chain, fixture.receipt, limits)
  assert result.error == CollectedSuppliedPlanError.None
  let plan = result.value
  assert sameStateSnapshot(plan.collectedSuppliedUpdate.value.currentUpdateState,
      fixture.receipt.currentValue.value.currentUpdateState)
  var changed = plan.collectedSuppliedLimits.value
  changed.logical.keys = ElementLimit(0)
  assert uint64(plan.collectedSuppliedLimits.value.logical.keys) > 0
  var short = limits
  short.profile.bytes = ByteLimit(0)
  assert planCollectedSupplied(fixture.chain, fixture.receipt, short).profileFailure.error ==
      CurrentProfileError.LimitExceeded
  short = limits
  short.globals.totalBytes = ByteLimit(0)
  assert planCollectedSupplied(fixture.chain, fixture.receipt, short).error ==
      CollectedSuppliedPlanError.GlobalsFailure
  let empty = default(PreparationCompletion)
  assert planCollectedSupplied(fixture.chain, empty, limits).admissionFailure.error ==
      CollectedUpdateError.NoCompletion
  let missing = default(CollectedSuppliedPlan)
  assert missing.collectedSuppliedUpdate.error == CollectedSuppliedPlanError.Uninitialized
  assert missing.collectedSuppliedLimits.error == CollectedSuppliedPlanError.Uninitialized
  assert missing.collectedSuppliedGlobals.error == CollectedSuppliedPlanError.Uninitialized
  echo "application-collected-supplied-plan: ok"
try:
  main()
except:
  quit(2) # Ordinary fixture failures cannot create a frozen target.
