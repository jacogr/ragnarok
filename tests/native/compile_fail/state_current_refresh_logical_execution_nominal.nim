# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Earlier admitted sources cannot bypass complete current frozen qualification.
# @@Verification={"group":"nominal","expected":"CurrentLogicalRefreshPlan","early":["executeCurrentLogicalRefresh(","[1] expected: CurrentLogicalRefreshPlan but got: CurrentRefreshPlan"]}
import ../../../src/state/[current_logical_refresh, current_refresh_plan]
discard executeCurrentLogicalRefresh(default(CurrentRefreshPlan))
