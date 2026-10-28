# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit complete supplied host qualification policies and genuine native fixture composition.
import ./app_collected_native_context
import ./state_current_namespace_refresh_context
import ../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../src/state/current_logical as state_current_logical
proc collectedSuppliedTestLimits*(): CollectedSuppliedLimits =
  ## Whole map and retained raw-key policies are independently stated by the maintained namespace fixture.
  let policy = namespaceLogicalLimits()
  CollectedSuppliedLimits(profile: policy.profile, globals: policy.globals, logical: policy.logical)
proc suppliedNativePlan*(fixture: CollectedNativeFixture): CollectedSuppliedPlan =
  ## Use only its actual native receipt and original chain; no independently replaced snapshot enters planning.
  planCollectedSupplied(fixture.chain, fixture.receipt, collectedSuppliedTestLimits()).value
proc suppliedNativeState*(fixture: CollectedNativeFixture): CurrentLogicalState =
  ## Complete caller-provided namespaces remain subject to whole actual map matching and raw-key capture.
  executeCollectedSupplied(fixture.chain, suppliedNativePlan(fixture), fixture.declarations).value
