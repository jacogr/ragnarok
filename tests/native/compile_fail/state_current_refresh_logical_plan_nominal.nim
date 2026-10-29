# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Earlier admitted sources cannot bypass complete current frozen qualification.
# @@Verification={"group":"nominal","expected":"CurrentRefreshPlan","early":["planCurrentLogicalRefresh(","[1] expected: CurrentRefreshPlan but got: CurrentRequestKeys"]}
import ../../../src/state/current/logical/refresh as current_logical_refresh
import ../../../src/state/current/request_keys as current_request_keys
discard planCurrentLogicalRefresh(default(CurrentRequestKeys), CurrentLogicalRefreshLimits())
