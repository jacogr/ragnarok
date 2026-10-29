# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen plans bind exact actual native receipts, original child profiles and policies before supplied namespace matching.
import std/[assertions, syncio]
import ../../support/[collected_native_context, current_namespace_refresh_context]
import ../../../src/app/collected/supplied/plan as collected_supplied_plan
import ../../../src/app/collected/update as collected_update
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/state/current/[profile as current_profile, globals as current_globals]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
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
