# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual sources, frozen quotas and selected result authority stay private.
# @@Verification={"group":"privacy","expected":"initialized"}
import ../../../src/state/current_refresh_plan
var owner: CurrentRefreshPlan
discard owner.initialized
