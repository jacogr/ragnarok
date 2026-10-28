# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current planning/source/policy/result authority stays private and guarded.
# @@Verification={"group":"privacy","expected":"initialized"}
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
var owner: CurrentLogicalRefreshPlan
discard owner.initialized
