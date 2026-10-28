# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit full current logical continuation policy and genuine nonempty frozen source.
import ./state_current_refresh_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../src/state/current_profile as state_current_profile
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
const currentLogicalRefreshTestLimits* = CurrentLogicalRefreshLimits(profile: CurrentProfileLimits(
    validators: ElementLimit(1024), bytes: ByteLimit(65536)), globals: parentGlobalsTestLimits,
    logical: suppliedLogicalTestLimits, checks: ElementLimit(36), retainedBytes: ByteLimit(262144))
proc namespaceLogicalRefreshPlan*(base: OwnedReport): LogicalRefreshPlanResult[
    CurrentLogicalRefreshPlan] =
  ## Actual complete selected parent/genuine update and frozen reconstruction are the only source of executable full qualification.
  let source = planCurrentRefresh(namespaceRefreshKeys(base), currentRefreshTestLimits).value
  planCurrentLogicalRefresh(source, currentLogicalRefreshTestLimits)
