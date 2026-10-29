# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit full current logical continuation policy and genuine nonempty frozen source.
import ./[current_refresh_context, parent_globals_context, supplied_logical_context]
import ../../src/state/current/logical/refresh as current_logical_refresh
import ../../src/state/current/refresh/plan as current_refresh_plan
import ../../src/state/current/profile as current_profile
import ../../src/codec/[bounded, report_owned]
const currentLogicalRefreshTestLimits* = CurrentLogicalRefreshLimits(profile: CurrentProfileLimits(
    validators: ElementLimit(1024), bytes: ByteLimit(65536)), globals: parentGlobalsTestLimits,
    logical: suppliedLogicalTestLimits, checks: ElementLimit(36), retainedBytes: ByteLimit(262144))
proc namespaceLogicalRefreshPlan*(base: OwnedReport): LogicalRefreshPlanResult[
    CurrentLogicalRefreshPlan] =
  ## Actual complete selected parent/genuine update and frozen reconstruction are the only source of executable full qualification.
  let source = planCurrentRefresh(namespaceRefreshKeys(base), currentRefreshTestLimits).value
  planCurrentLogicalRefresh(source, currentLogicalRefreshTestLimits)
